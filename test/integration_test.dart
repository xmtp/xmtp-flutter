import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/api.dart';
import 'package:xmtp/src/auth.dart';
import 'package:xmtp/src/contact.dart';
import 'package:xmtp/src/content.dart';
import 'package:xmtp/src/crypto.dart';
import 'package:xmtp/src/signature.dart';
import 'package:xmtp/src/topic.dart';

void main() {
  // This attempts to read a known-saved key from the network.
  // It's part of the rigging used to test xmtp-js compat.
  // (e.g. it assumes a JS client has elsewhere stored the key to the network)
  test(
    skip: "manual testing only",
    'js compat',
    () async {
      // We use explicit private keys so that a JS edition running
      // in parallel can read/write as the same identity.
      var alice = EthPrivateKey.fromHex(
          // address = "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"
          "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
      var identity = EthPrivateKey.fromHex(
          // address = "0x70997970c51812dc3a010c7d01b50e0d17dc79c8"
          "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d");
      var authorized = await alice.createIdentity(identity);
      var authToken = await authorized.createAuthToken();
      var api = Api.create(
        host: '127.0.0.1',
        port: 5556,
        isSecure: false,
        debugLogRequests: true,
      );
      api.setAuthToken(authToken);

      var stored = await _lookupPrivateKeys(api, alice.address.hexEip55);
      expect(stored.length, 1);
      var decrypted = await alice.enableIdentityLoading(stored.first);
      expect(decrypted.identity.privateKey, identity.privateKey);
      expect(decrypted.wallet.hexEip55, alice.address.hexEip55);
    },
  );

  // This creates and authorizes an identity key.
  // It saves (encrypts) that key to the network storage
  // and then loads (decrypts) it back.
  test(
    skip: "manual testing only",
    "storing private keys",
    () async {
      var alice = EthPrivateKey.createRandom(Random.secure());
      var identity = EthPrivateKey.createRandom(Random.secure());

      // Prompt them to sign "XMTP : Create Identity ..."
      var authorized = await alice.createIdentity(identity);

      // Create the `Authorization: Bearer $authToken` for API calls.
      var authToken = await authorized.createAuthToken();

      // Setup the API client.
      var api = Api.create(
        host: '127.0.0.1',
        port: 5556,
        isSecure: false,
        debugLogRequests: true,
      );
      api.setAuthToken(authToken);

      var stored = await _lookupPrivateKeys(api, alice.address.hexEip55);

      expect(stored.length, 0, reason: "alice has no stored keys yet");

      // Ask her to authorize us to save it.
      var encrypted = await alice.enableIdentitySaving(authorized);

      // Now store a private key for alice.
      await _savePrivateKeys(api, alice.address.hexEip55, encrypted);

      stored = await _lookupPrivateKeys(api, alice.address.hexEip55);
      expect(stored.length, 1);

      // Then we ask her to allow us to decrypt it.
      var decrypted = await alice.enableIdentityLoading(stored.first);
      expect(decrypted, authorized);
      expect(decrypted.identity.address.hexEip55, identity.address.hexEip55);
      expect(decrypted.wallet.hexEip55, alice.address.hexEip55);
    },
  );

  test(
    skip: "manual testing only",
    "dev: inspecting contacts, saved keys for particular wallet on dev network",
    () async {
      // Setup the API client.
      var api = Api.create(
        host: 'dev.xmtp.network',
        port: 5556,
        isSecure: true,
        debugLogRequests: true,
      );
      var alice = EthPrivateKey.createRandom(Random.secure());
      // var alice = EthPrivateKey.fromHex("...private key...");
      var contacts = await _lookupContact(api, alice.address.hexEip55);
      for (var i = 0; i < contacts.length; ++i) {
        var contact = contacts[i];
        var wallet = contact.wallet.hexEip55;
        var identity = contact.identity.hexEip55;
        var pre = contact.hasPre ? contact.pre.hexEip55 : "(none)";
        debugPrint("[$i] ${contact.whichVersion()}");
        debugPrint("    wallet $wallet");
        debugPrint("    -> identity $identity");
        debugPrint("       -> pre $pre");
      }
      var bundles = await _lookupPrivateKeys(api, alice.address.hexEip55);
      for (var i = 0; i < bundles.length; ++i) {
        var encrypted = bundles[i];
        debugPrint("[$i] ${encrypted.whichVersion()}");
        var decrypted = await alice.enableIdentityLoading(encrypted);
        try {
          var wallet = decrypted.wallet.hexEip55;
          var identity = decrypted.identity.address.hexEip55;
          var pre = decrypted.preKeys.isNotEmpty
              ? decrypted.preKeys.first.address.hexEip55
              : "(none)";
          debugPrint("    wallet $wallet");
          debugPrint("    -> identity $identity");
          debugPrint("       -> pre $pre");
        } catch (err) {
          debugPrint("[$i] error: $err");
          debugPrint(
              "[$i] error: encrypted ${encrypted.whichVersion()}\n $encrypted");
          debugPrint(
              "[$i] error: decrypted ${decrypted.whichVersion()}\n $decrypted");
          rethrow;
        }
      }
    },
  );

  test(
    skip: "manual testing only",
    "dev: inspecting contacts for particular wallets on dev network",
    () async {
      // Setup the API client.
      var api = Api.create(
        host: 'dev.xmtp.network',
        port: 5556,
        isSecure: true,
        debugLogRequests: true,
      );

      var walletAddress =
          "0x359B0ceb2daBcBB6588645de3B480c8203aa5b76"; // dmccartney.eth
      // var walletAddress = "0xf0EA7663233F99D0c12370671abBb6Cca980a490"; // saulmc.eth
      // var walletAddress = "0x66942eC8b0A6d0cff51AEA9C7fd00494556E705F"; // anoopr.eth

      var stored = await _lookupContact(api, walletAddress);
      for (var i = 0; i < stored.length; ++i) {
        var contact = stored[i];
        try {
          var wallet = contact.wallet.hexEip55;
          var identity = contact.identity.hexEip55;
          var pre = contact.hasPre ? contact.pre.hexEip55 : "(none)";
          debugPrint("[$i] ${contact.whichVersion()}");
          debugPrint("    wallet $wallet");
          debugPrint("    -> identity $identity");
          debugPrint("       -> pre $pre");
        } catch (err) {
          debugPrint("[$i] ${contact.whichVersion()}: err: $err");
        }
        expect(
          contact.wallet.hexEip55,
          walletAddress,
        );
      }
    },
  );

  test(
    skip: "manual testing only",
    "contact creation / loading",
    () async {
      // Setup the API client.
      var api = Api.create(
        host: '127.0.0.1',
        port: 5556,
        isSecure: false,
        debugLogRequests: true,
      );

      var alice = EthPrivateKey.createRandom(Random.secure());

      // First lookup if she has a contact (i.e. if she has an account)
      var stored = await _lookupContact(api, alice.address.hexEip55);
      expect(stored.length, 0); // nope, no account

      // So we create an identity key and authorize it
      var identity = EthPrivateKey.createRandom(Random.secure());
      var authorized = await alice.createIdentity(identity);
      var authToken = await authorized.createAuthToken();
      api.setAuthToken(authToken);

      var bundle = createContactBundleV1(authorized);
      await _saveContact(api, alice.address.hexEip55, bundle);

      // Now when we lookup alice again, she should have a contact
      stored = await _lookupContact(api, alice.address.hexEip55);
      expect(stored.length, 1);
      expect(stored.first.wallet.hexEip55, alice.address.hexEip55);
    },
  );

  // This creates 2 users connected to the API and sends DMs
  // back and forth using message API V1.
  test(
    skip: "manual testing only",
    "v1 messaging: intros, reading, writing, streaming",
    () async {
      // Setup the API clients.
      var aliceApi = Api.create(host: '127.0.0.1', port: 5556, isSecure: false);
      var bobApi = Api.create(host: '127.0.0.1', port: 5556, isSecure: false);

      // setup Alice's account and API session
      var aliceWallet = EthPrivateKey.createRandom(Random.secure());
      var aliceIdentity = EthPrivateKey.createRandom(Random.secure());
      var aliceKeys = await aliceWallet.createIdentity(aliceIdentity);
      var aliceAuthToken = await aliceKeys.createAuthToken();
      aliceApi.setAuthToken(aliceAuthToken);
      await _saveContact(
        aliceApi,
        aliceWallet.address.hexEip55,
        createContactBundleV1(aliceKeys),
      );

      // setup Bob's account and API session
      var bobWallet = EthPrivateKey.createRandom(Random.secure());
      var bobIdentity = EthPrivateKey.createRandom(Random.secure());
      var bobKeys = await bobWallet.createIdentity(bobIdentity);
      var bobAuthToken = await bobKeys.createAuthToken();
      bobApi.setAuthToken(bobAuthToken);
      await _saveContact(
        bobApi,
        bobWallet.address.hexEip55,
        createContactBundleV1(bobKeys),
      );

      // Load their contacts
      var aliceAddress = aliceWallet.address.hexEip55;
      var bobAddress = bobWallet.address.hexEip55;
      var aliceContact = (await _lookupContact(aliceApi, aliceAddress)).first;
      var bobContact = (await _lookupContact(bobApi, bobAddress)).first;

      expect(aliceContact.whichVersion(), xmtp.ContactBundle_Version.v1);
      expect(bobContact.whichVersion(), xmtp.ContactBundle_Version.v1);

      // Gather subscriptions here so we can clean them up later.
      //  map of { topic -> subscription }
      Map<String, StreamSubscription<xmtp.Envelope>> subscription = {};

      // We'll log the transcript here
      var transcript = [];
      // This creates a transcript recorder that listens to intros + DMs.
      createRecorder(
        EthPrivateKey wallet,
        Api api,
        xmtp.PrivateKeyBundle keys,
      ) =>
          (e) async {
            var intro = xmtp.Message.fromBuffer(e.message);
            var header = xmtp.MessageHeaderV1.fromBuffer(intro.v1.headerBytes);
            var sender = header.sender.identityKey
                .recoverWalletSignerPublicKey()
                .toEthereumAddress();
            var recipient = header.recipient.identityKey
                .recoverWalletSignerPublicKey()
                .toEthereumAddress();
            var peer =
                {sender, recipient}.firstWhere((a) => a != wallet.address);

            debugPrint("${wallet.address} was introduced to $peer");
            // Now subscribe to the DMs with this peer.
            var dms =
                Topic.directMessageV1(wallet.address.hexEip55, peer.hexEip55);
            subscription[dms] ??= api.client
                .subscribe(xmtp.SubscribeRequest(contentTopics: [dms]))
                .listen((e) async {
              var dm = xmtp.Message.fromBuffer(e.message);
              var encoded = await decryptMessageV1(dm.v1, keys);
              var header = xmtp.MessageHeaderV1.fromBuffer(dm.v1.headerBytes);
              var sender = header.sender.identityKey
                  .recoverWalletSignerPublicKey()
                  .toEthereumAddress();
              var text = utf8.decode(encoded.content); // todo: use codecs
              transcript.add("${sender.hexEip55}> $text");
            });
          };

      // This attaches transcript recorders to Alice and Bobs intros + dms.
      var bobIntros = Topic.userIntro(bobAddress);
      subscription[bobIntros] ??= bobApi.client
          .subscribe(xmtp.SubscribeRequest(contentTopics: [bobIntros]))
          .listen(createRecorder(bobWallet, bobApi, bobKeys));
      var aliceIntros = Topic.userIntro(aliceAddress);
      subscription[aliceIntros] ??= aliceApi.client
          .subscribe(xmtp.SubscribeRequest(contentTopics: [aliceIntros]))
          .listen(createRecorder(aliceWallet, aliceApi, aliceKeys));

      // Wait a beat to make sure the subscriptions are live.
      await Future.delayed(const Duration(milliseconds: 100));

      // Now pretend that Alice sends Bob an intro + DM
      var fromAlice = await encryptMessageV1(
          aliceKeys,
          bobContact.v1.keyBundle,
          xmtp.EncodedContent(
            type: contentTypeText,
            fallback: "hello Bob, it's me Alice!",
            content: utf8.encode("hello Bob, it's me Alice!"),
          ));

      // Alice sends the initial message to their /dm and both of their /intros
      await _sendIntroV1(aliceApi, bobAddress, fromAlice);
      await _sendIntroV1(aliceApi, aliceAddress, fromAlice);
      await _sendDirectMessageV1(aliceApi, aliceAddress, bobAddress, fromAlice);

      // And then a couple seconds later Bob sends a reply to Alice
      var fromBob = await encryptMessageV1(
          bobKeys,
          aliceContact.v1.keyBundle,
          xmtp.EncodedContent(
            type: contentTypeText,
            fallback: "oh, hello Alice!",
            content: utf8.encode("oh, hello Alice!"),
          ));
      await _sendDirectMessageV1(bobApi, bobAddress, aliceAddress, fromBob);

      // wait a couple seconds then close all subscriptions
      await Future.delayed(const Duration(seconds: 1));

      // then close all subscriptions
      await Future.wait(subscription.values.map((sub) => sub.cancel()));

      debugPrint("transcript:\n${transcript.join("\n")}");

      expect(transcript, [
        "$aliceAddress> hello Bob, it's me Alice!",
        "$bobAddress> oh, hello Alice!",
      ]);
    },
  );

  // This connects to the dev network to test decrypting DMs from the JS client.
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

      var alice = EthPrivateKey.fromHex("... put private key here...");

      var walletAddress = alice.address.hexEip55;
      var encryptedKeys = (await _lookupPrivateKeys(api, walletAddress)).first;
      var keys = await alice.enableIdentityLoading(encryptedKeys);
      var intros = await _lookupIntros(api, walletAddress);

      // Gather all the V1 peers
      var peers = intros.expand((intro) {
        var header = xmtp.MessageHeaderV1.fromBuffer(intro.v1.headerBytes);
        var sender = header.sender.identityKey
            .recoverWalletSignerPublicKey()
            .toEthereumAddress();
        var recipient = header.recipient.identityKey
            .recoverWalletSignerPublicKey()
            .toEthereumAddress();
        return [
          sender.hexEip55,
          recipient.hexEip55,
        ];
      }).toSet() // This remove duplicates.
        ..remove(walletAddress);

      // List the DMs with each of the peers.
      for (var peer in peers) {
        debugPrint("dm w/ $peer");
        var dms =
            await _lookupDirectMessageV1s(api, alice.address.hexEip55, peer);
        for (var j = 0; j < dms.length; ++j) {
          var dm = dms[j];
          var encoded = await decryptMessageV1(dm.v1, keys);
          var header = xmtp.MessageHeaderV1.fromBuffer(dm.v1.headerBytes);
          var sender = header.sender.identityKey
              .recoverWalletSignerPublicKey()
              .toEthereumAddress();
          var text = utf8.decode(encoded.content); // todo: use codecs
          debugPrint("${header.timestamp} ${sender.hexEip55}> $text");
        }
      }
    },
  );

  // This creates 2 users connected to the API and sends DMs
  // back and forth using message API V2.
  test(
    skip: "manual testing only",
    "v2 messaging: invites, reading, writing, streaming",
    () async {
      // Setup the API clients.
      var aliceApi = Api.create(host: '127.0.0.1', port: 5556, isSecure: false);
      var bobApi = Api.create(host: '127.0.0.1', port: 5556, isSecure: false);

      // setup Alice's account and API session
      var aliceWallet = EthPrivateKey.createRandom(Random.secure());
      var aliceIdentity = EthPrivateKey.createRandom(Random.secure());
      var aliceKeys = await aliceWallet.createIdentity(aliceIdentity);
      var aliceAuthToken = await aliceKeys.createAuthToken();
      aliceApi.setAuthToken(aliceAuthToken);
      await _saveContact(
        aliceApi,
        aliceWallet.address.hexEip55,
        createContactBundleV2(aliceKeys),
      );

      // setup Bob's account and API session
      var bobWallet = EthPrivateKey.createRandom(Random.secure());
      var bobIdentity = EthPrivateKey.createRandom(Random.secure());
      var bobKeys = await bobWallet.createIdentity(bobIdentity);
      var bobAuthToken = await bobKeys.createAuthToken();
      bobApi.setAuthToken(bobAuthToken);
      await _saveContact(
        bobApi,
        bobWallet.address.hexEip55,
        createContactBundleV2(bobKeys),
      );

      // Load their contacts
      var aliceAddress = aliceWallet.address.hexEip55;
      var bobAddress = bobWallet.address.hexEip55;
      var aliceContact = (await _lookupContact(aliceApi, aliceAddress)).first;
      var bobContact = (await _lookupContact(bobApi, bobAddress)).first;

      expect(aliceContact.whichVersion(), xmtp.ContactBundle_Version.v2);
      expect(bobContact.whichVersion(), xmtp.ContactBundle_Version.v2);

      // Gather subscriptions here so we can clean them up later.
      //  map of { topic -> subscription }
      Map<String, StreamSubscription<xmtp.Envelope>> subscription = {};

      // We'll log the transcript here
      var transcript = [];
      // This creates a transcript recorder that listens to invites + messages.
      createRecorder(
        EthPrivateKey wallet,
        Api api,
        xmtp.PrivateKeyBundle keys,
      ) =>
          (e) async {
            var invite = xmtp.SealedInvitation.fromBuffer(e.message);
            var decrypted = await decryptInviteV1(invite.v1, keys);
            var topic = decrypted.topic;
            var secret = decrypted.aes256GcmHkdfSha256.keyMaterial;
            debugPrint("${wallet.address} was invited to $topic");
            // Now subscribe to the DMs with this peer.
            subscription[topic] ??= api.client
                .subscribe(xmtp.SubscribeRequest(contentTopics: [topic]))
                .listen((e) async {
              var msg = xmtp.Message.fromBuffer(e.message);
              var decryptedBytes = await decrypt(
                secret,
                msg.v2.ciphertext,
                aad: msg.v2.headerBytes,
              );
              var signed = xmtp.SignedContent.fromBuffer(decryptedBytes);
              var sender = signed.sender.identityKey
                  .recoverWalletSignerPublicKey()
                  .toEthereumAddress();
              var encoded = xmtp.EncodedContent.fromBuffer(signed.payload);
              var text = utf8.decode(encoded.content); // todo: use codecs
              transcript.add("${sender.hexEip55}> $text");
            });
          };

      // This attaches transcript recorders to Alice and Bobs invites + msgs.
      var bobInvites = Topic.userInvite(bobAddress);
      subscription[bobInvites] ??= bobApi.client
          .subscribe(xmtp.SubscribeRequest(contentTopics: [bobInvites]))
          .listen(createRecorder(bobWallet, bobApi, bobKeys));
      var aliceInvites = Topic.userInvite(aliceAddress);
      subscription[aliceInvites] ??= aliceApi.client
          .subscribe(xmtp.SubscribeRequest(contentTopics: [aliceInvites]))
          .listen(createRecorder(aliceWallet, aliceApi, aliceKeys));

      // Wait a beat to make sure the subscriptions are live.
      await Future.delayed(const Duration(milliseconds: 100));

      // Create the new conversation.
      var invite = createInviteV1(xmtp.InvitationV1_Context(
        conversationId: "https://example.com/1",
        metadata: {"foo": "bar"},
      ));
      var sealed = await encryptInviteV1(
        aliceKeys,
        bobContact.v2.keyBundle,
        invite,
      );
      // Send the invite to both Alice and Bob.
      await _sendInviteV1(aliceApi, aliceAddress, sealed);
      await _sendInviteV1(aliceApi, bobAddress, sealed);

      // Send a message from Alice
      await _sendMessageV2(
          aliceApi,
          invite.topic,
          await encryptMessageV2(
            aliceKeys,
            invite,
            xmtp.EncodedContent(
              type: contentTypeText,
              fallback: "hello Bob, it's me Alice!",
              content: utf8.encode("hello Bob, it's me Alice!"),
            ),
          ));

      // Send a message from Bob
      await _sendMessageV2(
          bobApi,
          invite.topic,
          await encryptMessageV2(
            bobKeys,
            invite,
            xmtp.EncodedContent(
              type: contentTypeText,
              fallback: "oh, hello Alice!",
              content: utf8.encode("oh, hello Alice!"),
            ),
          ));

      // wait a beat then close all subscriptions
      await Future.delayed(const Duration(milliseconds: 200));

      // then close all subscriptions
      await Future.wait(subscription.values.map((sub) => sub.cancel()));

      debugPrint("transcript:\n${transcript.join("\n")}");

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

      var alice = EthPrivateKey.fromHex("... private key ...");

      var walletAddress = alice.address.hexEip55;
      var encryptedKeys = (await _lookupPrivateKeys(api, walletAddress)).first;
      var keys = await alice.enableIdentityLoading(encryptedKeys);
      var invites = await _lookupInvites(api, walletAddress);
      debugPrint("invites ${invites.length}");
      for (var i = 0; i < invites.length; ++i) {
        var encrypted = invites[i];
        var invite = await decryptInviteV1(encrypted.v1, keys);
        var topic = invite.topic;
        debugPrint("[$i] ${invite.topic}");
        var msgs = await _lookupMessageV2s(api, topic);
        for (var j = 0; j < msgs.length; ++j) {
          var msg = msgs[j];
          var signed = await decryptMessageV2(msg.v2, invite);
          var sender = signed.sender.identityKey
              .recoverWalletSignerPublicKey()
              .toEthereumAddress();
          var encoded = xmtp.EncodedContent.fromBuffer(signed.payload);
          var text = utf8.decode(encoded.content);
          debugPrint("[$i][$j] ${sender.hexEip55}> $text");
        }
      }
    },
  );
}

