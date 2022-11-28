import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/api.dart';
import 'package:xmtp/src/auth.dart';
import 'package:xmtp/src/contact.dart';
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

      var bundle = authorized.toContactBundle();
      await _saveContact(api, alice.address.hexEip55, bundle);

      // Now when we lookup alice again, she should have a contact
      stored = await _lookupContact(api, alice.address.hexEip55);
      expect(stored.length, 1);
      expect(stored.first.wallet.hexEip55, alice.address.hexEip55);
    },
  );
}

// Helpers
// TODO: fold these into the eventual Client

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
