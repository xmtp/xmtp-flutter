import 'dart:convert';
import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import './contact.dart';
import './crypto.dart';
import './signature.dart';

/// This adds some helper methods to [Credentials] (i.e. a signer)
/// to allow it to create and enable XMTP identities.
extension AuthCredentials on Credentials {
  /// This prompts the wallet to sign a personal message.
  /// It authorizes the `identity` key to act on behalf of this wallet.
  ///   e.g. "XMTP : Create Identity ..."
  /// It returns a bundle of the `identity` key signed by the wallet,
  /// together with a `preKey` signed by the `identity` key.
  Future<xmtp.PrivateKeyBundle> createIdentity(EthPrivateKey identity) async {
    // This method gathers the
    //  - `identityKey` containing `identity` signed by this wallet and
    //  - `preKey` containing a new `pre` signed by `identity`

    // First we need to get this wallet to authorize `identity`.
    // So we initiate a personal signature to "Create Identity".
    // This prompt includes an `UnsignedPublicKey` of `identity`
    // that is serialized and included in the signed message text.
    var unsignedIdentityBytes = identity.toUnsignedPublicKey().writeToBuffer();
    var text = SignatureText.createIdentity(unsignedIdentityBytes);
    var sig = await _signPersonalMessageText(text);
    var identityKey = xmtp.SignedPrivateKey(
        secp256k1: xmtp.SignedPrivateKey_Secp256k1(bytes: identity.privateKey),
        publicKey: xmtp.SignedPublicKey(
          keyBytes: unsignedIdentityBytes,
          signature: xmtp.Signature(
            ecdsaCompact: sig.toEcdsaCompact(),
          ),
        ));

    // Now we have the `identity` so we use it authorize a preKey.
    var pre = EthPrivateKey.createRandom(Random.secure());
    var unsignedPreBytes = pre.toUnsignedPublicKey().writeToBuffer();
    var preSig = await pre.signToSignature(unsignedPreBytes);
    var preKey = xmtp.SignedPrivateKey(
      secp256k1: xmtp.SignedPrivateKey_Secp256k1(bytes: pre.privateKey),
      publicKey: xmtp.SignedPublicKey(
        keyBytes: unsignedPreBytes,
        signature: xmtp.Signature(
          ecdsaCompact: preSig.toEcdsaCompact(),
        ),
      ),
    );

    return xmtp.PrivateKeyBundle(
      v2: xmtp.PrivateKeyBundleV2(
        identityKey: identityKey,
        preKeys: [preKey],
      ),
    );
  }

  /// This prompts the wallet to sign a personal message.
  /// It authorizes the loading (decrypting) of previously saved keys.
  ///   e.g. "XMTP : Enable Identity ..."
  /// This uses the signature as the secret to decrypt the keys.
  Future<xmtp.PrivateKeyBundle> enableIdentityLoading(
      xmtp.EncryptedPrivateKeyBundle encrypted) async {
    var signature = await _enableIdentity(encrypted.v1.walletPreKey);
    var message = await decrypt(signature, encrypted.v1.ciphertext);
    return xmtp.PrivateKeyBundle.fromBuffer(message);
  }

  /// This prompts the wallet to sign a personal message.
  /// It authorizes the saving (encrypting) of keys to be saved.
  ///   e.g. "XMTP : Enable Identity ..."
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

/// This adds a helper to [EthPrivateKey] to
/// build the corresponding [xmtp.UnsignedPublicKey].
extension ToUnsignedPublicKey on EthPrivateKey {
  xmtp.UnsignedPublicKey toUnsignedPublicKey() {
    return xmtp.UnsignedPublicKey(
      createdNs: _nowNs(),
      secp256k1Uncompressed: xmtp.UnsignedPublicKey_Secp256k1Uncompressed(
        // NOTE: The 0x04 prefix indicates that it is uncompressed.
        bytes: [0x04] + encodedPublicKey,
      ),
    );
  }
}

/// This enhances the [xmtp.PrivateKeyBundle] to simplify
/// access to the "wallet", "identity" and "preKeys".
///
/// This extension handles the compatibility logic required
/// to support both V1 and V2 of PrivateKeyBundle.
///
extension CompatPrivateKeyBundle on xmtp.PrivateKeyBundle {
  /// This returns the wallet that authorized this "identity"
  EthereumAddress get wallet {
    // We recover the wallet public key from the signature on the identity key.
    if (whichVersion() == xmtp.PrivateKeyBundle_Version.v1) {
      return v1.identityKey.publicKey
          .recoverWalletSignerPublicKey()
          .toEthereumAddress();
    } else {
      return v2.identityKey.publicKey
          .recoverWalletSignerPublicKey()
          .toEthereumAddress();
    }
  }

