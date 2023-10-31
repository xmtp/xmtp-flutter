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
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var charlieWallet =
          EthPrivateKey.createRandom(Random.secure()).asSigner();
      var alice = await _createLocalManager(aliceWallet);
      var bob = await _createLocalManager(bobWallet);
      var charlie = await _createLocalManager(charlieWallet);
      var aliceAddress = aliceWallet.address.hex;
      var bobAddress = bobWallet.address.hex;

      var aliceChats = await alice.listConversations();
      var bobChats = await bob.listConversations();
      expect(aliceChats.length, 0);
      expect(bobChats.length, 0);

      var aliceConvo = await alice.newConversation(bobAddress);
      var bobConvo = await bob.newConversation(aliceAddress);
      var charlieConvo = await charlie.newConversation(aliceAddress);

      var aliceMessages = await alice.listMessages([aliceConvo]);
      var bobMessages = await bob.listMessages([bobConvo]);
      var charlieAndBobMessages =
          await alice.listMessages([bobConvo, charlieConvo]);

      expect(aliceMessages.length, 0);
      expect(bobMessages.length, 0);
      expect(charlieAndBobMessages.length, 0);

      // Bob starts listening to the stream and recording the transcript.
      var transcript = [];
      var bobListening = bob.streamMessages([bobConvo]).listen(
          (msg) => transcript.add('${msg.sender.hex}> ${msg.content}'));

      // Wait a second to allow contacts to propagate.
      await Future.delayed(const Duration(seconds: 1));

      // Alice sends the first message.
      await alice.sendMessage(aliceConvo, "hello Bob, it's me Alice!");

      // It gets added to both of their conversation lists with that first msg.
      expect((await alice.listConversations()).length, 1);
      expect((await bob.listConversations()).length, 1);

      // And Bob see the message in the conversation.
      bobMessages = await bob.listMessages([bobConvo]);
      expect(bobMessages.length, 1);
      expect(bobMessages[0].sender, aliceWallet.address);
      expect(bobMessages[0].content, "hello Bob, it's me Alice!");

      // Bob replies
      await bob.sendMessage(bobConvo, "oh, hello Alice!");

      aliceMessages = await alice.listMessages([aliceConvo]);
      expect(aliceMessages.length, 2);
      expect(aliceMessages[0].sender, bobWallet.address);
      expect(aliceMessages[0].content, "oh, hello Alice!");
      expect(aliceMessages[1].sender, aliceWallet.address);
      expect(aliceMessages[1].content, "hello Bob, it's me Alice!");

      // Charlie sends a message to Alice.
      await charlie.sendMessage(charlieConvo, "hey Alice, it's Charlie");

      charlieAndBobMessages =
          await alice.listMessages([bobConvo, charlieConvo]);
      expect(charlieAndBobMessages.length, 3);
      expect(charlieAndBobMessages[0].sender, charlieWallet.address);
      expect(charlieAndBobMessages[0].content, "hey Alice, it's Charlie");
      expect(charlieAndBobMessages[1].sender, bobWallet.address);
      expect(charlieAndBobMessages[1].content, "oh, hello Alice!");
      expect(charlieAndBobMessages[2].sender, aliceWallet.address);
      expect(charlieAndBobMessages[2].content, "hello Bob, it's me Alice!");

      await bobListening.cancel();
      expect(transcript, [
        "$aliceAddress> hello Bob, it's me Alice!",
        "$bobAddress> oh, hello Alice!",
      ]);
    },
  );

  test(
    skip: skipUnlessTestServerEnabled,
    timeout: const Timeout.factor(5), // TODO: consider turning off in CI
    "v1 messaging: batch requests should be partitioned to fit max batch size",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      var alice = await _createLocalManager(aliceWallet);
      var aliceAddress = aliceWallet.address.hexEip55;

      // Pretend a bunch of people have messaged alice.
      const conversationCount = maxQueryRequestsPerBatch + 5;
      await Future.wait(List.generate(conversationCount, (i) async {
        var wallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
        var user = await _createLocalManager(wallet, debugLogRequests: false);
        var convo = await user.newConversation(aliceAddress);
        await user.sendMessage(convo, "I am number $i of $conversationCount");
      }));
      await delayToPropagate();

      var convos = await alice.listConversations();
      expect(convos.length, conversationCount);

      var messages = await alice.listMessages(convos);
      expect(messages.length, conversationCount);
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
      var wallet = EthPrivateKey.fromHex("... private key ...").asSigner();
      var auth = AuthManager(wallet.address, api);
      var contacts = ContactManager(api, auth);
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
        var dms = await v1.listMessages([convo]);
        for (var j = 0; j < dms.length; ++j) {
          var dm = dms[j];
          debugPrint("${dm.sentAt} ${dm.sender.hexEip55}> ${dm.content}");
        }
      }
    },
  );
}

// helpers

Future<ConversationManagerV1> _createLocalManager(
  Signer wallet, {
  bool debugLogRequests = kDebugMode,
}) async {
  var api = createTestServerApi(debugLogRequests: debugLogRequests);
  var auth = AuthManager(wallet.address, api);
  var contacts = ContactManager(api, auth);
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
