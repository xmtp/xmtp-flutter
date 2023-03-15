import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/common/api.dart';
import 'package:xmtp/src/common/signature.dart';
import 'package:xmtp/src/common/time64.dart';
import 'package:xmtp/src/common/topic.dart';
import 'package:xmtp/src/auth.dart';
import 'package:xmtp/src/contact.dart';
import 'package:xmtp/src/content/codec_registry.dart';
import 'package:xmtp/src/content/text_codec.dart';
import 'package:xmtp/src/conversation/conversation_v2.dart';

import '../test_server.dart';

void main() {
  // This creates 2 users connected to the API and sends DMs
  // back and forth using message API V2.
  test(
    skip: skipUnlessTestServerEnabled,
    "v2 messaging: invites, reading, writing, streaming",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var alice = await _createLocalManager(aliceWallet);
      var bob = await _createLocalManager(bobWallet);
      var aliceAddress = aliceWallet.address.hex;
      var bobAddress = bobWallet.address.hex;

      var aliceChats = await alice.listConversations();
      var bobChats = await bob.listConversations();
      expect(aliceChats.length, 0);
      expect(bobChats.length, 0);

      // Alice initiates the conversation (sending off the invites)
      var aliceConvo = await alice.newConversation(
        bobAddress,
        xmtp.InvitationV1_Context(
          conversationId: "example.com/alice-and-bob",
          metadata: {"title": "Alice & Bob"},
        ),
      );
      await delayToPropagate();

      // They both get the invite.
      expect((await alice.listConversations()).length, 1);
      expect((await bob.listConversations()).length, 1);
      var bobConvo = (await bob.listConversations())[0];

      // They see each other as the recipients.
      expect(aliceConvo.peer, bobWallet.address);
      expect(bobConvo.peer, aliceWallet.address);

      // Bob starts listening to the stream and recording the transcript.
      var transcript = [];
      var bobListening = bob.streamMessages([bobConvo]).listen(
          (msg) => transcript.add('${msg.sender.hex}> ${msg.content}'));

      // Alice sends the first message.
      await alice.sendMessage(aliceConvo, "hello Bob, it's me Alice!");
      await delayToPropagate();

      // And Bob see the message in the conversation.
      var bobMessages = await bob.listMessages([bobConvo]);
      expect(bobMessages.length, 1);
      expect(bobMessages[0].sender, aliceWallet.address);
      expect(bobMessages[0].content, "hello Bob, it's me Alice!");

      // Bob replies
      await bob.sendMessage(bobConvo, "oh, hello Alice!");
      await delayToPropagate();

      var aliceMessages = await alice.listMessages([aliceConvo]);
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

  // This creates 2 users having a conversation and prepares
  // an invalid message from the one pretending to be someone else
  // to verify that it is properly discarded.
  test(
    skip: skipUnlessTestServerEnabled,
    "v2 messaging: invalid sender key bundles on a message should be discarded",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var alice = await _createLocalManager(aliceWallet);
      var aliceAddress = aliceWallet.address.hexEip55;

      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bob = await _createLocalManager(bobWallet);
      var bobAddress = bobWallet.address.hexEip55;

      // This is the fake user that Bob pretends to be.
      var carlWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var carlIdentity = EthPrivateKey.createRandom(Random.secure());
      var carlKeys = await carlWallet.createIdentity(carlIdentity);
      // Carl's contact bundle is publically available.
      var carlContact = createContactBundleV2(carlKeys);

      // Alice initiates the conversation (sending off the invites)
      var aliceConvo = await alice.newConversation(
          bobAddress,
          xmtp.InvitationV1_Context(
            conversationId: "example.com/sneaky-fake-sender-key-bundle",
          ));
      await delayToPropagate();
      var bobConvo = (await bob.listConversations())[0];

      // Helper to inspect transcript (from Alice's perspective).
      getTranscript() async => (await alice.listMessages([aliceConvo]))
          .reversed
          .map((msg) => '${msg.sender.hexEip55}> ${msg.content}');

      await alice.sendMessage(aliceConvo, "hello Bob, it's me Alice!");
      await delayToPropagate();
      await bob.sendMessage(bobConvo, "oh hi Alice, it's me Bob!");
      await delayToPropagate();

      // Everything looks good,
      expect(await getTranscript(), [
        "$aliceAddress> hello Bob, it's me Alice!",
        "$bobAddress> oh hi Alice, it's me Bob!",
      ]);

      // Now Bob tries to pretend to be Carl using Carl's contact info.
      var original = await TextCodec().encode("I love you!");
      var now = nowNs();
      var header = xmtp.MessageHeaderV2(topic: bobConvo.topic, createdNs: now);
      var signed = await signContent(bob.auth.keys, header, original);

      // Here's where Bob pretends to be Carl using Carl's public identity key.
      signed.sender.identityKey = carlContact.v2.keyBundle.identityKey;

      var fakeMessage = await encryptMessageV2(bobConvo.invite, header, signed);
      await bob.api.client.publish(xmtp.PublishRequest(envelopes: [
        xmtp.Envelope(
          contentTopic: bobConvo.topic,
          timestampNs: now,
          message: xmtp.Message(v2: fakeMessage).writeToBuffer(),
        )
      ]));
      await delayToPropagate();

      // ... then Alice can inspect the topic directly to see the bad message.
      var inspecting = await alice.api.client
          .query(xmtp.QueryRequest(contentTopics: [aliceConvo.topic]));
      expect(inspecting.envelopes.length, 3 /* = 2 valid + 1 bad */);

      // ... but when she lists messages the fake one is properly discarded.
      expect(await getTranscript(), [
        "$aliceAddress> hello Bob, it's me Alice!",
        "$bobAddress> oh hi Alice, it's me Bob!",
        // There's no fake message here from Carl
      ]);

      await alice.sendMessage(aliceConvo, "did you say something?");

      // ... and the conversation continues on, still discarding bad messages.
      expect(await getTranscript(), [
        "$aliceAddress> hello Bob, it's me Alice!",
        "$bobAddress> oh hi Alice, it's me Bob!",
        // There's no fake message here from Carl
        "$aliceAddress> did you say something?",
      ]);
    },
  );

  // This creates 2 users connected to the API and prepares
  // an invalid invitation (mismatched timestamps)
  // to verify that it is properly discarded.
  test(
    skip: skipUnlessTestServerEnabled,
    "v2 messaging: mismatched timestamps on an invite should be discarded",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var alice = await _createLocalManager(aliceWallet);
      var bob = await _createLocalManager(bobWallet);
      var bobAddress = bobWallet.address.hex;

      var aliceChats = await alice.listConversations();
      var bobChats = await bob.listConversations();
      expect(aliceChats.length, 0);
      expect(bobChats.length, 0);

      // Use low-level API call to pretend Alice sent an invalid invitation.
      var badInviteSealedAt = nowNs();
      var badInvitePublishedAt = nowNs() + 12345;
      // Note: these ^ timestamps do not match which makes the envelope invalid
      var bobPeer = await alice.contacts.getUserContactV2(bobAddress);
      var invalidInvite = await encryptInviteV1(
        alice.auth.keys,
        bobPeer.v2.keyBundle,
        createInviteV1(xmtp.InvitationV1_Context(
          conversationId: "example.com/not-valid-mismatched-timestamps",
        )),
        badInviteSealedAt,
      );
      await alice.api.client.publish(xmtp.PublishRequest(envelopes: [
        xmtp.Envelope(
          contentTopic: Topic.userInvite(bobAddress),
          timestampNs: badInvitePublishedAt,
          message: invalidInvite.writeToBuffer(),
        )
      ]));
      await delayToPropagate();

      // Now looking at the low-level invites we see that Bob has received it...
      var raw = await bob.api.client.query(xmtp.QueryRequest(
        contentTopics: [Topic.userInvite(bobAddress)],
      ));
      expect(
        xmtp.SealedInvitation.fromBuffer(raw.envelopes[0].message),
        invalidInvite,
      );
      // ... but when Bob lists conversations the invalid one is discarded.
      expect((await bob.listConversations()).length, 0);

      // But later if Alice sends a _valid_ invite...
      await alice.newConversation(
        bobAddress,
        xmtp.InvitationV1_Context(
          conversationId: "example.com/valid",
        ),
      );
      await delayToPropagate();

      // ... then Bob should see that new conversation (and still discard the
      // earlier invalid invitation).
      expect((await bob.listConversations()).length, 1);
      var bobConvo = (await bob.listConversations())[0];
      expect(bobConvo.conversationId, "example.com/valid");
    },
  );

  // This creates 2 users connected to the API and having a conversation.
  // It sends a message with invalid payload (bad content signature)
  // to verify that it is properly discarded.
  test(
    skip: skipUnlessTestServerEnabled,
    "v2 messaging: bad signature on a message should be discarded",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var alice = await _createLocalManager(aliceWallet);
      var bob = await _createLocalManager(bobWallet);
      var aliceAddress = aliceWallet.address.hex;
      var bobAddress = bobWallet.address.hex;

      var aliceChats = await alice.listConversations();
      var bobChats = await bob.listConversations();
      expect(aliceChats.length, 0);
      expect(bobChats.length, 0);

      // First Alice invites Bob to the conversation
      var aliceConvo = await alice.newConversation(
        bobAddress,
        xmtp.InvitationV1_Context(
          conversationId: "example.com/valid",
        ),
      );
      await delayToPropagate();
      var bobConvo = (await bob.listConversations())[0];
      expect(bobConvo.conversationId, "example.com/valid");

      // Helper to inspect transcript (from Alice's perspective).
      getTranscript() async => (await alice.listMessages([aliceConvo]))
          .reversed
          .map((msg) => '${msg.sender.hex}> ${msg.content}');

      // There are no messages at first.
      expect(await getTranscript(), []);

      // But then Alice sends a message to greet Bob.
      await alice.sendMessage(aliceConvo, "hello Bob, it's me Alice!");
      await delayToPropagate();

      // That first messages should show up in the transcript.
      expect(await getTranscript(), [
        "$aliceAddress> hello Bob, it's me Alice!",
      ]);

      // And when Bob sends a greeting back...
      await bob.sendMessage(bobConvo, "Oh, good to chat with you Alice!");
      await delayToPropagate();

      // ... Bob's message should show up in the transcript too.
      expect(await getTranscript(), [
        "$aliceAddress> hello Bob, it's me Alice!",
        "$bobAddress> Oh, good to chat with you Alice!",
      ]);

      // But when Bob's payload is tampered with...
      // (we simulate this using low-level API calls with a bad payload)
      var original = await TextCodec().encode("I love you!");
      var tampered = await TextCodec().encode("I hate you!");
      var now = nowNs();
      var header = xmtp.MessageHeaderV2(topic: bobConvo.topic, createdNs: now);
      var signed = await signContent(bob.auth.keys, header, original);
      // Here's where we pretend to tamper the payload (after signing).
      signed.payload = tampered.writeToBuffer();
      var tamperedMessage =
          await encryptMessageV2(bobConvo.invite, header, signed);
      await bob.api.client.publish(xmtp.PublishRequest(envelopes: [
        xmtp.Envelope(
          contentTopic: bobConvo.topic,
          timestampNs: now,
          message: xmtp.Message(v2: tamperedMessage).writeToBuffer(),
        )
      ]));
      await delayToPropagate();

      // ... then Alice can inspect the topic directly to sees the bad message.
      var inspecting = await alice.api.client
          .query(xmtp.QueryRequest(contentTopics: [aliceConvo.topic]));
      expect(inspecting.envelopes.length, 3 /* = 2 valid + 1 bad */);

      // ... but when she lists messages the tampered one is properly discarded.
      expect(await getTranscript(), [
        "$aliceAddress> hello Bob, it's me Alice!",
        "$bobAddress> Oh, good to chat with you Alice!",
        // The bad 3rd message was discarded.
      ]);
    },
  );

  // This connects to the dev network to test decrypting v2 messages
  // NOTE: it requires a private key
  test(
    skip: "manual testing only",
    "dev: v2 message reading - listing invites, decrypting messages",
    () async {
      var api = Api.create(
        host: 'dev.xmtp.network',
        port: 5556,
        isSecure: true,
        debugLogRequests: true,
      );
      var wallet = EthPrivateKey.fromHex("... private key ...").asSigner();
      var auth = AuthManager(wallet.address, api);
      var codecs = CodecRegistry()..registerCodec(TextCodec());
      var contacts = ContactManager(api);
      await auth.authenticateWithCredentials(wallet);
      var v2 = ConversationManagerV2(
        wallet.address,
        api,
        auth,
        codecs,
        contacts,
      );
      var conversations = await v2.listConversations();
      for (var convo in conversations) {
        debugPrint("dm w/ ${convo.peer}");
        var dms = await v2.listMessages([convo]);
        for (var j = 0; j < dms.length; ++j) {
          var dm = dms[j];
          debugPrint("${dm.sentAt} ${dm.sender.hexEip55}> ${dm.content}");
        }
      }
    },
  );
}

// helpers

Future<ConversationManagerV2> _createLocalManager(Signer wallet) async {
  var api = createTestServerApi();
  var auth = AuthManager(wallet.address, api);
  var codecs = CodecRegistry()..registerCodec(TextCodec());
  var contacts = ContactManager(api);
  var keys = await auth.authenticateWithCredentials(wallet);
  var myContacts = await contacts.getUserContacts(wallet.address.hex);
  if (myContacts.isEmpty) {
    await contacts.saveContact(keys);
    await delayToPropagate();
  }
  return ConversationManagerV2(
    wallet.address,
    api,
    auth,
    codecs,
    contacts,
  );
}
