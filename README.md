![Status](https://img.shields.io/badge/Deprecated-brown)

> [!CAUTION]
> This repository is no longer maintained. See [Pick an SDK](https://docs.xmtp.org/inboxes/pick-an-sdk) for a list of available SDKs.

The documentation below is provided for historical reference only.

# xmtp-flutter

`xmtp-flutter` provides a Dart implementation of an XMTP message API client for use with Flutter apps.

Use `xmtp-flutter` to build with XMTP to send messages between blockchain accounts, including DMs, notifications, announcements, and more.

To keep up with the latest SDK developments, see the [Issues tab](https://github.com/xmtp/xmtp-flutter/issues) in this repo.

To learn more about XMTP and get answers to frequently asked questions, see the [XMTP documentation](https://xmtp.org/docs).

## Quickstart app built with `xmtp-flutter`

Use the [XMTP Flutter quickstart app](https://github.com/xmtp/xmtp-flutter/tree/main/example) as a tool to start building an app with XMTP. This basic messaging app has an intentionally unopinionated UI to help make it easier for you to build with.

## Reference docs

> **View the reference**  
> Access the [Dart client SDK reference documentation](https://pub.dev/documentation/xmtp/latest/xmtp/Client-class.html) on pub.dev.

## Install with Dart Package Manager

```bash
flutter pub add xmtp
```

To see more options, check out the [verified XMTP Dart package](https://pub.dev/packages/xmtp/install).

## Usage overview

The XMTP message API revolves around a message API client (client) that allows retrieving and sending messages to other XMTP network participants. A client must connect to a wallet app on startup. If this is the very first time the client is created, the client will generate a key bundle that is used to encrypt and authenticate messages. The key bundle persists encrypted in the network using an account signature. The public side of the key bundle is also regularly advertised on the network to allow parties to establish shared encryption keys. All of this happens transparently, without requiring any additional code.

```dart
import 'package:xmtp/xmtp.dart' as xmtp;
import 'package:web3dart/credentials.dart';
import 'dart:math';

var wallet = EthPrivateKey.createRandom(Random.secure());
var api = xmtp.Api.create();
var client = await xmtp.Client.createFromWallet(api, wallet);
```

## Use local storage

> **Important**  
> If you are building a production-grade app, be sure to use an architecture that includes a local cache backed by an XMTP SDK.

To learn more, see [Use a local cache](https://xmtp.org/docs/tutorials/performance#use-a-local-cache).

## Create a client

The client has two constructors: `createFromWallet` and `createFromKeys`.

The first time a user uses a new device, they should call `createFromWallet`. This will prompt them
to sign a message to do one of the following:

- Create a new identity (if they're new)
- Enable their existing identity (if they've used XMTP before)

When this succeeds, it configures the client with a bundle of `keys` that can be stored securely on
the device.

```dart
var api = xmtp.Api.create();
var client = await Client.createFromWallet(api, wallet);
await mySecureStorage.save(client.keys.writeToBuffer());
```

The second time a user launches the app, they should call `createFromKeys`
using the stored `keys` from their previous session.

```dart
var stored = await mySecureStorage.load();
var keys = xmtp.PrivateKeyBundle.fromBuffer(stored);
var api = xmtp.Api.create();
var client = await Client.createFromKeys(api, keys);
```

### Configure the client

You can configure the client environment when you call `Api.create()`.

By default, it will connect to a `local` XMTP network.
For important details about connecting to environments,
see [XMTP `production` and `dev` network environments](#xmtp-production-and-dev-network-environments).

### List existing conversations

You can list existing conversations and send them messages.

```dart
var conversations = await client.listConversations();
for (var convo in conversations) {
  debugPrint('Saying GM to ${convo.peer}');
  await client.sendMessage(convo, 'gm');
}
```

These conversations include all conversations for a user **regardless of which app created the conversation.** This functionality provides the concept of an [interoperable inbox](https://xmtp.org/docs/concepts/interoperable-inbox), which enables a user to access all of their conversations in any app built with XMTP.

### Listen for new conversations

You can also listen for new conversations being started in real-time.
This will allow apps to display incoming messages from new contacts.

```dart
var listening = client.streamConversations().listen((convo) {
  debugPrint('Got a new conversation with ${convo.peer}');
});
// When you want to stop listening:
await listening.cancel();
```

### Start a new conversation

You can create a new conversation with any Ethereum address on the XMTP network.

```dart
var convo = await client.newConversation("0x...");
```

### Send messages

To be able to send a message, the recipient must have already created a client at least once and
consequently advertised their key bundle on the network.

Messages are addressed using account addresses.

The message content can be a plain text string. Or you can configure custom content types.
See [Handle different types of content](#handle-different-types-of-content).

```dart
var convo = await client.newConversation("0x...");
await client.sendMessage(convo, 'gm');
```

### List messages in a conversation

You can receive the complete message history in a conversation.

```dart
// Only show messages from the last 24 hours.
var messages = await alice.listMessages(convo,
    start: DateTime.now().subtract(const Duration(hours: 24)));
```

### List messages in a conversation with pagination

It may be helpful to retrieve and process the messages in a conversation page by page.
You can do this by specifying `limit` and `end`, which will return the specified number
of messages sent before that time.

```dart
var messages = await alice.listMessages(convo, limit: 10);
var nextPage = await alice.listMessages(
    convo, limit: 10, end: messages.last.sentAt);
```

### Listen for new messages in a conversation

You can listen for any new messages (incoming or outgoing) in a conversation by calling
`client.streamMessages(convo)`.

A successfully received message (that makes it through decoding and decryption) can be trusted
to be authentic. Authentic means that it was sent by the owner of the `message.sender` account and
that it wasn't modified in transit. The `message.sentAt` time can be trusted to have been set by
the sender.

```dart
var listening = client.streamMessages(convo).listen((message) {
  debugPrint('${message.sender}> ${message.content}');
});
// When you want to stop listening:
await listening.cancel();
```

> **Note**  
> This package does not currently include the `streamAllMessages()` functionality from the [XMTP client SDK for JavaScript](https://github.com/xmtp/xmtp-js) (`xmtp-js`).

## Handle different types of content

When sending a message, you can specify the type of content. This allows you to specify different
types of content than the default (a simple string, `ContentTypeText`).

To learn more about content types, see [Content types with XMTP](https://xmtp.org/docs/concepts/content-types).

Support for other types of content can be added during client construction by registering additional `Codec`s, including a `customCodecs` parameter. Every codec declares a specific content type identifier,
`ContentTypeId`, which is used to signal to the client which codec should be used to process the
content that is being sent or received. See [XIP-5](https://github.com/xmtp/XIPs/blob/main/XIPs/xip-5-message-content-types.md)
for more details on codecs and content types.

Codecs and content types may be proposed as interoperable standards through [XRCs](https://github.com/xmtp/XIPs/blob/main/XIPs/xip-9-composite-content-type.md).

```dart
/// Example [Codec] for sending [int] values around.
final contentTypeInteger = xmtp.ContentTypeId(
  authorityId: "com.example",
  typeId: "integer",
  versionMajor: 0,
  versionMinor: 1,
);
class IntegerCodec extends Codec<int> {
  @override
  xmtp.ContentTypeId get contentType => contentTypeInteger;

  @override
  Future<int> decode(xmtp.EncodedContent encoded) async =>
      Uint8List.fromList(encoded.content).buffer.asByteData().getInt64(0);

  @override
  Future<xmtp.EncodedContent> encode(int decoded) async => xmtp.EncodedContent(
    type: contentType,
    content: Uint8List(8)..buffer.asByteData().setInt64(0, decoded),
    fallback: decoded.toString(),
  );
}

// Using the custom codec to send around an integer.
var client = await Client.createFromWallet(api, wallet, customCodecs:[IntegerCodec()]);
var convo = await client.newConversation("0x...");
await client.sendMessage(convo, "Hey here comes my favorite number:");
await client.sendMessage(convo, 42, contentType: contentTypeInteger);
```

As shown in the example above, you must provide a content fallback value. Use it to provide an alt text-like description of the original content. Providing a content fallback value enables clients that don't support the content type to still display something meaningful.

> **Caution**  
> If you don't provide a content fallback value, clients that don't support the content type will display an empty message. This results in a poor user experience and breaks interoperability.

## Compression

This package currently does not support message content compression.

## 🏗 Breaking revisions

Because `xmtp-flutter` is in active development, you should expect breaking revisions that might require you to adopt the latest SDK release to enable your app to continue working as expected.

XMTP communicates about breaking revisions in the [XMTP Discord community](https://discord.gg/xmtp), providing as much advance notice as possible. Additionally, breaking revisions in an `xmtp-flutter` release will be described on the [Releases page](https://github.com/xmtp/xmtp-flutter/releases).

## XMTP `production` and `dev` network environments

XMTP provides both `production` and `dev` network environments to support the development phases of your project.

The `production` and `dev` networks are completely separate and not interchangeable.
For example, for a given blockchain account, its XMTP identity on `dev` network is completely
distinct from its XMTP identity on the `production` network, as are the messages associated with
these identities. In addition, XMTP identities and messages created on the `dev` network can't be
accessed from or moved to the `production` network, and vice versa.

> **Note**  
> When you [create a client](#create-a-client), it connects to an XMTP `local`
> environment by default. When you create the `Api` used by the `Client`, it must have a valid network `host`.

Here are some best practices for when to use each environment:

- `dev` (`host: "dev.xmtp.network"`): Use to have a client communicate with the `dev` network. As a best practice, use `dev` while developing and testing your app. Follow this best practice to isolate test messages to `dev` inboxes.

- `production` (`host: "production.xmtp.network"`): Use to have a client communicate with the `production` network. As a best practice, use `production` when your app is serving real users. Follow this best practice to isolate messages between real-world users to `production` inboxes.

- `local` (`host: "127.0.0.1"`, default): Use to have a client communicate with an XMTP node you are running locally. For example, an XMTP node developer can use `local` to generate client traffic to test a node running locally.

The `production` network is configured to store messages indefinitely.
XMTP may occasionally delete messages and keys from the `dev` network and will provide
advance notice in the [XMTP Discord community](https://discord.gg/xmtp).

## Publish a new version to pub.dev

1. Determine the next version number based on the [current published version](https://pub.dev/packages/xmtp) in `major.minor.patch` format.
2. Update the `sdkVersion` in `common/api.dart` to use the new version.
3. Update [CHANGELOG.md](https://github.com/xmtp/xmtp-flutter/blob/main/CHANGELOG.md) to include release notes for the new version number.
4. Merge the updates from Steps 2 & 3 into the `main` branch via a Pull Request.
5. Checkout the `main` branch, pull the latest changes & run the following commands replacing `{VERSION_NUMBER}` with the new version.
   ```bash
   git tag -a v{VERSION_NUMBER} -m "xmtp release v{VERSION_NUMBER}"
   git push origin v{VERSION_NUMBER}
   ```
6. Watch the [GitHub Actions](https://github.com/xmtp/xmtp-flutter/actions) and ensure the `Release` Action succeeds, confirming the package has been published.
7. Ensure the new version is up to date at https://pub.dev/packages/xmtp.