// Helpers
// TODO: fold these into the eventual Client

Future<List<xmtp.SealedInvitation>> _lookupInvites(
  Api api,
  String walletAddress,
) async {
  var listing = await api.client.query(xmtp.QueryRequest(
    contentTopics: [Topic.userInvite(walletAddress)],
    // pagingInfo: xmtp.PagingInfo()
  ));
  return listing.envelopes
      .map((e) => xmtp.SealedInvitation.fromBuffer(e.message))
      .toList();
}

Future<List<xmtp.Message>> _lookupIntros(
  Api api,
  String walletAddress,
) async {
  var listing = await api.client.query(xmtp.QueryRequest(
    contentTopics: [Topic.userIntro(walletAddress)],
    // pagingInfo: xmtp.PagingInfo()
  ));
  return listing.envelopes
      .map((e) => xmtp.Message.fromBuffer(e.message))
      .toList();
}

Future<List<xmtp.Message>> _lookupMessageV2s(
  Api api,
  String topic,
) async {
  var listing = await api.client.query(xmtp.QueryRequest(
      contentTopics: [topic],
      pagingInfo: xmtp.PagingInfo(
        direction: xmtp.SortDirection.SORT_DIRECTION_ASCENDING,
      )));
  return listing.envelopes
      .map((e) => xmtp.Message.fromBuffer(e.message))
      .toList();
}

