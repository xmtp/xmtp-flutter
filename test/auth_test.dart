import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/auth.dart';

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
    var encrypted = await alice.enableIdentitySaving(authorized.toBundle());

    // Then we ask her to allow us to load (decrypt) it.
    var decrypted = await alice.enableIdentityLoading(encrypted);
    expect(decrypted.v1.identityKey.secp256k1.bytes, identity.privateKey);
    expect(decrypted.v1.identityKey.publicKey, authorized.authorized);
  });
}
