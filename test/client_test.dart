import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp/src/contact.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/common/api.dart';
import 'package:xmtp/src/common/signature.dart';
import 'package:xmtp/src/common/topic.dart';
import 'package:xmtp/src/content/attachment_codec.dart';
import 'package:xmtp/src/content/codec.dart';
import 'package:xmtp/src/content/decoded.dart';
import 'package:xmtp/src/content/reaction_codec.dart';
import 'package:xmtp/src/content/remote_attachment_codec.dart';
import 'package:xmtp/src/content/reply_codec.dart';
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
      expect(alice.checkContactConsent(bobAddress), ContactConsent.unknown);
      expect(bob.checkContactConsent(aliceAddress), ContactConsent.unknown);

      var aliceConvo = await alice.newConversation(bobAddress);
      var aliceMessages = await alice.listMessages(aliceConvo);

      // Alice started the conversation so she implicitly allowed the contact.
      expect(aliceMessages.length, 0);
      expect(alice.checkContactConsent(bobAddress), ContactConsent.allow);

      // Bob can see the conversation but hasn't received any messages yet.
      // And he has neither denied nor allowed the contact.
      var bobConvos = (await bob.listConversations());
      var bobConvo = bobConvos[0];
      var bobMessages = await bob.listMessages(bobConvo);
      expect(bobConvos.length, 1);
      expect(bobConvo.peer, alice.address);
      expect(bobMessages.length, 0);
      expect(bob.checkContactConsent(aliceAddress), ContactConsent.unknown);

      // Bob starts listening to the stream and recording the transcript.
      var transcript = [];
      var bobListening = bob
          .streamMessages(bobConvo)
          .listen((msg) => transcript.add('${msg.sender.hex}> ${msg.content}'));
      await delayToPropagate();

      // Alice sends the first message.
      await alice.sendMessage(aliceConvo, "hello Bob, it's me Alice!");
      await delayToPropagate();

      // It gets added to both of their conversation lists with that first msg.
      // But Bob still hasn't allowed the contact.
      expect((await alice.listConversations()).length, 1);
      expect((await bob.listConversations()).length, 1);
      expect(alice.checkContactConsent(bobAddress), ContactConsent.allow);
      expect(bob.checkContactConsent(aliceAddress), ContactConsent.unknown);

      // And Bob see the message in the conversation.
      bobMessages = await bob.listMessages(bobConvo);
      expect(bobMessages.length, 1);
      expect(bobMessages[0].sender, aliceWallet.address);
      expect(bobMessages[0].content, "hello Bob, it's me Alice!");

      // Bob replies
      // Which now implicitly gives Bob's consent to allow the contact.
      await bob.sendMessage(bobConvo, "oh, hello Alice!");
      await delayToPropagate();
      expect(alice.checkContactConsent(bobAddress), ContactConsent.allow);
      expect(bob.checkContactConsent(aliceAddress), ContactConsent.allow);

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
      var pushBobConvos =
          await pushApi.client.query(xmtp.QueryRequest(contentTopics: [
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
        sort: xmtp.SortDirection.SORT_DIRECTION_ASCENDING,
      );
      expect(messages.length, 3);
      expect(messages[0].content, "first message to convo");
      expect(messages[1].content, "second message to convo");
      expect(messages[2].content, "third message to convo");

      messages = await alice.listMessages(
        convo,
        sort: xmtp.SortDirection.SORT_DIRECTION_DESCENDING,
      );
      expect(messages.length, 3);
      expect(messages[0].content, "third message to convo");
      expect(messages[1].content, "second message to convo");
      expect(messages[2].content, "first message to convo");
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
    "messaging: contact consent should be persisted",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobApi = createTestServerApi();
      var carlWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var carlApi = createTestServerApi();
      var danaWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var danaApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      var bob = await Client.createFromWallet(bobApi, bobWallet);
      var carl = await Client.createFromWallet(carlApi, carlWallet);
      var dana = await Client.createFromWallet(danaApi, danaWallet);
      await delayToPropagate();

      await alice.denyContact(bob.address.hex);
      await alice.allowContact(carl.address.hex);
      await delayToPropagate();
      expect(alice.checkContactConsent(bob.address.hex), ContactConsent.deny);
      expect(alice.checkContactConsent(carl.address.hex), ContactConsent.allow);
      expect(
          alice.checkContactConsent(dana.address.hex), ContactConsent.unknown);

      // The new session should pickup her old consents.
      alice = await Client.createFromWallet(aliceApi, aliceWallet);
      await alice.refreshContactConsentPreferences();
      expect(alice.checkContactConsent(bob.address.hex), ContactConsent.deny);
      expect(alice.checkContactConsent(carl.address.hex), ContactConsent.allow);
      expect(
          alice.checkContactConsent(dana.address.hex), ContactConsent.unknown);

      // To make sure the consent loading handles many pages of consent actions,
      // we'll simulate Alice changing her mind many times about Bob and Carl.
      for (var i = 0; i < 100; ++i) {
        if (i % 2 == 0) {
          await alice.denyContact(bob.address.hex);
          await alice.allowContact(carl.address.hex);
        } else {
          await alice.denyContact(carl.address.hex);
          await alice.allowContact(bob.address.hex);
        }
      }
      await delayToPropagate();

      // But in the end Alice allows them both.
      await alice.allowContact(bob.address.hex);
      await alice.allowContact(carl.address.hex);
      await delayToPropagate();

      // And when we start a new session, her consent should be remembered.
      alice = await Client.createFromWallet(aliceApi, aliceWallet);
      await alice.refreshContactConsentPreferences();
      expect(alice.checkContactConsent(bob.address.hex), ContactConsent.allow);
      expect(alice.checkContactConsent(carl.address.hex), ContactConsent.allow);
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

  test(
    skip: skipUnlessTestServerEnabled,
    "codecs: sending and streaming ephemeral messages",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var bobApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      var bob = await Client.createFromWallet(bobApi, bobWallet);
      await delayToPropagate();

      // Alice starts a conversation w/ Bob
      var convo = await alice.newConversation(bob.address.hex);
      await delayToPropagate();
      await alice.sendMessage(convo, "Hello");
      await delayToPropagate();

      // Bob should see that first message.
      expect((await bob.listMessages(convo)).map((m) => m.content).toList(), [
        "Hello",
      ]);

      // Bob starts listening to the stream of ephemera.
      var ephemera = [];
      var bobListening = bob
          .streamEphemeralMessages(convo)
          .listen((msg) => ephemera.add('${msg.sender.hex}> ${msg.content}'));
      await delayToPropagate();

      // Alice sends an ephemeral "typing..." indicator (text for now)
      await alice.sendMessage(convo, "typing...", isEphemeral: true);
      await delayToPropagate();

      // Bob should see the ephemeral indicator
      expect(ephemera, [
        "${alice.address.hex}> typing...",
      ]);

      // Then Alice sends the actual message she typed.
      await alice.sendMessage(convo, "I'm hungry, let's get lunch");
      await delayToPropagate();

      // And Bob should now see those two messages (w/o the ephemera)
      expect((await bob.listMessages(convo)).map((m) => m.content).toList(), [
        "I'm hungry, let's get lunch",
        "Hello",
      ]);
      await bobListening.cancel();
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

  test(
    skip: skipUnlessTestServerEnabled,
    "remote attachments: uploading and downloading attachments should work",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      var bob = await Client.createFromWallet(bobApi, bobWallet);
      var files = TestRemoteFiles();

      // If Alice sends a message and then a remote attachment...
      var convo = await alice.newConversation(bob.address.hex);
      await alice.sendMessage(convo, "Here's an attachment for you:");
      var attachment = Attachment("foo.txt", "text/plain", utf8.encode("bar"));
      var remote = await alice.upload(attachment, files.upload);
      await alice.sendMessage(convo, remote,
          contentType: contentTypeRemoteAttachment);
      await delayToPropagate();

      // ... then Bob should see the messages.
      var messages = await bob.listMessages(convo);
      expect(messages.length, 2);
      expect((messages[0].content as RemoteAttachment).filename, "foo.txt");
      expect((messages[1].content as String), "Here's an attachment for you:");

      // And he should be able to download the remote attachment.
      var downloaded = await bob.download(
        messages[0].content as RemoteAttachment,
        downloader: files.download,
      );
      expect((downloaded.content as Attachment).filename, "foo.txt");
      expect((downloaded.content as Attachment).mimeType, "text/plain");
      expect(utf8.decode((downloaded.content as Attachment).data), "bar");
    },
  );

  test(
    skip: skipUnlessTestServerEnabled,
    "codecs: sending codec encoded message to user",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var alice = await Client.createFromWallet(
        aliceApi,
        aliceWallet,
        customCodecs: [IntegerCodec()],
      );
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobApi = createTestServerApi();
      var bob = await Client.createFromWallet(
        bobApi,
        bobWallet,
        customCodecs: [IntegerCodec()],
      );
      var convo = await alice.newConversation(bob.address.hex);

      debugPrint('sending as ${alice.address.hexEip55}');

      await alice.sendMessage(convo, "Hello!");
      await alice.sendMessage(convo, "Here's a number:");
      await delayToPropagate();
      await alice.sendMessage(convo, 12345, contentType: contentTypeInteger);
      await delayToPropagate();
      await alice.sendMessage(convo, "Do you see it up ^ there?");
      await delayToPropagate();
      await alice.sendMessage(convo, "Here's an attachment:");
      await delayToPropagate();
      await alice.sendMessage(convo,
          Attachment("foo.txt", "text/plain", utf8.encode("some writing")),
          contentType: contentTypeAttachment);
      await delayToPropagate();
      await alice.sendMessage(convo, "Do you see it up ^ there?");
      await delayToPropagate();

      var msg = await alice.sendMessage(convo, "Here's a reaction:");
      await delayToPropagate();
      await alice.sendMessage(convo,
          Reaction(msg.id, ReactionAction.added, ReactionSchema.unicode, "👍"),
          contentType: contentTypeReaction);
      await delayToPropagate();
      await alice.sendMessage(convo, "Do you see it up ^ there?");
      await delayToPropagate();

      msg = await alice.sendMessage(convo, "Here's a reply:");
      await delayToPropagate();
      await alice.sendMessage(
          convo,
          Reply(msg.id,
              DecodedContent(contentTypeText, "I'm replying to myself!")),
          contentType: contentTypeReply);
      await delayToPropagate();
      await alice.sendMessage(convo, "Do you see it up ^ there?");
      await delayToPropagate();

      msg =
          await alice.sendMessage(convo, "Here's a reply with an attachment:");
      await delayToPropagate();
      await alice.sendMessage(
        convo,
        Reply(
            msg.id,
            DecodedContent(
                contentTypeAttachment,
                Attachment("reply.txt", "text/plain",
                    utf8.encode("a lengthy reply" * 100)))),
        contentType: contentTypeReply,
      );
      await delayToPropagate();
      await alice.sendMessage(convo, "Do you see it up ^ there?");
      await delayToPropagate();

      var messages = await bob.listMessages(convo,
          sort: xmtp.SortDirection.SORT_DIRECTION_ASCENDING);
      expect(messages.length, 16);
      expect(messages[0].content, "Hello!");
      expect(messages[1].content, "Here's a number:");
      expect(messages[2].content, 12345);
      expect(messages[3].content, "Do you see it up ^ there?");
      expect(messages[4].content, "Here's an attachment:");
      expect(messages[5].content, isA<Attachment>());
      expect((messages[5].content as Attachment).mimeType, "text/plain");
      expect((messages[5].content as Attachment).filename, "foo.txt");
      expect((messages[5].content as Attachment).data,
          utf8.encode("some writing"));
      expect(messages[6].content, "Do you see it up ^ there?");
      expect(messages[7].content, "Here's a reaction:");
      expect(messages[8].content, isA<Reaction>());
      expect((messages[8].content as Reaction).reference, messages[7].id);
      expect((messages[8].content as Reaction).action, ReactionAction.added);
      expect((messages[8].content as Reaction).schema, ReactionSchema.unicode);
      expect((messages[8].content as Reaction).content, "👍");
      expect(messages[9].content, "Do you see it up ^ there?");
      expect(messages[10].content, "Here's a reply:");
      expect(messages[11].content, isA<Reply>());
      expect((messages[11].content as Reply).reference, messages[10].id);
      expect(
        (messages[11].content as Reply).content.contentType,
        contentTypeText,
      );
      expect(
        (messages[11].content as Reply).content.content,
        "I'm replying to myself!",
      );
      expect(
          alice.fallback(
              DecodedContent(messages[11].contentType, messages[11].content)),
          "Replied with “I'm replying to myself!” to an earlier message");
      expect(messages[12].content, "Do you see it up ^ there?");
      expect(messages[13].content, "Here's a reply with an attachment:");
      expect(messages[14].content, isA<Reply>());
      expect(
          (messages[14].content as Reply).content.content, isA<Attachment>());
      expect(
          ((messages[14].content as Reply).content.content as Attachment)
              .mimeType,
          "text/plain");
      expect(
          ((messages[14].content as Reply).content.content as Attachment)
              .filename,
          "reply.txt");
      expect(
        ((messages[14].content as Reply).content.content as Attachment).data,
        utf8.encode("a lengthy reply" * 100),
      );
      expect(messages[15].content, "Do you see it up ^ there?");
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

  test(
    skip: "manual testing only",
    "dev: inspecting consent state for known wallet on dev network",
    () async {
      // Inspect a known wallet w/ many conversations and 100/100 consents
      var api = Api.create(host: 'dev.xmtp.network');
      var wallet = EthPrivateKey.fromHex(
              "0x0836200ffafa17a3cb8b54f22d6afa60b13da48726543241adc5c250dbb0e0cd")
          .asSigner();
      var client = await Client.createFromWallet(api, wallet);
      await client.refreshContactConsentPreferences();
      var consents = client.exportContactConsents();
      expect(consents.denied.walletAddresses.length, 100);
      expect(consents.allowed.walletAddresses.length, 100);
    },
  );

  test(
    skip: "manual testing",
    "conversations: listing conversations with pagination",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      await _startRandomConversationsWith(
        alice.address.hex,
        // > 100 (the server page size)
        conversationCount: 105,
        messagesPerConvo: 1,
      );
      var conversations = await alice.listConversations();
      expect(conversations.length, 105);
    },
  );

  test(
    skip: "manual testing",
    "messages: listing batch messages first message",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      await _startRandomConversationsWith(
        alice.address.hex,
        // > 50 (the batch size)
        conversationCount: 60,
        messagesPerConvo: 1,
      );
      await _startRandomConversationsWith(
        alice.address.hex,
        // start a couple with lots of entries in them
        conversationCount: 2,
        messagesPerConvo: 110,
      );
      var conversations = await alice.listConversations();
      expect(conversations.length, 60 + 2);
      var messages = await alice.listBatchMessages(conversations, limit: 1);
      expect(messages.length, 60 + 2);
    },
  );

  test(
    skip: "manual testing",
    "messages: listing batch messages with pagination",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      await _startRandomConversationsWith(
        alice.address.hex,
        // > 50 (the batch size)
        conversationCount: 60,
        messagesPerConvo: 1,
      );
      await _startRandomConversationsWith(
        alice.address.hex,
        // start a couple with lots of entries in them
        conversationCount: 2,
        messagesPerConvo: 110,
      );
      var conversations = await alice.listConversations();
      expect(conversations.length, 60 + 2);
      var messages = await alice.listBatchMessages(conversations);
      expect(messages.length, 60 + 2 * 110);
    },
  );

  test(
    skip: "manual testing",
    "messages: listing batch messages with multiple paginations",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var aliceApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      await _startRandomConversationsWith(
        alice.address.hex,
        conversationCount: 2,
        messagesPerConvo: 110,
      );
      var conversations = await alice.listConversations();
      expect(conversations.length, 2);
      var messages = await alice.listBatchMessages(conversations);
      expect(messages.length, 2 * 110);
    },
  );

  // This creates a user and sends them lots of messages from other users.
  // This aims to be useful for prepping an account to test performance.
  test(
    skip: "manual testing",
    "messaging: send lots of messages to me",
    () async {
      var recipientKey = EthPrivateKey.createRandom(Random.secure());
      var recipientClient = await Client.createFromWallet(
          createTestServerApi(), recipientKey.asSigner());
      var recipient = recipientClient.address.hex;
      debugPrint('sending messages to $recipient');
      debugPrint(' private key: ${bytesToHex(recipientKey.privateKey)}');
      await _startRandomConversationsWith(
        recipient,
        conversationCount: 200,
        messagesPerConvo: 5,
      );
    },
  );
}

/// Helper to store and retrieve remote files.
class TestRemoteFiles {
  var files = {};

  Future<String> upload(List<int> data) async {
    var url = "https://example.com/${Random.secure().nextInt(1000000)}";
    files[url] = data;
    return url;
  }

  Future<List<int>> download(String url) async => files[url];
}

/// Helper to seed random conversations in a test account.
Future _startRandomConversationsWith(
  String recipientAddress, {
  conversationCount = 5,
  messagesPerConvo = 1,
}) async {
  for (var i = 0; i < conversationCount; ++i) {
    var senderKey = EthPrivateKey.createRandom(Random.secure());
    var senderWallet = senderKey.asSigner();
    var senderApi = createTestServerApi(debugLogRequests: false);
    var sender = await Client.createFromWallet(senderApi, senderWallet);
    debugPrint('${i + 1}/$conversationCount: '
        'sending $messagesPerConvo from ${sender.address.hex}');
    var convo = await sender.newConversation(recipientAddress);
    await Future.wait(Iterable.generate(
      messagesPerConvo,
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