Future<List<xmtp.Message>> _lookupDirectMessageV1s(
  Api api,
  String senderAddress,
  String recipientAddress,
) async {
  var listing = await api.client.query(xmtp.QueryRequest(
      contentTopics: [Topic.directMessageV1(senderAddress, recipientAddress)],
      pagingInfo: xmtp.PagingInfo(
        direction: xmtp.SortDirection.SORT_DIRECTION_ASCENDING,
      )));
  return listing.envelopes
      .map((e) => xmtp.Message.fromBuffer(e.message))
      .toList();
}

Future<xmtp.PublishResponse> _sendDirectMessageV1(
  Api api,
  String senderAddress,
  String recipientAddress,
  xmtp.MessageV1 msg,
) async {
  var res = api.client.publish(xmtp.PublishRequest(envelopes: [
    xmtp.Envelope(
      contentTopic: Topic.directMessageV1(senderAddress, recipientAddress),
      timestampNs: Int64(DateTime.now().millisecondsSinceEpoch) * 1000000,
      message: xmtp.Message(v1: msg).writeToBuffer(),
    ),
  ]));
  await Future.delayed(const Duration(milliseconds: 500));
  return res;
}

Future<xmtp.PublishResponse> _sendIntroV1(
  Api api,
  String walletAddress,
  xmtp.MessageV1 msg,
) async {
  var res = api.client.publish(xmtp.PublishRequest(envelopes: [
    xmtp.Envelope(
      contentTopic: Topic.userIntro(walletAddress),
      timestampNs: Int64(DateTime.now().millisecondsSinceEpoch) * 1000000,
      message: xmtp.Message(v1: msg).writeToBuffer(),
    ),
  ]));
  await Future.delayed(const Duration(milliseconds: 500));
  return res;
}

