import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import './signature.dart';
import './crypto.dart';

/// This adds some helper methods to [Credentials] (i.e. a signer)
/// to allow it to create and enable XMTP identities.
extension AuthorizingEthPrivateKey on Credentials {
  /// This prompts the wallet to sign a personal message.
  /// It authorizes the `identity` key to act on behalf of this wallet.
  /// e.g. "XMTP : Create Identity ..."
  Future<AuthorizedIdentity> createIdentity(EthPrivateKey identity) async {
    // Prepare a slim edition of the `PublicKey`
    // that is serialized and included in the signed message.
    var slim = xmtp.PublicKey(
      timestamp: Int64(DateTime.now().millisecondsSinceEpoch),
      secp256k1Uncompressed: xmtp.PublicKey_Secp256k1Uncompressed(
        // NOTE: The 0x04 prefix indicates that it is uncompressed.
        bytes: [0x04] + identity.encodedPublicKey,
      ),
    );

    // Initiate a personal signature to "Create Identity".
    var sigText = SignatureText.createIdentity(slim.writeToBuffer());
    var sig = await _signPersonalMessageText(sigText);

    var address = await extractAddress();

    // Store the resulting `signature`.
    return AuthorizedIdentity(
      address.hexEip55,
      identity,
      xmtp.PublicKey(
        timestamp: slim.timestamp,
        secp256k1Uncompressed: slim.secp256k1Uncompressed,
        signature: xmtp.Signature(
          ecdsaCompact: xmtp.Signature_ECDSACompact(
            bytes: sig.sublist(0, 64),
            recovery: 1 - (sig[64] % 2),
          ),
        ),
      ),
    );
  }

  /// This prompts the wallet to sign a personal message.
  /// It authorizes the loading (decrypting) of previously saved keys.
  /// e.g. "XMTP : Enable Identity ..."
  ///
  /// This uses the signature as the secret to decrypt the keys.
  Future<xmtp.PrivateKeyBundle> enableIdentityLoading(
      xmtp.EncryptedPrivateKeyBundle encrypted) async {
    var signature = await _enableIdentity(encrypted.v1.walletPreKey);
    var message = await decrypt(signature, encrypted.v1.ciphertext);
    return xmtp.PrivateKeyBundle.fromBuffer(message);
  }

  /// This prompts the wallet to sign a personal message.
  /// It authorizes the saving (encrypting) of keys to be saved.
  /// e.g. "XMTP : Enable Identity ..."
  ///
  /// This uses the signature as the secret to encrypt the keys.
  Future<xmtp.EncryptedPrivateKeyBundle> enableIdentitySaving(
      xmtp.PrivateKeyBundle bundle) async {
    var walletPreKey = generateRandomBytes(32);
    var signature = await _enableIdentity(walletPreKey);
    var ciphertext = await encrypt(signature, bundle.writeToBuffer());
    return xmtp.EncryptedPrivateKeyBundle(
        v1: xmtp.EncryptedPrivateKeyBundleV1(
      walletPreKey: walletPreKey,
      ciphertext: ciphertext,
    ));
  }

  /// This is used by both the saving and loading of stored keys.
  Future<Uint8List> _enableIdentity(List<int> walletPreKey) async {
    // Initiate a personal signature to "Enable Identity".
    return _signPersonalMessageText(SignatureText.enableIdentity(walletPreKey));
  }

  Future<Uint8List> _signPersonalMessageText(String text) {
    return signPersonalMessage(Uint8List.fromList(utf8.encode(text)));
  }
}

/// This is an `identity` that is `authorized` to act on
/// behalf of the `walletAddr`.
///
/// This authorization is captured by the `authorized.signature`
/// which has been signed by the `walletAddr`.
class AuthorizedIdentity {
  final String walletAddr;
  final xmtp.PublicKey authorized; // .signature is signed by the wallet
  final EthPrivateKey identity;

  AuthorizedIdentity(this.walletAddr, this.identity, this.authorized);

  /// Creates an authorization token that bundles
  ///  - the authorized identity (signed by the wallet key) and
  ///  - a new `AuthData` (signed by the identity key).
  ///
  /// This is used for authentication with the API.
  ///  e.g. it is sent as the "authorization: Bearer $authToken".
  Future<String> createAuthToken() async {
    var authDataBytes = xmtp.AuthData(
            walletAddr: walletAddr,
            createdNs: Int64(DateTime.now().millisecondsSinceEpoch) * 1000000)
        .writeToBuffer();

    var sig = await identity.signToSignature(authDataBytes);
    var token = xmtp.Token(
      identityKey: authorized,
      authDataBytes: authDataBytes,
      authDataSignature: xmtp.Signature(
        ecdsaCompact: xmtp.Signature_ECDSACompact(
          bytes: _padTo32(unsignedIntToBytes(sig.r)) +
              _padTo32(unsignedIntToBytes(sig.s)),
          recovery: 1 - (sig.v % 2),
        ),
      ),
    );
    return base64.encode(token.writeToBuffer());
  }

  /// e.g. _padTo32([1, 2, 3]) -> [0, 0, ... , 0, 0, 1, 2, 3]
  ///                               .length == 32
  _padTo32(Uint8List l) => Uint8List(32)..setRange(32 - l.length, 32, l);

  xmtp.PrivateKeyBundle toBundle() {
    return xmtp.PrivateKeyBundle(
      v1: xmtp.PrivateKeyBundleV1(
          identityKey: xmtp.PrivateKey(
        publicKey: authorized,
        secp256k1: xmtp.PrivateKey_Secp256k1(
          bytes: identity.privateKey,
        ),
      )),
    );
  }
}
