import 'dart:async';

import 'package:quiver/collection.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'auth.dart';
import 'common/api.dart';
import 'common/signature.dart';
import 'common/time64.dart';
import 'common/topic.dart';

/// This manages the contacts for the user's session.
///
/// It is responsible for loading contacts from the server.
/// See [getUserContacts].
///
/// And it is responsible for saving the user's contact to the server.
/// See [saveContact].
class ContactManager {
  final Api _api;
  final Multimap<String, xmtp.ContactBundle> _contacts;

  ContactManager(this._api) : _contacts = Multimap();

  Future<List<xmtp.ContactBundle>> getUserContacts(
    String walletAddress,
  ) async {
    walletAddress = EthereumAddress.fromHex(walletAddress).hexEip55;
    var cached = _contacts[walletAddress].toList();
    if (cached.isNotEmpty) {
      return cached;
    }
    var stored = await _api.client.query(xmtp.QueryRequest(
      contentTopics: [Topic.userContact(walletAddress)],
      pagingInfo: xmtp.PagingInfo(limit: 5),
    ));
    var results = stored.envelopes.map((e) => e.toContactBundle()).where(
          // Ignore invalid results for the wrong address.
          (result) => result.wallet.hexEip55 == walletAddress,
        );
    _contacts.removeAll(walletAddress);
    _contacts.addValues(walletAddress, results);
    return results.toList();
  }

  Future<bool> hasUserContacts(String walletAddress) async {
    var results = await getUserContacts(walletAddress);
    return results.isNotEmpty;
  }

  Future<xmtp.ContactBundle> getUserContactV1(String walletAddress) async {
    var peerContacts = await getUserContacts(walletAddress);
    return peerContacts.firstWhere((c) => c.hasV1());
  }

  Future<xmtp.ContactBundle> getUserContactV2(String walletAddress) async {
    var peerContacts = await getUserContacts(walletAddress);
    return peerContacts.firstWhere((c) => c.hasV2());
  }

  Future<xmtp.PublishResponse> saveContact(
    xmtp.PrivateKeyBundle keys, {
    bool includeV1 = true,
    bool includeV2 = true,
  }) async {
    List<xmtp.ContactBundle> bundles = [];
    if (includeV1) {
      bundles.add(createContactBundleV1(keys));
    }
    if (includeV2) {
      bundles.add(createContactBundleV2(keys));
    }
    var address = keys.wallet;
    _contacts.removeAll(address.hexEip55);
    _contacts.addValues(address.hexEip55, bundles);
    return _api.client.publish(xmtp.PublishRequest(
      envelopes: bundles.map(
        (bundle) => xmtp.Envelope(
          contentTopic: Topic.userContact(address.hexEip55),
          timestampNs: nowNs(),
          message: bundle.writeToBuffer(),
        ),
      ),
    ));
  }

  /// This ensures that the [keys] public contact is published to the server.
  Future<bool> ensureSavedContact(
    xmtp.PrivateKeyBundle keys,
  ) async {
    var address = keys.wallet.hex;
    var myContacts = await getUserContacts(address);
    if (myContacts.isNotEmpty) {
      return false;
    }
    await saveContact(keys);
    return true;
  }
}

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

xmtp.PublicKey _toPublicKey(
  xmtp.SignedPublicKey v2, {
  required bool isSignedByWallet,
}) =>
    // This works because v1 `PublicKey` ~= v2 `UnsignedPublicKey`
    xmtp.PublicKey.fromBuffer(v2.keyBytes)
      ..signature = isSignedByWallet
          ? v2.signature.toWalletEcdsa()
          : v2.signature.toEcdsa();

xmtp.SignedPublicKey _toSignedPublicKey(
  xmtp.PublicKey v1, {
  required bool isSignedByWallet,
}) =>
    xmtp.SignedPublicKey(
      signature: isSignedByWallet
          ? v1.signature.toWalletEcdsa()
          : v1.signature.toEcdsa(),
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

  var identityKey = isAlreadyV1
      ? keys.v1.identityKey.publicKey
      : _toPublicKey(keys.v2.identityKey.publicKey, isSignedByWallet: true);
  return xmtp.ContactBundle(
    v1: xmtp.ContactBundleV1(
      keyBundle: xmtp.PublicKeyBundle(
        identityKey: xmtp.PublicKey()
          ..mergeFromMessage(identityKey)
          ..signature = identityKey.signature.toEcdsa(),
        preKey: isAlreadyV1
            ? keys.v1.preKeys.first.publicKey
            : _toPublicKey(
                keys.v2.preKeys.first.publicKey,
                isSignedByWallet: false,
              )
      ),
    ),
  );
}

/// This creates a [v2] [xmtp.ContactBundle] from a [xmtp.PrivateKeyBundle].
///
/// Contact Bundle Signature Notes:
///
/// The backend and xmtp-js disagree on how to sign an `.identityKey`:
///  - the `xmtp-js` library expects a `.walletEcdsaCompact` signature
///  - the backend expects an `.ecdsaCompact` signature
/// So we sign these contact bundles (for xmtp-js etc) with `.walletEcdsaCompact`.
/// And we create authTokens (for the backend) signed `.ecdsaCompact`.
///  See `createAuthToken()` in `auth.dart`.
xmtp.ContactBundle createContactBundleV2(xmtp.PrivateKeyBundle keys) {
  var isAlreadyV2 = keys.whichVersion() == xmtp.PrivateKeyBundle_Version.v2;
  return xmtp.ContactBundle(
    v2: xmtp.ContactBundleV2(
      keyBundle: xmtp.SignedPublicKeyBundle(
        identityKey: isAlreadyV2
            ? keys.v2.identityKey.publicKey
            : _toSignedPublicKey(
                keys.v1.identityKey.publicKey,
                isSignedByWallet: true,
              ),
        preKey: isAlreadyV2
            ? keys.v2.preKeys.first.publicKey
            : _toSignedPublicKey(
                keys.v1.preKeys.first.publicKey,
                isSignedByWallet: false,
              ),
      ),
    ),
  );
}
