import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:web3dart/crypto.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

final _aesGcm256 = AesGcm.with256bits(nonceLength: 12);

final ECDomainParameters _params = ECCurve_secp256k1();

/// This returns the sha256 hash of the input.
List<int> sha256(List<int> input) => (const DartSha256().newHashSink()
      ..add(input)
      ..close())
    .hashSync()
    .bytes;

/// This uses the `secret` to encrypt the `message`.
Future<xmtp.Ciphertext> encrypt(
  List<int> secret,
  List<int> message, {
  List<int> aad = const <int>[],
}) async {
  var hkdfSalt = generateRandomBytes(32);
  var gcmNonce = generateRandomBytes(12);
  final hkdf = Hkdf(
    hmac: Hmac(Sha256()),
    outputLength: 32,
  );
  final key = await hkdf.deriveKey(
    secretKey: SecretKey(secret),
    nonce: hkdfSalt,
  );
  var payload = await _aesGcm256.encrypt(
    message,
    secretKey: key,
    aad: aad,
    nonce: gcmNonce,
  );
  return xmtp.Ciphertext(
      aes256GcmHkdfSha256: xmtp.Ciphertext_Aes256gcmHkdfsha256(
    hkdfSalt: hkdfSalt,
    gcmNonce: gcmNonce,
    payload: payload.concatenation(nonce: false),
  ));
}

/// This uses the `secret` to decrypt the `ciphertext`.
Future<List<int>> decrypt(
  List<int> secret,
  xmtp.Ciphertext ciphertext, {
  List<int> aad = const <int>[],
}) async {
  if (!ciphertext.hasAes256GcmHkdfSha256()) {
    throw StateError("unsupported ciphertext");
  }
  var p = ciphertext.aes256GcmHkdfSha256;
  final hkdf = Hkdf(
    hmac: Hmac(Sha256()),
    outputLength: 32,
  );
  final key = await hkdf.deriveKey(
    secretKey: SecretKey(secret),
    nonce: p.hkdfSalt,
  );
  var cipherText = p.payload.sublist(0, p.payload.length - 16);
  var mac = p.payload.sublist(p.payload.length - 16);
  return _aesGcm256.decrypt(
    SecretBox(
      cipherText,
      nonce: p.gcmNonce,
      mac: Mac(mac),
    ),
    secretKey: key,
    aad: aad,
  );
}

/// Compute the shared secret between `privateKey` and `publicKey`.
/// See also [createECPrivateKey], [createECPublicKey] for help constructing.
Uint8List computeDHSecret(ECPrivateKey privateKey, ECPublicKey publicKey) {
  // NOTE: ECPoint overloads the * operator to do point multiplication.
  var s = publicKey.Q! * privateKey.d;
  return s!.getEncoded(false);
}

/// This performs a variation of the X3DH protocol to establish a shared secret
/// between "me" and "peer".
/// NOTE: it varies based on whether "me" is the recipient (vs sender).
Uint8List compute3DHSecret(
  ECPrivateKey meId,
  ECPrivateKey mePre,
  ECPublicKey peerId,
  ECPublicKey peerPre,
  bool isRecipientMe,
) {
  var dh1 = computeDHSecret(meId, peerPre);
  var dh2 = computeDHSecret(mePre, peerId);
  var dh3 = computeDHSecret(mePre, peerPre);
  return isRecipientMe
      ? Uint8List.fromList(dh2 + dh1 + dh3)
      : Uint8List.fromList(dh1 + dh2 + dh3);
}

/// This creates an [ECPublicKey] from the raw secp256k1 public key `bytes`.
ECPublicKey createECPublicKey(List<int> bytes) {
  if (bytes.length == 64) {
    // Add the 0x04 byte prefix if it's missing.
    // The prefix indicates that it is uncompressed.
    bytes = [0x04] + bytes;
  }
  if (bytes.length != 65) {
    throw ArgumentError("invalid public key length (expected 65): $bytes");
  }
  return ECPublicKey(
    _params.curve.decodePoint(bytes),
    _params,
  );
}

/// This creates an [ECPrivateKey] from the raw secp256k1 private key `bytes`.
ECPrivateKey createECPrivateKey(List<int> bytes) => ECPrivateKey(
      bytesToUnsignedInt(Uint8List.fromList(bytes)),
      _params,
    );

final _rand = Random.secure();

/// This produces a list of `count` random bytes.
List<int> generateRandomBytes(int count) {
  return List.generate(count, (_) => _rand.nextInt(256));
}
