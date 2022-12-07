import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/auth.dart';
import 'package:xmtp/src/common/api.dart';

import 'test_server.dart';

void main() {
  test('creating authToken', () async {
    var alice = EthPrivateKey.createRandom(Random.secure());
    var identity = EthPrivateKey.createRandom(Random.secure());

    // Prompt them to sign "XMTP : Create Identity ..."
    var authorized = await alice.createIdentity(identity);

    // Create the `Authorization: Bearer $authToken` for API calls.
    var authToken = await authorized.createAuthToken();

    var token = xmtp.Token.fromBuffer(base64.decode(authToken));
    var authData = xmtp.AuthData.fromBuffer(token.authDataBytes);
    expect(authData.walletAddr, alice.address.hexEip55);
  });

  test('enabling saving and loading of stored keys', () async {
    var alice = EthPrivateKey.createRandom(Random.secure());
    var identity = EthPrivateKey.createRandom(Random.secure());

    // Prompt them to sign "XMTP : Create Identity ..."
    var authorized = await alice.createIdentity(identity);

    // Ask her to authorize us to save (encrypt) it.
    var encrypted = await alice.enableIdentitySaving(authorized);

    // Then we ask her to allow us to load (decrypt) it.
    var decrypted = await alice.enableIdentityLoading(encrypted);

    expect(decrypted, authorized);
    expect(decrypted.wallet.hexEip55, alice.address.hexEip55);
    expect(decrypted.identity.address.hexEip55, identity.address.hexEip55);
    expect(decrypted.preKeys.length, 1);
  });

  // This creates and authorizes an identity key.
  // It saves (encrypts) that key to the network storage
  // and then loads (decrypts) it back.
  test(
    skip: !testServerEnabled,
    "storing private keys",
    () async {
      var alice = EthPrivateKey.createRandom(Random.secure());

      // At first, alice authenticates and saves her keys to the network.
      var apiFirst = createTestServerApi();
      var authFirst = AuthManager(alice.address, apiFirst);
      var keysFirst = await authFirst.authenticateWithCredentials(alice);

      // Later, when she authenticates again it loads those keys...
      var apiLater = createTestServerApi();
      var authLater = AuthManager(alice.address, apiLater);
      var keysLater = await authLater.authenticateWithCredentials(alice);

      // ... they should be the same keys that she saved at first.
      expect(keysFirst.wallet, keysLater.wallet);
      expect(keysFirst.identity, keysLater.identity);
      expect(keysFirst.preKeys, keysLater.preKeys);
    },
  );

  // This connects to the dev network to test loading saved keys.
  // NOTE: it requires a private key
  test(
    skip: "manual testing only",
    "dev: inspecting contacts, saved keys for particular wallet on dev network",
    () async {
      // Setup the API client.
      var api = Api.create(
        host: 'dev.xmtp.network',
        port: 5556,
        isSecure: true,
      );
      var alice = EthPrivateKey.fromHex("... private key ...");
      var auth = AuthManager(alice.address, api);
      var decrypted = await auth.authenticateWithCredentials(alice);
      var wallet = decrypted.wallet.hexEip55;
      var identity = decrypted.identity.address.hexEip55;
      var pre = decrypted.preKeys.isNotEmpty
          ? decrypted.preKeys.first.address.hexEip55
          : "(none)";
      debugPrint("wallet $wallet");
      debugPrint(" -> identity $identity");
      debugPrint("  -> pre $pre");
    },
  );
}