  /// This returns the identity key for the bundle.
  EthPrivateKey get identity {
    List<int> bytes;
    if (whichVersion() == xmtp.PrivateKeyBundle_Version.v1) {
      bytes = v1.identityKey.secp256k1.bytes;
    } else {
      bytes = v2.identityKey.secp256k1.bytes;
    }
    var ethPrivateInt = bytesToUnsignedInt(Uint8List.fromList(bytes));
    return EthPrivateKey.fromInt(ethPrivateInt);
  }

  /// This yields all authorized preKeys in the bundle.
  List<EthPrivateKey> get preKeys {
    if (whichVersion() == xmtp.PrivateKeyBundle_Version.v1) {
      return v1.preKeys
          .map((k) => bytesToUnsignedInt(Uint8List.fromList(k.secp256k1.bytes)))
          .map((ethPrivateInt) => EthPrivateKey.fromInt(ethPrivateInt))
          .toList();
    } else {
      return v2.preKeys
          .map((k) => bytesToUnsignedInt(Uint8List.fromList(k.secp256k1.bytes)))
          .map((ethPrivateInt) => EthPrivateKey.fromInt(ethPrivateInt))
          .toList();
    }
  }
}

/// This enhances the [xmtp.PrivateKeyBundle] so it can produce
/// auth tokens for use with the API.
extension AuthPrivateKeyBundle on xmtp.PrivateKeyBundle {
  /// Creates an authorization token that bundles
  ///  - the authorized identity (signed by the wallet key) and
  ///  - a new `AuthData` (signed by the identity key).
  ///
  /// This is used for authentication with the API.
  ///  e.g. it is sent as the "authorization: Bearer $authToken".
  ///
  /// NOTE: this can only be called on v2 bundles.
  /// TODO: consider supporting V1 key bundles
  /// TODO: consider adding a converter ".toV2()" for V1 instances
  /// TODO: more compatibility testing
  Future<String> createAuthToken() async {
    if (whichVersion() != xmtp.PrivateKeyBundle_Version.v2) {
      throw "only supported on xmtp.PrivateKeyBundle v2";
    }

    var walletAddr = v2.identityKey.publicKey
        .recoverWalletSignerPublicKey()
        .toEthereumAddress()
        .hexEip55;
    var authData = xmtp.AuthData(walletAddr: walletAddr, createdNs: _nowNs());
    var authDataBytes = authData.writeToBuffer();

    var identityPrivateKey =
        bytesToUnsignedInt(Uint8List.fromList(v2.identityKey.secp256k1.bytes));
    var identity = EthPrivateKey.fromInt(identityPrivateKey);
    var sig = await identity.signToSignature(authDataBytes);

    var identityPublicKey =
        xmtp.UnsignedPublicKey.fromBuffer(v2.identityKey.publicKey.keyBytes);
    var token = xmtp.Token(
      identityKey: xmtp.PublicKey(
        timestamp: identityPublicKey.createdNs,
        secp256k1Uncompressed: xmtp.PublicKey_Secp256k1Uncompressed(
          bytes: identityPublicKey.secp256k1Uncompressed.bytes,
        ),
        signature: v2.identityKey.publicKey.signature,
      ),
      authDataBytes: authDataBytes,
      authDataSignature: xmtp.Signature(
        ecdsaCompact: sig.toEcdsaCompact(),
      ),
    );
    return base64.encode(token.writeToBuffer());
  }
}

Int64 _nowNs() => Int64(DateTime.now().millisecondsSinceEpoch) * 1000000;
