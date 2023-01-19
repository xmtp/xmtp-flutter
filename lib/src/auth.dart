import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:quiver/check.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'common/crypto.dart';
import 'common/signature.dart';
import 'common/api.dart';
import 'common/time64.dart';
import 'common/topic.dart';

/// This manages the [keys] for a user.
/// It is responsible for initializing them from wallet [Credentials]
/// or from a previously saved [xmtp.PrivateKeyBundle] keys.
/// See [authenticateWithCredentials], [authenticateWithKeys].
///
/// It is also responsible for saving and loading them from the [Api].
class AuthManager {
  final EthereumAddress _address;
  final Api _api;
  late xmtp.PrivateKeyBundle keys;

  String authToken = "";
  DateTime authTokenExpiresAt = DateTime(0);
  final Duration maxAuthTokenAge;

  AuthManager(
    this._address,
    this._api, {
    // Note: true max is 1 hour. But we give ourselves some elbow room.
    this.maxAuthTokenAge = const Duration(minutes: 59),
  });

  /// This authenticates using [keys] acquired from network storage
  /// encrypted using the [wallet].
  ///
  /// e.g. this might be called the first time a user logs in from a new device.
  ///      The next time they launch the app they can [authenticateWithKeys].
  ///
  /// If there are stored keys then this asks the [wallet] to
  /// [enableIdentityLoading] so that we can decrypt the stored [keys].
  ///
  /// If there are no stored keys then this generates a new [identityKey]
  /// and asks the [wallet] to both [createIdentity] and [enableIdentitySaving]
  /// so we can then store it encrypted for the next time.
  Future<xmtp.PrivateKeyBundle> authenticateWithCredentials(
    Signer wallet,
  ) async {
    xmtp.PrivateKeyBundle keys;
    var storedKeys = await _lookupPrivateKeys();
    if (storedKeys.isNotEmpty) {
      keys = await wallet.enableIdentityLoading(storedKeys.first);
      _checkKeys(keys);
      this.keys = keys;
      _api.setAuthTokenProvider(getAuthToken);
      return keys;
    } else {
      var identity = generateKeyPair();
      keys = await wallet.createIdentity(identity);
      _checkKeys(keys);
      this.keys = keys;
      _api.setAuthTokenProvider(getAuthToken);
      var encryptedKeys = await wallet.enableIdentitySaving(keys);
      await _savePrivateKeys(encryptedKeys);
      return keys;
    }
  }

  /// This returns an authentication token for the current user.
  /// If a previous auth token does not exist, or if it has expired,
  /// then this will use the [keys] to create a new one.
  Future<String> getAuthToken() async {
    if (authToken.isEmpty || authTokenExpiresAt.isBefore(DateTime.now())) {
      authToken = await keys.createAuthToken();
      authTokenExpiresAt = DateTime.now().add(maxAuthTokenAge);
    }
    return authToken;
  }

  /// This authenticates with [keys] directly received.
  /// e.g. this might be called on subsequent app launches once we
  ///      have already stored the keys from a previous session.
  Future<xmtp.PrivateKeyBundle> authenticateWithKeys(
    xmtp.PrivateKeyBundle keys,
  ) async {
    _checkKeys(keys);
    this.keys = keys;
    _api.setAuthTokenProvider(getAuthToken);
    return keys;
  }

  /// This throws if the wallet signer of the keys does not match [address].
  void _checkKeys(xmtp.PrivateKeyBundle keys) => checkArgument(
        keys.wallet == _address,
        message: "authentication keys must match client address: "
            "${keys.wallet} <-> $_address",
      );

  Future<List<xmtp.EncryptedPrivateKeyBundle>> _lookupPrivateKeys() async {
    var stored = await _api.client.query(xmtp.QueryRequest(
      contentTopics: [Topic.userPrivateStoreKeyBundle(_address.hex)],
      pagingInfo: xmtp.PagingInfo(limit: 10),
    ));
    var result = <xmtp.EncryptedPrivateKeyBundle>[];
    for (var e in stored.envelopes) {
      try {
        result.add(xmtp.EncryptedPrivateKeyBundle.fromBuffer(e.message));
      } catch (e) {
        debugPrint("failed to decode stored keys: $e");
      }
    }
    return result;
  }