Future<xmtp.PublishResponse> _sendMessageV2(
  Api api,
  String topic,
  xmtp.MessageV2 msg,
) async {
  var res = api.client.publish(xmtp.PublishRequest(envelopes: [
    xmtp.Envelope(
      contentTopic: topic,
      timestampNs: Int64(DateTime.now().millisecondsSinceEpoch) * 1000000,
      message: xmtp.Message(v2: msg).writeToBuffer(),
    ),
  ]));
  await Future.delayed(const Duration(milliseconds: 500));
  return res;
}

Future<xmtp.PublishResponse> _sendInviteV1(
  Api api,
  String walletAddress,
  xmtp.SealedInvitation sealed,
) async {
  var res = api.client.publish(xmtp.PublishRequest(envelopes: [
    xmtp.Envelope(
      contentTopic: Topic.userInvite(walletAddress),
      timestampNs: Int64(DateTime.now().millisecondsSinceEpoch) * 1000000,
      message: sealed.writeToBuffer(),
    ),
  ]));
  await Future.delayed(const Duration(milliseconds: 500));
  return res;
}

Future<List<xmtp.EncryptedPrivateKeyBundle>> _lookupPrivateKeys(
  Api api,
  String walletAddress, {
  int limit = 100,
}) async {
  var stored = await api.client.query(xmtp.QueryRequest(
    contentTopics: [Topic.userPrivateStoreKeyBundle(walletAddress)],
    pagingInfo: xmtp.PagingInfo(limit: limit),
  ));
  return stored.envelopes
      .map((e) => xmtp.EncryptedPrivateKeyBundle.fromBuffer(e.message))
      .toList();
}

