import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/common/api.dart';
import 'package:xmtp/src/common/signature.dart';
import 'package:xmtp/src/content/codec.dart';
import 'package:xmtp/src/client.dart';

import 'test_server.dart';

void main() {
  // This creates 2 new users with connected clients and
  // sends messages back and forth between them.
  test(
    skip: skipUnlessTestServerEnabled,
    "messaging: listing, reading, writing, streaming",
    () async {
      var aliceWallet =
          await EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var bobWallet =
          await EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      var bob = await Client.createFromWallet(bobApi, bobWallet);
      await _delayToPropagate();
      var aliceAddress = aliceWallet.address.hex;
      var bobAddress = bobWallet.address.hex;

      var aliceChats = await alice.listConversations();
      var bobChats = await bob.listConversations();
      expect(aliceChats.length, 0);
      expect(bobChats.length, 0);

      var aliceConvo = await alice.newConversation(bobAddress);
      var bobConvo = await bob.newConversation(aliceAddress);

      var aliceMessages = await alice.listMessages(aliceConvo);
      var bobMessages = await alice.listMessages(bobConvo);

      expect(aliceMessages.length, 0);
      expect(bobMessages.length, 0);

      // Bob starts listening to the stream and recording the transcript.
      var transcript = [];
      var bobListening = bob
          .streamMessages(bobConvo)
          .listen((msg) => transcript.add('${msg.sender.hex}> ${msg.content}'));

      // Alice sends the first message.
      await alice.sendMessage(aliceConvo, "hello Bob, it's me Alice!");
      await _delayToPropagate();

      // It gets added to both of their conversation lists with that first msg.
      expect((await alice.listConversations()).length, 1);
      expect((await bob.listConversations()).length, 1);

      // And Bob see the message in the conversation.
      bobMessages = await bob.listMessages(bobConvo);
      expect(bobMessages.length, 1);
      expect(bobMessages[0].sender, aliceWallet.address);
      expect(bobMessages[0].content, "hello Bob, it's me Alice!");

      // Bob replies
      await bob.sendMessage(bobConvo, "oh, hello Alice!");
      await _delayToPropagate();

      aliceMessages = await alice.listMessages(aliceConvo);
      expect(aliceMessages.length, 2);
      expect(aliceMessages[0].sender, bobWallet.address);
      expect(aliceMessages[0].content, "oh, hello Alice!");
      expect(aliceMessages[1].sender, aliceWallet.address);
      expect(aliceMessages[1].content, "hello Bob, it's me Alice!");

      await bobListening.cancel();
      expect(transcript, [
        "$aliceAddress> hello Bob, it's me Alice!",
        "$bobAddress> oh, hello Alice!",
      ]);
    },
  );

  // This verifies client usage of published contacts.
  test(
    skip: skipUnlessTestServerEnabled,
    "contacts: can message only when their contact has been published",
    () async {
      var aliceWallet =
          await EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobWallet =
          await EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceAddress = aliceWallet.address.hex;
      var bobAddress = bobWallet.address.hex;
      // At this point, neither Alice nor Bob has signed up yet.

      // First Alice signs up.
      var aliceApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);

      // But Bob hasn't signed up yet, so she cannot message him.
      expect(await alice.canMessage(bobAddress), false);

      // Then Bob signs up.
      var bobApi = createTestServerApi();
      var bob = await Client.createFromWallet(bobApi, bobWallet);
      // Give contacts a moment to propagate.
      await Future.delayed(const Duration(milliseconds: 100));

      // So now they both should be able to message each other
      expect(await alice.canMessage(bobAddress), true);
      expect(await bob.canMessage(aliceAddress), true);

      // But they should not be able to message themselves (no self-messaging)
      expect(await alice.canMessage(aliceAddress), false);
      expect(await bob.canMessage(bobAddress), false);

      // And they should both remain unable to message a random address.
      var unknown = EthPrivateKey.createRandom(Random.secure());
      expect(await alice.canMessage(unknown.address.hex), false);
      expect(await bob.canMessage(unknown.address.hex), false);
    },
  );

  // This lists conversations and messages using various listing options.
  test(
    skip: skipUnlessTestServerEnabled,
    "listing and sorting parameters",
    () async {
      var aliceWallet =
          await EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var bobWallet =
          await EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      var bob = await Client.createFromWallet(bobApi, bobWallet);
      await _delayToPropagate();

      var convo = await alice.newConversation(bob.address.hex,
          conversationId: "example.com");
      await alice.sendMessage(convo, "first message to convo");
      await _delayToPropagate();
      await alice.sendMessage(convo, "second message to convo");
      await _delayToPropagate();
      await alice.sendMessage(convo, "third message to convo");
      await _delayToPropagate();

      var messages = await alice.listMessages(
        convo,
        limit: 2,
        sort: xmtp.SortDirection.SORT_DIRECTION_ASCENDING,
      );
      expect(messages.length, 2);
      expect(messages[0].content, "first message to convo");
      expect(messages[1].content, "second message to convo");

      messages = await alice.listMessages(
        convo,
        limit: 2,
        sort: xmtp.SortDirection.SORT_DIRECTION_DESCENDING,
      );
      expect(messages.length, 2);
      expect(messages[0].content, "third message to convo");
      expect(messages[1].content, "second message to convo");
    },
  );

  // This tests a user messaging herself.
  test(
    skip: skipUnlessTestServerEnabled,
    "messaging: self messages should be prevented",
    () async {
      var aliceWallet =
          await EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      await _delayToPropagate();

      await expectLater(() async => alice.newConversation(alice.address.hex),
          throwsArgumentError);
    },
  );

  // This conducts two distinct conversations between the same two users.
  test(
    skip: skipUnlessTestServerEnabled,
    "messaging: distinguish conversations using conversationId",
    () async {
      var aliceWallet =
          await EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var bobWallet =
          await EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      var bob = await Client.createFromWallet(bobApi, bobWallet);
      await _delayToPropagate();

      var work = await alice.newConversation(
        bob.address.hex,
        conversationId: "https://example.com/alice-bob-discussing-work",
      );
      await alice.sendMessage(work, "Bob, let's chat here about work.");
      await alice.sendMessage(work, "Our quarterly report is due next week.");

      var play = await alice.newConversation(
        bob.address.hex,
        conversationId: "https://example.com/alice-bob-discussing-play",
      );
      await alice.sendMessage(play, "Bob, let's chat here about play.");
      await alice.sendMessage(play, "I don't want to work.");
      await alice.sendMessage(play, "I just want to bang on my drum all day.");
      await _delayToPropagate();

      var bobChats = await bob.listConversations();
      expect(bobChats.length, 2);
      expect((await bob.listMessages(work)).map((m) => m.content).toList(), [
        "Our quarterly report is due next week.",
        "Bob, let's chat here about work.",
      ]);
      expect((await bob.listMessages(play)).map((m) => m.content).toList(), [
        "I just want to bang on my drum all day.",
        "I don't want to work.",
        "Bob, let's chat here about play.",
      ]);
    },
  );

  // This uses a custom codec to send integers between two people.
  test(
    skip: skipUnlessTestServerEnabled,
    "codecs: using a custom codec for integers",
    () async {
      var aliceWallet =
          await EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var bobWallet =
          await EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobApi = createTestServerApi();
      var alice = await Client.createFromWallet(
        aliceApi,
        aliceWallet,
        customCodecs: [IntegerCodec()],
      );
      var bob = await Client.createFromWallet(
        bobApi,
        bobWallet,
        customCodecs: [IntegerCodec()],
      );
      await _delayToPropagate();

      var convo = await alice.newConversation(bob.address.hex);

      await alice.sendMessage(convo, "Here's a number:");
      await alice.sendMessage(convo, 12345, contentType: contentTypeInteger);
      await _delayToPropagate();

      expect((await bob.listMessages(convo)).map((m) => m.content).toList(), [
        12345,
        "Here's a number:",
      ]);

      await bob.sendMessage(convo, "Cool. Here's another:");
      await bob.sendMessage(convo, 67890, contentType: contentTypeInteger);
      await _delayToPropagate();

      expect((await alice.listMessages(convo)).map((m) => m.content).toList(), [
        67890,
        "Cool. Here's another:",
        12345,
        "Here's a number:",
      ]);
    },
  );

  // This connects to the dev network to test the client.
  // NOTE: it requires a private key
  test(
    skip: "manual testing only",
    "dev: inspecting contacts, saved keys for particular wallet on dev network",
    () async {
      // Setup the API client.
      var api =
          Api.create(host: 'dev.xmtp.network', port: 5556, isSecure: true);
      var wallet =
          await EthPrivateKey.fromHex("... private key ...").asSigner();
      var client = await Client.createFromWallet(api, wallet);
      var conversations = await client.listConversations();
      for (var convo in conversations) {
        debugPrint('Conversation with ${convo.peer} ${convo.version}');
        debugPrint(' -> ${convo.topic}');
        var messages = await client.listMessages(convo);
        for (var msg in messages) {
          debugPrint(' ${msg.sentAt} ${msg.sender}> ${msg.content}');
        }
      }
    },
  );
}

/// A delay to allow messages to propagate before making assertions.
_delayToPropagate() => Future.delayed(const Duration(milliseconds: 200));

/// Simple [Codec] for sending [int] values around.
///
/// This encodes it as an 8 byte (64 bit) array.
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
        type: contentTypeInteger,
        content: Uint8List(8)..buffer.asByteData().setInt64(0, decoded),
      );
}