  Future<xmtp.PublishResponse> _savePrivateKeys(
    xmtp.EncryptedPrivateKeyBundle encrypted,
  ) async {
    return _api.client.publish(xmtp.PublishRequest(envelopes: [
      xmtp.Envelope(
        contentTopic: Topic.userPrivateStoreKeyBundle(_address.hex),
        timestampNs: nowNs(),
        message: encrypted.writeToBuffer(),
      ),
    ]));
  }
}

/// This adds some helper methods to [Credentials] (i.e. a signer)
/// to allow it to create and enable XMTP identities.
extension AuthCredentials on Signer {
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
    var unsigned = identity.toUnsignedPublicKey();
    var text = SignatureSubject.createIdentity(unsigned.writeToBuffer());
    var sig = await _signPersonalMessageText(text);
    var identityKey = xmtp.PrivateKey(
      secp256k1: xmtp.PrivateKey_Secp256k1(bytes: identity.privateKey),
      publicKey: unsigned
        ..signature = xmtp.Signature(
          walletEcdsaCompact: sig.toWalletEcdsaCompact(),
        ),
    );

    // Now we have the `identity` so we use it authorize a preKey.
    var pre = EthPrivateKey.createRandom(Random.secure());
    var unsignedPre = pre.toUnsignedPublicKey();
    var preDigest = await SignatureSubject.createPreKey(
      unsignedPre.writeToBuffer(),
    );
    var preSig = sign(preDigest, identity.privateKey);
    var preKey = xmtp.PrivateKey(
      secp256k1: xmtp.PrivateKey_Secp256k1(bytes: pre.privateKey),
      publicKey: unsignedPre
        ..signature = xmtp.Signature(
          ecdsaCompact: preSig.toEcdsaCompact(),
        ),
    );

