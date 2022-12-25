import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/common/api.dart';
import 'package:xmtp/src/common/signature.dart';
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
      var aliceWallet =
          await EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobWallet =
          await EthPrivateKey.createRandom(Random.secure()).asSigner();
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

      // They both get the invite.
      expect((await alice.listConversations()).length, 1);
      expect((await bob.listConversations()).length, 1);
      var bobConvo = (await bob.listConversations())[0];

      // They see each other as the recipients.
      expect(aliceConvo.peer, bobWallet.address);
      expect(bobConvo.peer, aliceWallet.address);

      // Bob starts listening to the stream and recording the transcript.
      var transcript = [];
      var bobListening = bob
          .streamMessages(bobConvo)
          .listen((msg) => transcript.add('${msg.sender.hex}> ${msg.content}'));

      // Alice sends the first message.
      await alice.sendMessage(aliceConvo, "hello Bob, it's me Alice!");

      // And Bob see the message in the conversation.
      var bobMessages = await bob.listMessages(bobConvo);
      expect(bobMessages.length, 1);
      expect(bobMessages[0].sender, aliceWallet.address);
      expect(bobMessages[0].content, "hello Bob, it's me Alice!");

      // Bob replies
      await bob.sendMessage(bobConvo, "oh, hello Alice!");

      var aliceMessages = await alice.listMessages(aliceConvo);
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
      var wallet =
          await EthPrivateKey.fromHex("... private key ...").asSigner();
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
        var dms = await v2.listMessages(convo);
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
    await Future.delayed(const Duration(milliseconds: 100));
  }
  return ConversationManagerV2(
    wallet.address,
    api,
    auth,
    codecs,
    contacts,
  );
}
