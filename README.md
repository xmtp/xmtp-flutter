# xmtp-flutter

![Test](https://github.com/xmtp/xmtp-flutter/actions/workflows/test.yml/badge.svg) ![Status](https://camo.githubusercontent.com/5bb5892781bbf711c7fe5eba3328e9e15a767de87c587d3fb65f2fd7e1f4ae72/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f50726f6a6563745f5374617475732d446576656c6f7065725f507265766965772d726564)

`xmtp-flutter` provides a Dart implementation of an XMTP message API client for use with Flutter apps.

Use `xmtp-flutter` to build with XMTP to send messages between blockchain accounts, including DMs, notifications, announcements, and more.

This SDK is in **Developer Preview** status. We do **not** recommend using Developer Preview software in production apps.

Software in this status:

- Is not formally supported
- Will change without warning
- May not be backward compatible
- Has not undergone a formal security audit

Follow along in the [tracking issue](https://github.com/xmtp/xmtp-flutter/issues/4) for updates.

To learn more about XMTP and get answers to frequently asked questions, see [FAQ about XMTP](https://xmtp.org/docs/dev-concepts/faq).

![x-red-sm](https://user-images.githubusercontent.com/510695/163488403-1fb37e86-c673-4b48-954e-8460ae4d4b05.png)

## Example app

For a basic demonstration of the core concepts and capabilities of the `xmtp-flutter` client SDK, see the [Example app project](https://github.com/xmtp/xmtp-flutter/tree/main/example).

## Reference docs

See [xmtp library](https://pub.dev/documentation/xmtp/latest/xmtp/Client-class.html) for the Flutter client SDK reference documentation.

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

***dan provide this. See xmtp-ios for example content: https://github.com/xmtp/xmtp-ios#create-a-client***

```dart
code sample
```

### Configure the client

***dan provide this. See xmtp-ios for example content: https://github.com/xmtp/xmtp-ios#configure-the-client***

```dart
code sample
```

## Handle conversations

***dan provide this. See xmtp-ios for example content: https://github.com/xmtp/xmtp-ios#handle-conversations***

```dart
code sample
```

### List existing conversations

***dan provide this. See xmtp-ios for example content: https://github.com/xmtp/xmtp-ios#list-existing-conversations***

```dart
code sample
```

### Listen for new conversations

***dan provide this. See xmtp-ios for example content: https://github.com/xmtp/xmtp-ios#listen-for-new-conversations***

```dart
code sample
```

### Start a new conversation

***dan provide this. See xmtp-ios for example content: https://github.com/xmtp/xmtp-ios#start-a-new-conversation***

```dart
code sample
```

### Send messages

***dan provide this. See xmtp-ios for example content: https://github.com/xmtp/xmtp-ios#send-messages***

```dart
code sample
```

### List messages in a conversation

***dan provide this. See xmtp-ios for example content: https://github.com/xmtp/xmtp-ios#list-messages-in-a-conversation***

```dart
code sample
```

### List messages in a conversation with pagination

***dan provide this. See xmtp-ios for example content: https://github.com/xmtp/xmtp-ios#list-messages-in-a-conversation-with-pagination***

```dart
code sample
```

### Listen for new messages in a conversation

***dan provide this. See xmtp-ios for example content: https://github.com/xmtp/xmtp-ios#listen-for-new-messages-in-a-conversation***

```dart
code sample
```

### Handling multiple conversations with the same blockchain address

***dan provide this. See xmtp-ios for example content: https://github.com/xmtp/xmtp-ios#handling-multiple-conversations-with-the-same-blockchain-address***

```dart
code sample
```

## Compression

***dan provide this. See xmtp-ios for example content: https://github.com/xmtp/xmtp-ios#compression***

## 🏗 **Breaking revisions**

Because `xmtp-flutter` is in active development, you should expect breaking revisions that might require you to adopt the latest SDK release to enable your app to continue working as expected.

XMTP communicates about breaking revisions in the [XMTP Discord community](https://discord.gg/xmtp), providing as much advance notice as possible. Additionally, breaking revisions in an `xmtp-flutter` release are described on the [Releases page](https://github.com/xmtp/xmtp-flutter/releases).

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
For example, for a given blockchain account, its XMTP identity on `dev` network is completely distinct from its XMTP identity on the `production` network, as are the messages associated with these identities. In addition, XMTP identities and messages created on the `dev` network can't be accessed from or moved to the `production` network, and vice versa.

***Dan, if you remove the Create a client and/or Configure the client sections, we need to find a way to resolve the anchor links in the following paragraph:***

**Important:** When you [create a client](#create-a-client), it connects to the XMTP `dev` environment by default. To learn how to use the `env` parameter to set your client's network environment, see [Configure the client](#configure-the-client).

The `env` parameter accepts one of three valid values: `dev`, `production`, or `local`. Here are some best practices for when to use each environment:

- `dev`: Use to have a client communicate with the `dev` network. As a best practice, set `env` to `dev` while developing and testing your app. Follow this best practice to isolate test messages to `dev` inboxes.

- `production`: Use to have a client communicate with the `production` network. As a best practice, set `env` to `production` when your app is serving real users. Follow this best practice to isolate messages between real-world users to `production` inboxes.

- `local`: Use to have a client communicate with an XMTP node you are running locally. For example, an XMTP node developer can set `env` to `local` to generate client traffic to test a node running locally.

The `production` network is configured to store messages indefinitely. XMTP may occasionally delete messages and keys from the `dev` network, and will provide advance notice in the [XMTP Discord community](https://discord.gg/xmtp).
