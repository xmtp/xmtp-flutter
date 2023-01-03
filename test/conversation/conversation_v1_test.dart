import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/web3dart.dart';

import 'package:xmtp/src/common/api.dart';
import 'package:xmtp/src/auth.dart';
import 'package:xmtp/src/common/signature.dart';
import 'package:xmtp/src/contact.dart';
import 'package:xmtp/src/content/codec_registry.dart';
import 'package:xmtp/src/content/text_codec.dart';
import 'package:xmtp/src/conversation/conversation_v1.dart';

import '../test_server.dart';

void main() {
  // This creates 2 users connected to the API and sends DMs
  // back and forth using message API V1.
  test(
    skip: skipUnlessTestServerEnabled,
    "v1 messaging: intros, reading, writing, streaming",
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

      var aliceConvo = await alice.newConversation(bobAddress);
      var bobConvo = await bob.newConversation(aliceAddress);

      var aliceMessages = await alice.listMessages(aliceConvo);
      var bobMessages = await bob.listMessages(bobConvo);

      expect(aliceMessages.length, 0);
      expect(bobMessages.length, 0);

      // Bob starts listening to the stream and recording the transcript.
      var transcript = [];
      var bobListening = bob
          .streamMessages(bobConvo)
          .listen((msg) => transcript.add('${msg.sender.hex}> ${msg.content}'));

      // Wait a second to allow contacts to propagate.
      await Future.delayed(const Duration(seconds: 1));

      // Alice sends the first message.
      await alice.sendMessage(aliceConvo, "hello Bob, it's me Alice!");

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

  // This connects to the dev network to test decrypting v1 DMs
  // NOTE: it requires a private key
  test(
    skip: "manual testing only",
    "dev: v1 message reading - listing intros, decrypting DMs",
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
      var contacts = ContactManager(api);
      var codecs = CodecRegistry()..registerCodec(TextCodec());
      await auth.authenticateWithCredentials(wallet);
      var v1 = ConversationManagerV1(
        wallet.address,
        api,
        auth,
        codecs,
        contacts,
      );
      var conversations = await v1.listConversations();
      for (var convo in conversations) {
        debugPrint("dm w/ ${convo.peer}");
        var dms = await v1.listMessages(convo);
        for (var j = 0; j < dms.length; ++j) {
          var dm = dms[j];
          debugPrint("${dm.sentAt} ${dm.sender.hexEip55}> ${dm.content}");
        }
      }
    },
  );
}

// helpers

Future<ConversationManagerV1> _createLocalManager(Signer wallet) async {
  var api = createTestServerApi();
  var auth = AuthManager(wallet.address, api);
  var contacts = ContactManager(api);
  var codecs = CodecRegistry()..registerCodec(TextCodec());
  var keys = await auth.authenticateWithCredentials(wallet);
  var myContacts = await contacts.getUserContacts(wallet.address.hex);
  if (myContacts.isEmpty) {
    await contacts.saveContact(keys);
  }
  return ConversationManagerV1(
    wallet.address,
    api,
    auth,
    codecs,
    contacts,
  );
}
