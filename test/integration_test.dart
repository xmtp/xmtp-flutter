import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/topic.dart';
import 'package:xmtp/src/auth.dart';
import 'package:xmtp/src/api.dart';

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
      expect(decrypted.v1.identityKey.secp256k1.bytes, identity.privateKey);
      expect(decrypted.v1.identityKey.publicKey, authorized.authorized);
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
      var encrypted = await alice.enableIdentitySaving(authorized.toBundle());

      // Now store a private key for alice.
      await api.client.publish(xmtp.PublishRequest(envelopes: [
        xmtp.Envelope(
          contentTopic: Topic.userPrivateStoreKeyBundle(alice.address.hexEip55),
          timestampNs: Int64(DateTime.now().millisecondsSinceEpoch) * 1000000,
          message: encrypted.writeToBuffer(),
        ),
      ]));
      // Wait a sec to let the publish go through.
      await Future.delayed(const Duration(seconds: 1));

      stored = await _lookupPrivateKeys(api, alice.address.hexEip55);
      expect(stored.length, 1);

      // Then we ask her to allow us to decrypt it.
      var decrypted = await alice.enableIdentityLoading(stored.first);
      expect(decrypted.v1.identityKey.secp256k1.bytes, identity.privateKey);
      expect(decrypted.v1.identityKey.publicKey, authorized.authorized);
    },
  );
}

// Helpers

Future<List<xmtp.EncryptedPrivateKeyBundle>> _lookupPrivateKeys(
  Api api,
  String walletAddress,
) async {
  var stored = await api.client.query(xmtp.QueryRequest(
    contentTopics: [Topic.userPrivateStoreKeyBundle(walletAddress)],
  ));
  return stored.envelopes
      .map((e) => xmtp.EncryptedPrivateKeyBundle.fromBuffer(e.message))
      .toList();
}
