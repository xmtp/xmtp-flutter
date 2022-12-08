import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/credentials.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/common/crypto.dart';

void main() {
  test('codec', () async {
    const message = [5, 5, 5];
    const secret = [1, 2, 3, 4];
    var encrypted = await encrypt(secret, message);
    var decrypted = await decrypt(secret, encrypted);
    expect(decrypted, message);
  });
  test('decrypting known cyphertext', () async {
    const message = [5, 5, 5];
    const secret = [1, 2, 3, 4];
    var encrypted = xmtp.Ciphertext.fromBuffer([
      // This was generated using xmtp-js code for encrypt().
      10, 69, 10, 32, 23, 10, 217, 190, 235, 216, 145,
      38, 49, 224, 165, 169, 22, 55, 152, 150, 176, 65,
      207, 91, 45, 45, 16, 171, 146, 125, 143, 60, 152,
      128, 0, 120, 18, 12, 219, 247, 207, 184, 141, 179,
      171, 100, 251, 171, 120, 137, 26, 19, 216, 215, 152,
      167, 118, 59, 93, 177, 53, 242, 147, 10, 87, 143,
      27, 245, 154, 169, 109
    ]);
    var decrypted = await decrypt(secret, encrypted);
    expect(decrypted, message);
  });

  test('computing shared secret', () async {
    var alice = EthPrivateKey.createRandom(Random.secure());
    var bob = EthPrivateKey.createRandom(Random.secure());

    var aliceSecret = computeDHSecret(
      createECPrivateKey(alice.privateKey),
      createECPublicKey(bob.encodedPublicKey),
    );
    var bobSecret = computeDHSecret(
      createECPrivateKey(bob.privateKey),
      createECPublicKey(alice.encodedPublicKey),
    );
    expect(aliceSecret, bobSecret);
  });

  test('creating EC keys', () async {
    for (var i = 0; i < 10; ++i) {
      var pair = EthPrivateKey.createRandom(Random.secure());
      createECPrivateKey(pair.privateKey);
      createECPublicKey(pair.encodedPublicKey);
    }
  });

  test('prepending 0x04 to encoded public keys', () async {
    // These reproduce a fixed bug.
    //
    // When the 64 bytes of a public key had a leading byte of 0x04 we were
    // failing to prepend the additional 65th byte of 0x04. This caused the
    // point decoder to reject the malformed key.
    //
    // So these (randomly generated) pairs have public key encodings that
    // all have a 0x04 first byte. This reproduces the issue that was fixed.
    var producesLeading04 = [
      "94b0d16bdd3ff8b8725a3ba90b8a5009cfa3779b5c1bf97c5bad7b5694e929ba",
      "5ed96997701a0ff7f21f598e76953b089f9e0059c0743b3b56de4149a3a96906",
      "f6fc4a83e63ac82ca5bf8c794dd92fa2e54f49a77afe6d648beeab3c941bc9c1",
    ];
    for (var k in producesLeading04) {
      var pair = EthPrivateKey.fromHex(k);
      expect(pair.encodedPublicKey[0], 0x04);
      // This would fail before the fix.
      createECPublicKey(pair.encodedPublicKey);
    }
  });

  test('symmetric 3dh', () async {
    var aliceId = EthPrivateKey.createRandom(Random.secure());
    var alicePre = EthPrivateKey.createRandom(Random.secure());
    var bobId = EthPrivateKey.createRandom(Random.secure());
    var bobPre = EthPrivateKey.createRandom(Random.secure());

    var aliceSecret = compute3DHSecret(
      // what Alice can see
      createECPrivateKey(aliceId.privateKey),
      createECPrivateKey(alicePre.privateKey),
      createECPublicKey(bobId.encodedPublicKey),
      createECPublicKey(bobPre.encodedPublicKey),
      false, // Alice is not the recipient
    );
    var bobSecret = compute3DHSecret(
      // what Bob can see
      createECPrivateKey(bobId.privateKey),
      createECPrivateKey(bobPre.privateKey),
      createECPublicKey(aliceId.encodedPublicKey),
      createECPublicKey(alicePre.encodedPublicKey),
      true, // Bob is the recipient
    );

    expect(aliceSecret, bobSecret, reason: "they should reach the same secret");
  });
}
