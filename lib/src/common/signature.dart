import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web3dart/credentials.dart';
import 'package:web3dart/crypto.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

/// This contains the XMTP signature texts and related utilities.

/// These are the texts that users are prompted to sign.
///
/// These must be kept in sync across the network.
/// See e.g. xmtp/xmtp-node-go/pkg/api/authentication.go#createIdentitySignRequest
///          xmtp-js/src/crypto/Signature.WalletSigner#identitySigRequestText
class SignatureText {
  /// This is the text that users sign when they want to create
  /// an identity key associated with their wallet.
  ///
  /// The `key` bytes contains an unsigned [xmtp.PublicKey] of the
  /// identity key to be created.
  ///
  /// The resulting signature is then published to prove that the
  /// identity key is authorized on behalf of the wallet.
  ///
  /// See [AuthorizingEthPrivateKey.createIdentity]
  static String createIdentity(List<int> key) =>
      "XMTP : Create Identity\n${_bytesToHex(key)}\n\nFor more info: https://xmtp.org/signatures/";

  /// This is the text that users sign when they want to save (encrypt)
  /// or to load (decrypt) keys using the network private storage.
  ///
  /// The `key` bytes contains the `walletPreKey` of the encrypted bundle.
  ///
  /// The resulting signature is the shared secret used to encrypt and
  /// decrypt the saved keys.
  ///
  /// See [AuthorizingEthPrivateKey.enableIdentitySaving]
  /// See [AuthorizingEthPrivateKey.enableIdentityLoading]
  static String enableIdentity(List<int> key) =>
      "XMTP : Enable Identity\n${_bytesToHex(key)}\n\nFor more info: https://xmtp.org/signatures/";

  static _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join("");
}

/// This adds a converter to [MsgSignature]
/// from an [xmtp.Signature].
extension ToMsgSignature on xmtp.Signature {
  MsgSignature toMsgSignature() {
    var bytes = whichUnion() == xmtp.Signature_Union.walletEcdsaCompact
        ? walletEcdsaCompact.bytes
        : ecdsaCompact.bytes;
    if (bytes.length != 64) {
      throw StateError('bad wallet signature length (${bytes.length})');
    }
    var r = bytesToUnsignedInt(Uint8List.fromList(bytes.sublist(0, 32)));
    var s = bytesToUnsignedInt(Uint8List.fromList(bytes.sublist(32, 64)));
    var recovery = whichUnion() == xmtp.Signature_Union.walletEcdsaCompact
        ? walletEcdsaCompact.recovery
        : ecdsaCompact.recovery;
    var v = recovery + 27;
    return MsgSignature(r, s, v);
  }
}

/// This adds a method to [xmtp.PublicKey] to help
/// recover the wallet that signed it.
extension RecoverWalletPublicKey on xmtp.PublicKey {
  List<int> recoverWalletSignerPublicKey() {
    var keyBytes = xmtp.PublicKey(
      timestamp: timestamp,
      secp256k1Uncompressed: secp256k1Uncompressed,
    ).writeToBuffer();
    return _recoverWalletSignerPublicKey(keyBytes, signature);
  }
}

/// This adds a method to [xmtp.SignedPublicKey] to help
/// recover the wallet that signed it.
extension RecoverWalletSignedPublicKey on xmtp.SignedPublicKey {
  List<int> recoverWalletSignerPublicKey() {
    return _recoverWalletSignerPublicKey(keyBytes, signature);
  }
}

List<int> _recoverWalletSignerPublicKey(
  List<int> keyBytes,
  xmtp.Signature signature,
) {
  // This recreates the signed text which
  // (together with the signature) lets us
  // recover the public key of the signer.
  var text = SignatureText.createIdentity(keyBytes);
  var hash = ethereumHash(text);
  return ecRecover(hash, signature.toMsgSignature());
}

/// This adds a helper to construct [xmtp.Signature]
/// from the list of raw bytes from an eth_sign signature.
extension ListToEcdsaCompact on List<int> {
  toEcdsaCompact() {
    return xmtp.Signature_ECDSACompact(
      bytes: sublist(0, 64),
      recovery: 1 - (this[64] % 2),
    );
  }
}

/// This adds a helper to construct the
/// [xmtp.Signature_ECDSACompact] from a [MsgSignature].
extension MsgSignatureToEcdsaCompat on MsgSignature {
  toEcdsaCompact() {
    return xmtp.Signature_ECDSACompact(
      bytes: _padTo32(unsignedIntToBytes(r)) + _padTo32(unsignedIntToBytes(s)),
      recovery: 1 - (v % 2),
    );
  }

  /// e.g. _padTo32([1, 2, 3]) -> [0, 0, ... , 0, 0, 1, 2, 3]
  ///                               .length == 32
  _padTo32(Uint8List l) => Uint8List(32)..setRange(32 - l.length, 32, l);
}

/// This produces the ethereum hash of the `text`.
/// NOTE: this is performed automatically by `Credentials.signPersonalMessage`
///
/// TODO: consider moving this extension elsewhere w/ other eth utils.
Uint8List ethereumHash(String text) {
  var payload = utf8.encode(text);
  var prefix = utf8.encode('\u0019Ethereum Signed Message:\n');
  var count = utf8.encode(payload.length.toString());
  return keccak256(Uint8List.fromList(prefix + count + payload));
}

/// This adds helpers on [xmtp.PublicKeyBundle] to clean up header parsing.
extension PKBundleToEthAddresses on xmtp.PublicKeyBundle {
  EthereumAddress get wallet =>
      identityKey.recoverWalletSignerPublicKey().toEthereumAddress();

  EthereumAddress get identity =>
      identityKey.secp256k1Uncompressed.bytes.toEthereumAddress();

  EthereumAddress get pre =>
      preKey.secp256k1Uncompressed.bytes.toEthereumAddress();
}

/// This adds helpers on [xmtp.SignedPublicKeyBundle] to clean up header parsing.
extension SPKBundleToEthAddresses on xmtp.SignedPublicKeyBundle {
  EthereumAddress get wallet =>
      identityKey.recoverWalletSignerPublicKey().toEthereumAddress();

  EthereumAddress get identity =>
      identityKey.publicKeyBytes.toEthereumAddress();

  EthereumAddress get pre => preKey.publicKeyBytes.toEthereumAddress();
}

/// This adds helper to grab the public key bytes from an [xmtp.SignedPublicKey]
extension ToPublicKeyBytes on xmtp.SignedPublicKey {
  List<int> get publicKeyBytes =>
      xmtp.UnsignedPublicKey.fromBuffer(keyBytes).secp256k1Uncompressed.bytes;
}

/// This adds a helper to [List<int>] to simplify
/// conversion to [EthereumAddress].
extension EthAddressBytes on List<int> {
  EthereumAddress toEthereumAddress() {
    var publicKey = Uint8List.fromList(this);
    if (publicKey.length == 65 && publicKey[0] == 0x04) {
      // Skip the uncompressed indicator prefix.
      publicKey = publicKey.sublist(1);
    }
    if (publicKey.length != 64) {
      throw StateError("bad public key $publicKey");
    }
    return EthereumAddress.fromPublicKey(publicKey);
  }
}
