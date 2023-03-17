# xmtp-flutter

![Test](https://github.com/xmtp/xmtp-flutter/actions/workflows/test.yml/badge.svg) ![Status](https://img.shields.io/badge/Project_Status-General_Availability-31CA54)

`xmtp-flutter` provides a Dart implementation of an XMTP message API client for use with Flutter apps.

Use `xmtp-flutter` to build with XMTP to send messages between blockchain accounts, including DMs, notifications, announcements, and more.

This SDK is in **General Availability** status and ready for use in production. 

To keep up with the latest SDK developments, see the [Issues tab](https://github.com/xmtp/xmtp-flutter/issues) in this repo.

To learn more about XMTP and get answers to frequently asked questions, see [FAQ about XMTP](https://xmtp.org/docs/dev-concepts/faq).

![x-red-sm](https://user-images.githubusercontent.com/510695/163488403-1fb37e86-c673-4b48-954e-8460ae4d4b05.png)

## Example app

For a basic demonstration of the core concepts and capabilities of the `xmtp-flutter` client SDK, see the [Example app project](https://github.com/xmtp/xmtp-flutter/tree/main/example).

> **Important**  
> The example app includes a demonstration of how you might approach caching, or offline storage. Be aware that the example app naively performs a full refresh very frequently, **which causes slowdowns**. The underlying `xmtp-flutter` client SDK itself has no performance issues. If you want to provide offline storage in your app, be sure to design your refresh strategies with app performance in mind. Future versions of the example app aim to make this aspect easier to manage.

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

The second time a user launches the app they should call `createFromKeys`
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

These conversations include all conversations for a user **regardless of which app created the conversation.** This functionality provides the concept of an interoperable inbox, which enables a user to access all of their conversations in any app built with XMTP.

You might choose to provide an additional filtered view of conversations. To learn more, see [Handling multiple conversations with the same blockchain address](#handling-multiple-conversations-with-the-same-blockchain-address) and [Filter conversations using conversation IDs and metadata](https://xmtp.org/docs/client-sdk/javascript/tutorials/filter-conversations).

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
See [Different types of content](#different-types-of-content).

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
You can do this by specifying `limit` and `end` which will return the specified number
of messages sent before that time.

```dart
var messages = await alice.listMessages(convo, limit: 10);
var nextPage = await alice.listMessages(
    convo, limit: 10, end: messages.last.sentAt);
```

### Listen for new messages in a conversation

You can listen for any new messages (incoming or outgoing) in a conversation by calling
`client.streamMessages(convo)`.

A successfully received message (that makes it through the decoding and decryption) can be trusted
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
> This package does not currently include the `streamAllMessages()` functionality from the [XMTP client SDK for JavaScript](https://github.com/xmtp/xmtp-js) (xmtp-js).

### Handling multiple conversations with the same blockchain address

With XMTP, you can have multiple ongoing conversations with the same blockchain address.
For example, you might want to have a conversation scoped to your particular app, or even
a conversation scoped to a particular item in your app.

To accomplish this, you can pass a context with a conversationId when you are creating
a conversation. We recommend conversation IDs start with a domain, to help avoid unwanted collisions
between your app and other apps on the XMTP network.

```dart
var friend = "0x123..."; // my friend's address

var workTalk = await client.newConversation(
  friend,
  conversationId: "my.example.com/work",
  metadata: {"title": "Work Talk"},
);
var playTalk = await client.newConversation(
  friend,
  conversationId: "my.example.com/play",
  metadata: {"title": "Play Talk"},
);

var conversations = await client.listConversations();
var myConversations = conversations.where((c) =>
    c.conversationId.startsWith("my.example.com/"));
```

## Different types of content

When sending a message, you can specify the type of content. This allows you to specify different
types of content than the default (a simple string, `ContentTypeText`).

Support for other types of content can be added during client construction by registering additional `Codec`s, including a `customCodecs` parameter. Every codec declares a specific content type identifier,
`ContentTypeId`, which is used to signal to the Client which codec should be used to process the
content that is being sent or received. See [XIP-5](https://github.com/xmtp/XIPs/blob/main/XIPs/xip-5-message-content-types.md)
for more details on codecs and content types.

Codecs and content types may be proposed as interoperable standards through [XRCs](https://github.com/xmtp/XIPs/blob/main/XIPs/xip-9-composite-content-type.md).
If there is a concern that the recipient may not be able to handle a non-standard content type,
the sender can use the contentFallback option to provide a string that describes the content being
sent. If the recipient fails to decode the original content, the fallback will replace it and can be
used to inform the recipient what the original content was.

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

## Compression

This package currently does not support message content compression.

## 🏗 **Breaking revisions**

Because `xmtp-flutter` is in active development, you should expect breaking revisions that might require you to adopt the latest SDK release to enable your app to continue working as expected.

XMTP communicates about breaking revisions in the [XMTP Discord community](https://discord.gg/xmtp), providing as much advance notice as possible. Additionally, breaking revisions in an `xmtp-flutter` release will be described on the [Releases page](https://github.com/xmtp/xmtp-flutter/releases).

## Deprecation

Older versions of the SDK will eventually be deprecated, which means:

1. The network will not support and eventually actively reject connections from clients using deprecated versions.
2. Bugs will not be fixed in deprecated versions.

The following table provides the deprecation schedule.

| Announced  | Effective  | Minimum Version | Rationale                                                                                                         |
| ---------- | ---------- | --------------- | ----------------------------------------------------------------------------------------------------------------- |
| There are no deprecations scheduled for `xmtp-flutter` at this time. |  |          |  |

Bug reports, feature requests, and PRs are welcome in accordance with these [contribution guidelines](https://github.com/xmtp/xmtp-flutter/blob/main/CONTRIBUTING.md).

## XMTP `production` and `dev` network environments

XMTP provides both `production` and `dev` network environments to support the development phases of your project.

The `production` and `dev` networks are completely separate and not interchangeable.
For example, for a given blockchain account, its XMTP identity on `dev` network is completely
distinct from its XMTP identity on the `production` network, as are the messages associated with
these identities. In addition, XMTP identities and messages created on the `dev` network can't be
accessed from or moved to the `production` network, and vice versa.

> **Note**  
> When you [create a client](#create-a-client), it connects to an XMTP `local`
environment by default. When you create the `Api` used by the `Client`, it must have a valid network `host`.

Here are some best practices for when to use each environment:

- `dev` (`host: "dev.xmtp.network"`): Use to have a client communicate with the `dev` network. As a best practice, use `dev` while developing and testing your app. Follow this best practice to isolate test messages to `dev` inboxes.

- `production` (`host: "production.xmtp.network"`): Use to have a client communicate with the `production` network. As a best practice, use `production` when your app is serving real users. Follow this best practice to isolate messages between real-world users to `production` inboxes.

- `local` (`host: "127.0.0.1"`, default): Use to have a client communicate with an XMTP node you are running locally. For example, an XMTP node developer can use `local` to generate client traffic to test a node running locally.

The `production` network is configured to store messages indefinitely.
XMTP may occasionally delete messages and keys from the `dev` network, and will provide
advance notice in the [XMTP Discord community](https://discord.gg/xmtp).
