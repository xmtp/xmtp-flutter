import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/web3dart.dart';

import 'package:xmtp/src/common/api.dart';
import 'package:xmtp/src/client.dart';

import 'test_server.dart';

void main() {
  // This creates 2 new users with connected clients and
  // sends messages back and forth between them.
  test(
    skip: !testServerEnabled,
    "v1 messaging: intros, reading, writing, streaming",
    () async {
      var aliceWallet = EthPrivateKey.createRandom(Random.secure());
      var aliceApi = createTestServerApi();
      var bobWallet = EthPrivateKey.createRandom(Random.secure());
      var bobApi = createTestServerApi();
      var alice = await Client.createFromWallet(aliceApi, aliceWallet);
      var bob = await Client.createFromWallet(bobApi, bobWallet);
      var aliceAddress = aliceWallet.address.hex;
      var bobAddress = bobWallet.address.hex;

      var aliceChats = await alice.listConversations();
      var bobChats = await bob.listConversations();
      expect(aliceChats.length, 0);
      expect(bobChats.length, 0);

      var aliceConvo = await alice.newConversation(bobAddress);
      var bobConvo = await bob.newConversation(aliceAddress);

      var aliceMessages = await aliceConvo.listMessages();
      var bobMessages = await bobConvo.listMessages();

      expect(aliceMessages.length, 0);
      expect(bobMessages.length, 0);

      // Bob starts listening to the stream and recording the transcript.
      var transcript = [];
      var bobListening = bobConvo
          .streamMessages()
          .listen((msg) => transcript.add('${msg.sender.hex}> ${msg.content}'));

      // Alice sends the first message.
      await aliceConvo.send("hello Bob, it's me Alice!");

      // It gets added to both of their conversation lists with that first msg.
      expect((await alice.listConversations()).length, 1);
      expect((await bob.listConversations()).length, 1);

      // And Bob see the message in the conversation.
      bobMessages = await bobConvo.listMessages();
      expect(bobMessages.length, 1);
      expect(bobMessages[0].sender, aliceWallet.address);
      expect(bobMessages[0].content, "hello Bob, it's me Alice!");

      // Bob replies
      await bobConvo.send("oh, hello Alice!");

      aliceMessages = await aliceConvo.listMessages();
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

  // This connects to the dev network to test the client.
  // NOTE: it requires a private key
  test(
    skip: "manual testing only",
    "dev: inspecting contacts, saved keys for particular wallet on dev network",
    () async {
      // Setup the API client.
      var api =
          Api.create(host: 'dev.xmtp.network', port: 5556, isSecure: true);
      var wallet = EthPrivateKey.fromHex("... private key ...");
      var client = await Client.createFromWallet(api, wallet);
      var conversations = await client.listConversations();
      for (var convo in conversations) {
        debugPrint('Conversation with ${convo.peer} ${convo.version}');
        debugPrint(' -> ${convo.topic}');
        var messages = await convo.listMessages();
        for (var msg in messages) {
          debugPrint(' ${msg.sentAt} ${msg.sender}> ${msg.content}');
        }
      }
    },
  );
}
