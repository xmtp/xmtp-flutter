import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/common/api.dart';
import 'package:xmtp/src/common/signature.dart';
import 'package:xmtp/src/common/topic.dart';
import 'package:xmtp/src/content/codec.dart';
import 'package:xmtp/src/content/text_codec.dart';
import 'package:xmtp/src/client.dart';

import 'test_server.dart';

void main() {
  // This creates 2 new users with connected clients and
  // sends messages back and forth between them.
  test(
    skip: skipUnlessTestServerEnabled,
    "messaging: listing, reading, writing, streaming",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      var bob = await Client.createFromWallet(bobApi, bobWallet);
      await delayToPropagate();
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
      await delayToPropagate();

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
      await delayToPropagate();

      // Bob sends an already-encoded message
      await bob.sendMessageEncoded(
          bobConvo, await TextCodec().encode("I have a note for you"));
      await delayToPropagate();

      aliceMessages = await alice.listMessages(aliceConvo);
      expect(aliceMessages.length, 3);
      expect(aliceMessages[0].sender, bobWallet.address);
      expect(aliceMessages[0].content, "I have a note for you");
      expect(aliceMessages[1].sender, bobWallet.address);
      expect(aliceMessages[1].content, "oh, hello Alice!");
      expect(aliceMessages[2].sender, aliceWallet.address);
      expect(aliceMessages[2].content, "hello Bob, it's me Alice!");

      await bobListening.cancel();
      expect(transcript, [
        "$aliceAddress> hello Bob, it's me Alice!",
        "$bobAddress> oh, hello Alice!",
        "$bobAddress> I have a note for you",
      ]);
    },
  );

  test(
    skip: skipUnlessTestServerEnabled,
    "codecs: discard messages from unsupported codecs without fallback text",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      var bob = await Client.createFromWallet(bobApi, bobWallet);
      await delayToPropagate();

      var chat = await alice.newConversation(
        bob.address.hex,
        conversationId: "https://example.com/alice-bob-chat",
      );
      await delayToPropagate();

      var encoded1234 = await IntegerCodec().encode(1234);
      expect(encoded1234.hasFallback(), false);

      await alice.sendMessage(chat, "Hey! I'm about to send you an Integer");
      await delayToPropagate();
      await alice.sendMessageEncoded(chat, encoded1234);
      await delayToPropagate();
      await alice.sendMessage(chat, "You might see it?");
      await delayToPropagate();

      // Bob doesn't know about IntegerCodec (and it has no fallback)
      // So he can't see the integer message.
      expect((await bob.listMessages(chat)).map((m) => m.content).toList(), [
        "You might see it?",
        "Hey! I'm about to send you an Integer",
      ]);

      // But if we teach Bob about IntegerCodec
      bob = await Client.createFromWallet(bobApi, bobWallet,
          customCodecs: [IntegerCodec()]);
      // Then he should see it
      expect((await bob.listMessages(chat)).map((m) => m.content).toList(), [
        "You might see it?",
        1234,
        "Hey! I'm about to send you an Integer",
      ]);
    },
  );

  test(
    skip: skipUnlessTestServerEnabled,
    "push: handle out-of-band decryption of conversations + messages",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      var bob = await Client.createFromWallet(bobApi, bobWallet);
      await delayToPropagate();

      // The Push Server can watch topics but has no keys to decrypt anything
      var pushApi = createTestServerApi();

      // Alice starts a new conversation with Bob
      var chat = await alice.newConversation(
        bob.address.hex,
        conversationId: "https://example.com/alice-bob-chat",
      );
      await delayToPropagate();

      // The push notification server is watching for Bob's new chats
      var pushBobConvos = await pushApi.client
          .query(xmtp.QueryRequest(contentTopics: [
            Topic.userIntro(bob.address.hex),
            Topic.userInvite(bob.address.hex),
      ]));
      expect(pushBobConvos.envelopes.length, 1);

      // When we push that new conversation to Bob he can decrypt it.
      var bobChat = await bob.decryptConversation(pushBobConvos.envelopes[0]);
      expect(bobChat!.topic, chat.topic);

      // Then when alice sends a message
      await alice.sendMessage(chat, "Hey!");
      await delayToPropagate();

      // The push server is watching for Bob's new messages
      var pushBobMessages = await pushApi.client
          .query(xmtp.QueryRequest(contentTopics: [bobChat.topic]));
      expect(pushBobMessages.envelopes.length, 1);

      // And if we push that encrypted message to Bob he can decrypt it.
      var bobMsg = await bob.decryptMessage(bobChat,
          xmtp.Message.fromBuffer(pushBobMessages.envelopes[0].message));
      expect(bobMsg!.content, "Hey!");
      expect(bobMsg.sender, alice.address);
    },
  );

  // This verifies client usage of published contacts.
  test(
    skip: skipUnlessTestServerEnabled,
    "contacts: can message only when their contact has been published",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
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
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      var bob = await Client.createFromWallet(bobApi, bobWallet);
      await delayToPropagate();

      var convo = await alice.newConversation(bob.address.hex,
          conversationId: "example.com");
      await alice.sendMessage(convo, "first message to convo");
      await delayToPropagate();
      await alice.sendMessage(convo, "second message to convo");
      await delayToPropagate();
      await alice.sendMessage(convo, "third message to convo");
      await delayToPropagate();

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
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      await delayToPropagate();

      await expectLater(() async => alice.newConversation(alice.address.hex),
          throwsArgumentError);
    },
  );

  // This conducts two distinct conversations between the same two users.
  test(
    skip: skipUnlessTestServerEnabled,
    "messaging: distinguish conversations using conversationId",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      var bob = await Client.createFromWallet(bobApi, bobWallet);
      await delayToPropagate();

      var work = await alice.newConversation(
        bob.address.hex,
        conversationId: "https://example.com/alice-bob-discussing-work",
      );
      var play = await alice.newConversation(
        bob.address.hex,
        conversationId: "https://example.com/alice-bob-discussing-play",
      );
      await delayToPropagate();

      // Bob starts streaming both conversations
      expect((await bob.listConversations()).length, 2);
      var transcript = [];
      var bobListening = bob.streamBatchMessages([work, play]).listen((msg) =>
          transcript.add('${msg.topic} ${msg.sender.hex}> ${msg.content}'));

      await alice.sendMessage(work, "Bob, let's chat here about work.");
      await delayToPropagate();
      await alice.sendMessage(work, "Our quarterly report is due next week.");
      await delayToPropagate();
      await alice.sendMessage(play, "Bob, let's chat here about play.");
      await delayToPropagate();
      await alice.sendMessage(play, "I don't want to work.");
      await delayToPropagate();
      await alice.sendMessage(play, "I just want to bang on my drum all day.");
      await delayToPropagate();

      expect((await bob.listMessages(work)).map((m) => m.content).toList(), [
        "Our quarterly report is due next week.",
        "Bob, let's chat here about work.",
      ]);
      expect((await bob.listMessages(play)).map((m) => m.content).toList(), [
        "I just want to bang on my drum all day.",
        "I don't want to work.",
        "Bob, let's chat here about play.",
      ]);
      expect((await bob.listBatchMessages([work, play])).length, 5);
      await bobListening.cancel();
      expect(transcript, [
        "${work.topic} ${alice.address.hex}> Bob, let's chat here about work.",
        "${work.topic} ${alice.address.hex}> Our quarterly report is due next week.",
        "${play.topic} ${alice.address.hex}> Bob, let's chat here about play.",
        "${play.topic} ${alice.address.hex}> I don't want to work.",
        "${play.topic} ${alice.address.hex}> I just want to bang on my drum all day.",
      ]);
    },
  );

  test(
    skip: skipUnlessTestServerEnabled,
    timeout: const Timeout.factor(5), // TODO: consider turning off in CI
    "messaging: batch requests should be partitioned to fit max batch size",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      var aliceAddress = aliceWallet.address.hexEip55;

      // Pretend a bunch of people have messaged alice.
      const conversationCount = maxQueryRequestsPerBatch + 5;
      await Future.wait(List.generate(conversationCount, (i) async {
        var wallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
        var api = createTestServerApi(debugLogRequests: false);
        var user = await Client.createFromWallet(api, wallet);
        var convo = await user.newConversation(
          aliceAddress,
          conversationId: "example.com/batch-partition-test-convo-$i",
        );
        await user.sendMessage(convo, "I am number $i of $conversationCount");
      }));
      await delayToPropagate();

      var convos = await alice.listConversations();
      expect(convos.length, conversationCount);

      var messages = await alice.listBatchMessages(convos);
      expect(messages.length, conversationCount);
    },
  );

  // This uses a custom codec to send integers between two people.
  test(
    skip: skipUnlessTestServerEnabled,
    "codecs: using a custom codec for integers",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
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
      await delayToPropagate();

      var convo = await alice.newConversation(bob.address.hex);

      await alice.sendMessage(convo, "Here's a number:");
      await alice.sendMessage(convo, 12345, contentType: contentTypeInteger);
      await delayToPropagate();

      expect((await bob.listMessages(convo)).map((m) => m.content).toList(), [
        12345,
        "Here's a number:",
      ]);

      await bob.sendMessage(convo, "Cool. Here's another:");
      await bob.sendMessage(convo, 67890, contentType: contentTypeInteger);
      await delayToPropagate();

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
      var wallet = EthPrivateKey.fromHex("... private key ...").asSigner();
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

  // This creates a user and sends them lots of messages from other users.
  // This aims to be useful for prepping an account to test performance.
  test(
    skip: "manual testing",
    "messaging: send lots of messages to me",
    () async {
      // Starts this many conversations:
      const conversationCount = 30;
      // ... with this many messages in each:
      const messagesPerCount = 5;

      var recipientKey = EthPrivateKey.createRandom(Random.secure());
      var recipientClient = await Client.createFromWallet(
          createTestServerApi(), recipientKey.asSigner());
      var recipient = recipientClient.address.hex;
      debugPrint('sending messages to $recipient');
      debugPrint(' private key: ${bytesToHex(recipientKey.privateKey)}');
      for (var i = 0; i < conversationCount; ++i) {
        var senderKey = EthPrivateKey.createRandom(Random.secure());
        var senderWallet = senderKey.asSigner();
        var senderApi = createTestServerApi(debugLogRequests: false);
        var sender = await Client.createFromWallet(senderApi, senderWallet);
        debugPrint('${i + 1}/$conversationCount: '
            'sending $messagesPerCount from ${sender.address.hex}');
        var convo = await sender.newConversation(recipient);
        await Future.wait(Iterable.generate(
          messagesPerCount,
          (_) => sender.sendMessage(convo, """
Lorem ipsum dolor sit amet, consectetur adipiscing elit, 
sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. 
Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris 
nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in 
reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla 
pariatur. Excepteur sint occaecat cupidatat non proident, sunt in 
culpa qui officia deserunt mollit anim id est laborum.
"""),
        ));
      }
    },
  );
}

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
