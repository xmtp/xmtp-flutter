import 'package:flutter/foundation.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import './signature.dart';

/// This adds a helper to [xmtp.Envelope] to help when
/// decoding [xmtp.ContactBundle]s from the "contact-{address}" topic.
extension DecodeContactEnvelope on xmtp.Envelope {
  xmtp.ContactBundle toContactBundle() {
    var bundle = xmtp.ContactBundle.fromBuffer(message);
    // HACK: This detects a bad "ContactBundle" and attempts to reparse
    //       it as a "PublicKeyBundle".
    //
    //       This happens because the "contact-{address}" topic contains
    //       `PublicKeyBundles` when it should only contain `ContactBundles`.
    //
    //       In this scenario, the parser just tucks the unknown fields
    //       aside and yields a mostly empty message. So we do some sanity
    //       checks on the contact to decide if we should try reparsing.
    // TODO: consider cleaning up the topic so we can drop this hack.
    if (!_isMaybeValid(bundle)) {
      bundle = xmtp.ContactBundle(
        v1: xmtp.ContactBundleV1(
          keyBundle: xmtp.PublicKeyBundle.fromBuffer(message),
        ),
      );
    }
    return bundle;
  }

  /// This is a heuristic for whether the bundle is valid.
  /// This lets us know when to try reparsing.
  bool _isMaybeValid(xmtp.ContactBundle bundle) {
    if (bundle.whichVersion() == xmtp.ContactBundle_Version.v1) {
      return bundle
          .v1.keyBundle.identityKey.secp256k1Uncompressed.bytes.isNotEmpty;
    }
    if (bundle.whichVersion() == xmtp.ContactBundle_Version.v2) {
      return bundle.v2.keyBundle.identityKey.keyBytes.isNotEmpty;
    }
    return false; // i.e. when version == xmtp.ContactBundle_Version.notSet
  }
}

/// This enhances [xmtp.ContactBundle] to simplify
/// access to the "wallet", "identity" and "pre".
///
/// This extension handles the compatibility logic required
/// to support both V1 and V2 of [xmtp.ContactBundle].
extension CompatContactBundle on xmtp.ContactBundle {
  /// This returns the wallet that authorized this identity.
  EthereumAddress get wallet {
    // We recover the wallet public key from the signature on the identity key.
    if (whichVersion() == xmtp.ContactBundle_Version.v1) {
      return v1.keyBundle.identityKey
          .recoverWalletSignerPublicKey()
          .toEthereumAddress();
    } else {
      return v2.keyBundle.identityKey
          .recoverWalletSignerPublicKey()
          .toEthereumAddress();
    }
  }

  /// This returns the identity.
  EthereumAddress get identity {
    if (whichVersion() == xmtp.ContactBundle_Version.v1) {
      var identityPublicKey = v1.keyBundle.identityKey;
      return identityPublicKey.secp256k1Uncompressed.bytes.toEthereumAddress();
    } else {
      var identityPublicKey =
          xmtp.UnsignedPublicKey.fromBuffer(v2.keyBundle.identityKey.keyBytes);
      return identityPublicKey.secp256k1Uncompressed.bytes.toEthereumAddress();
    }
  }

  /// This returns whether there is a pre key in this contact bundle.
  bool get hasPre => _toPrePublicKey().isNotEmpty;

  /// This returns the pre key in this bundle.
  /// NOTE: this throws an exception if it does not exist.
  /// See [hasPre].
  EthereumAddress get pre => _toPrePublicKey().toEthereumAddress();

  List<int> _toPrePublicKey() {
    if (whichVersion() == xmtp.ContactBundle_Version.v1) {
      return v1.keyBundle.preKey.secp256k1Uncompressed.bytes;
    }
    var prePublicKey =
        xmtp.UnsignedPublicKey.fromBuffer(v2.keyBundle.preKey.keyBytes);
    return prePublicKey.secp256k1Uncompressed.bytes;
  }
}

xmtp.PublicKey _toPublicKey(xmtp.SignedPublicKey v2) =>
    // This works because v1 `PublicKey` ~= v2 `UnsignedPublicKey`
    xmtp.PublicKey.fromBuffer(v2.keyBytes)..signature = v2.signature;

xmtp.SignedPublicKey _toSignedPublicKey(xmtp.PublicKey v1) =>
    xmtp.SignedPublicKey(
      signature: v1.signature,
      // This works because v1 `PublicKey` ~= v2 `UnsignedPublicKey`
      keyBytes: xmtp.PublicKey(
        timestamp: v1.timestamp,
        secp256k1Uncompressed: v1.secp256k1Uncompressed,
        // NOTE: the keyBytes that was signed does not include the .signature
      ).writeToBuffer(),
    );

/// This creates a [v1] [xmtp.ContactBundle] from a [xmtp.PrivateKeyBundle].
xmtp.ContactBundle createContactBundleV1(xmtp.PrivateKeyBundle keys) {
  var isAlreadyV1 = keys.whichVersion() == xmtp.PrivateKeyBundle_Version.v1;
  return xmtp.ContactBundle(
    v1: xmtp.ContactBundleV1(
      keyBundle: xmtp.PublicKeyBundle(
        identityKey: isAlreadyV1
            ? keys.v1.identityKey.publicKey
            : _toPublicKey(keys.v2.identityKey.publicKey),
        preKey: isAlreadyV1
            ? keys.v1.preKeys.first.publicKey
            : _toPublicKey(keys.v2.preKeys.first.publicKey),
      ),
    ),
  );
}

/// This creates a [v2] [xmtp.ContactBundle] from a [xmtp.PrivateKeyBundle].
xmtp.ContactBundle createContactBundleV2(xmtp.PrivateKeyBundle keys) {
  var isAlreadyV2 = keys.whichVersion() == xmtp.PrivateKeyBundle_Version.v2;
  return xmtp.ContactBundle(
    v2: xmtp.ContactBundleV2(
      keyBundle: xmtp.SignedPublicKeyBundle(
        identityKey: isAlreadyV2
          ? keys.v2.identityKey.publicKey
          : _toSignedPublicKey(keys.v1.identityKey.publicKey),
        preKey: isAlreadyV2
          ? keys.v2.preKeys.first.publicKey
          : _toSignedPublicKey(keys.v1.preKeys.first.publicKey),
      ),
    ),
  );
}

/// This adds a helper to [List<int>] to simplify
/// conversion to [EthereumAddress].
///
/// TODO: consider moving this extension elsewhere w/ other eth utils.
extension EthAddressBytes on List<int> {
  EthereumAddress toEthereumAddress() {
    var publicKey = Uint8List.fromList(this);
    if (publicKey.length == 65 && publicKey[0] == 0x04) {
      // Skip the uncompressed indicator prefix.
      publicKey = publicKey.sublist(1);
    }
    if (publicKey.length != 64) {
      throw "bad public key $publicKey";
    }
    return EthereumAddress.fromPublicKey(publicKey);
  }
}