    return xmtp.PrivateKeyBundle(
      v1: xmtp.PrivateKeyBundleV1(
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
    return _signPersonalMessageText(
        SignatureSubject.enableIdentity(walletPreKey));
  }

  Future<Uint8List> _signPersonalMessageText(String text) {
    return signPersonalMessage(text);
  }
}

/// This adds a helper to [EthPrivateKey] to
/// build the corresponding [xmtp.UnsignedPublicKey].
extension ToUnsignedPublicKey on EthPrivateKey {
  xmtp.PublicKey toUnsignedPublicKey() {
    return xmtp.PublicKey(
      timestamp: nowMs(),
      secp256k1Uncompressed: xmtp.PublicKey_Secp256k1Uncompressed(
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
/// TODO: roll this into a "PrivateKeyBundle" helper class
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

  /// Get the preKey with the specified `address`.
  /// Throws an error when it cannot be found.
  EthPrivateKey getPre(EthereumAddress address) {
    for (var preKey in preKeys) {
      if (preKey.address == address) {
        return preKey;
      }
    }
    throw StateError("unable to find preKey ${address.hexEip55}");
  }

  /// Create the v1 bundle for these keys.
  /// Note: v1 bundles sign their identity key with type .ecdsaCompact
  xmtp.PrivateKeyBundleV1 toV1() {
    if (whichVersion() == xmtp.PrivateKeyBundle_Version.v1) {
      return v1
        ..identityKey.publicKey.signature =
            v1.identityKey.publicKey.signature.toEcdsa();
    }
    var unsignedPublic =
        xmtp.UnsignedPublicKey.fromBuffer(v2.identityKey.publicKey.keyBytes);
    return xmtp.PrivateKeyBundleV1(
        identityKey: xmtp.PrivateKey(
            timestamp: v2.identityKey.createdNs.toMs(),
            secp256k1: xmtp.PrivateKey_Secp256k1(
              bytes: v2.identityKey.secp256k1.bytes,
            ),
            publicKey: xmtp.PublicKey(
              timestamp: unsignedPublic.createdNs,
              secp256k1Uncompressed: xmtp.PublicKey_Secp256k1Uncompressed(
                bytes: unsignedPublic.secp256k1Uncompressed.bytes,
              ),
              signature: v2.identityKey.publicKey.signature.toEcdsa(),
            )));
  }

  /// Create the v2 bundle for these keys.
  /// Note: v2 bundles sign their identity key with type .walletEcdsaCompact
  xmtp.PrivateKeyBundleV2 toV2() {
    if (whichVersion() == xmtp.PrivateKeyBundle_Version.v2) {
      return v2
        ..identityKey.publicKey.signature =
            v1.identityKey.publicKey.signature.toWalletEcdsa();
    }
    return xmtp.PrivateKeyBundleV2(
        identityKey: xmtp.SignedPrivateKey(
      createdNs: v1.identityKey.timestamp.toNs(),
      secp256k1: xmtp.SignedPrivateKey_Secp256k1(
        bytes: v1.identityKey.secp256k1.bytes,
      ),
      publicKey: xmtp.SignedPublicKey(
        keyBytes: xmtp.PublicKey(
          timestamp: v1.identityKey.publicKey.timestamp,
          secp256k1Uncompressed: v1.identityKey.publicKey.secp256k1Uncompressed,
          // NOTE: the keyBytes that was signed does not include the .signature
        ).writeToBuffer(),
        signature: v1.identityKey.publicKey.signature.toWalletEcdsa(),
      ),
    ));
  }
}

/// This enhances the [xmtp.PrivateKeyBundle] so it can produce
/// auth tokens for use with the API.
///
/// TODO: roll this into a "PrivateKeyBundle" helper class
extension AuthPrivateKeyBundle on xmtp.PrivateKeyBundle {
  /// Creates an authorization token that bundles
  ///  - the authorized identity (signed by the wallet key) and
  ///  - a new `AuthData` (signed by the identity key).
  ///
  /// This is used for authentication with the API.
  ///  e.g. it is sent as the "authorization: Bearer $authToken".
  ///
  /// Auth Token Signature Notes:
  ///
  /// The backend and xmtp-js disagree on how to sign an `.identityKey`:
  ///  - the backend expects an `.ecdsaCompact` signature
  ///  - the `xmtp-js` library expects a `.walletEcdsaCompact` signature
  /// So we create this authToken (for the backend) signed `.ecdsaCompact`.
  /// And we sign contact bundles (for xmtp-js etc) with `.walletEcdsaCompact`.
  ///  See `createContactBundleV*()` in `contact.dart`.
  ///
  /// NOTE: this can only be called on v1 bundles.
  /// TODO: consider supporting V2 key bundles
  Future<String> createAuthToken() async {
    if (whichVersion() != xmtp.PrivateKeyBundle_Version.v1) {
      throw UnsupportedError("only supported on xmtp.PrivateKeyBundle v1");
    }

    var walletAddr = v1.identityKey.publicKey
        .recoverWalletSignerPublicKey()
        .toEthereumAddress()
        .hexEip55;
    var authData = xmtp.AuthData(walletAddr: walletAddr, createdNs: nowNs());
    var authDataBytes = authData.writeToBuffer();

    var identityPrivateKey =
        bytesToUnsignedInt(Uint8List.fromList(v1.identityKey.secp256k1.bytes));
    var identity = EthPrivateKey.fromInt(identityPrivateKey);
    var sig = await identity.signToSignature(authDataBytes);

    var token = xmtp.Token(
      // The backend expects a signature of type ECDSA not WalletECDSA.
      identityKey: xmtp.PublicKey()
        ..mergeFromMessage(v1.identityKey.publicKey)
        ..signature = v1.identityKey.publicKey.signature.toEcdsa(),
      authDataBytes: authDataBytes,
      authDataSignature: xmtp.Signature(
        ecdsaCompact: sig.toEcdsaCompact(),
      ),
    );
    return base64.encode(token.writeToBuffer());
  }
}

final _rand = Random.secure();
EthPrivateKey generateKeyPair() => EthPrivateKey.createRandom(_rand);
