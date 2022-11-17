import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

final _aesGcm256 = AesGcm.with256bits(nonceLength: 12);

/// This uses the `secret` to encrypt the `message`.
Future<xmtp.Ciphertext> encrypt(List<int> secret, List<int> message) async {
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
  xmtp.Ciphertext ciphertext,
) async {
  if (!ciphertext.hasAes256GcmHkdfSha256()) {
    throw UnsupportedError("unsupported ciphertext");
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
  );
}

final _rand = Random.secure();

/// This produces a list of `count` random bytes.
List<int> generateRandomBytes(int count) {
  return List.generate(count, (_) => _rand.nextInt(256));
}