Future<xmtp.PublishResponse> _savePrivateKeys(
  Api api,
  String walletAddress,
  xmtp.EncryptedPrivateKeyBundle encrypted,
) async {
  var res = api.client.publish(xmtp.PublishRequest(envelopes: [
    xmtp.Envelope(
      contentTopic: Topic.userPrivateStoreKeyBundle(walletAddress),
      timestampNs: Int64(DateTime.now().millisecondsSinceEpoch) * 1000000,
      message: encrypted.writeToBuffer(),
    ),
  ]));
  // Wait a sec to let the publish go through.
  await Future.delayed(const Duration(seconds: 1));
  return res;
}

Future<List<xmtp.ContactBundle>> _lookupContact(
  Api api,
  String walletAddress, {
  int limit = 100,
}) async {
  var stored = await api.client.query(xmtp.QueryRequest(
    contentTopics: [Topic.userContact(walletAddress)],
    pagingInfo: xmtp.PagingInfo(limit: limit),
  ));
  return stored.envelopes.map((e) => e.toContactBundle()).toList();
}

Future<xmtp.PublishResponse> _saveContact(
  Api api,
  String walletAddress,
  xmtp.ContactBundle bundle,
) async {
  var res = api.client.publish(xmtp.PublishRequest(envelopes: [
    xmtp.Envelope(
      contentTopic: Topic.userContact(walletAddress),
      timestampNs: Int64(DateTime.now().millisecondsSinceEpoch) * 1000000,
      message: bundle.writeToBuffer(),
    ),
  ]));
  // Wait a sec to let the publish go through.
  await Future.delayed(const Duration(seconds: 1));
  return res;
}
