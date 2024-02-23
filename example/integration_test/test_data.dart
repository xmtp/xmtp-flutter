import 'dart:convert';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp/xmtp.dart' as xmtp;

/// This contains some realistic-ish test data to make it easier to write tests.
/// Note: these are somewhat internally referentially consistent.

/// Addresses
final addressA =
    EthereumAddress.fromHex("0x1111111111222222222233333333334444444444");
final addressB =
    EthereumAddress.fromHex("0x2222222222333333333344444444445555555555");
final addressC =
    EthereumAddress.fromHex("0x3333333333444444444455555555556666666666");

/// Conversations
final convoAandB = xmtp.DirectConversation.v1(
  DateTime.now().subtract(const Duration(minutes: 2)),
  me: addressA,
  peer: addressB,
);
final convoAandC = xmtp.DirectConversation.v1(
  DateTime.now().subtract(const Duration(minutes: 1)),
  me: addressA,
  peer: addressC,
);

/// Messages
final messageAtoB = xmtp.DecodedMessage(
  xmtp.Message_Version.v1,
  DateTime.now().subtract(const Duration(minutes: 2)),
  addressA,
  xmtp.EncodedContent(
      content: utf8.encode("hello"), type: xmtp.contentTypeText),
  xmtp.contentTypeText,
  "hello",
  id: "abc123",
  topic: convoAandB.topic,
);

final messageBtoA = xmtp.DecodedMessage(
  xmtp.Message_Version.v1,
  DateTime.now().subtract(const Duration(minutes: 1)),
  addressB,
  xmtp.EncodedContent(
    content: utf8.encode("oh, hi there"),
    type: xmtp.contentTypeText,
  ),
  xmtp.contentTypeText,
  "oh, hi there",
  id: "def456",
  topic: convoAandB.topic,
);
