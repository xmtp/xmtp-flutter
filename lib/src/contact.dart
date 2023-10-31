import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:quiver/check.dart';
import 'package:quiver/collection.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp_bindings_flutter/xmtp_bindings_flutter.dart';
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
  final AuthManager _auth;
  final Multimap<String, xmtp.ContactBundle> _contacts;
  final Map<String, ContactConsent> _consentByAddress;
  DateTime? _lastRefreshedConsentsAt;

  ContactManager(this._api, this._auth)
      : _contacts = Multimap(),
        _consentByAddress = {},
        _lastRefreshedConsentsAt = null;

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

  ContactConsent checkConsent(EthereumAddress address) =>
      _consentByAddress[address.hexEip55] ?? ContactConsent.unknown;

  importConsents({
    Iterable<String> allowedWalletAddresses = const [],
    Iterable<String> deniedWalletAddresses = const [],
    DateTime? lastRefreshedAt,
  }) {
    _consentByAddress.clear();
    _consentByAddress.addEntries(allowedWalletAddresses
        .map(_normalizeAddress)
        .map((address) => MapEntry(address, ContactConsent.allow)));
    _consentByAddress.addEntries(deniedWalletAddresses
        .map(_normalizeAddress)
        .map((address) => MapEntry(address, ContactConsent.deny)));
    _lastRefreshedConsentsAt = lastRefreshedAt;
  }

  CompactConsents exportConsents() => CompactConsents(
        xmtp.PrivatePreferencesAction_Allow(
          walletAddresses: _consentByAddress.entries
              .where((e) => e.value == ContactConsent.allow)
              .map((e) => e.key)
              .toList(),
        ),
        xmtp.PrivatePreferencesAction_Block(
          walletAddresses: _consentByAddress.entries
              .where((e) => e.value == ContactConsent.deny)
              .map((e) => e.key)
              .toList(),
        ),
        _lastRefreshedConsentsAt,
      );

  Future<bool> refreshConsents(xmtp.PrivateKeyBundle keys,
      {bool fullRefresh = false}) async {
    var startTimeNs = _lastRefreshedConsentsAt?.toNs64();
    if (fullRefresh) {
      startTimeNs = null;
    }
    var topic = await Topic.userPreferences(keys.identity.privateKey);
    var listing = _api.client.envelopes(xmtp.QueryRequest(
      contentTopics: [topic],
      startTimeNs: startTimeNs,
      pagingInfo: xmtp.PagingInfo(
        limit: 100,
        direction: xmtp.SortDirection.SORT_DIRECTION_ASCENDING,
      ),
    ));
    var actions = await listing
        .asyncMap((e) => _actionFromMessage(keys, e.message))
        // discard any invalid or irrelevant actions
        .where((a) => a != null)
        .map((a) => a!)
        .where((a) => a.hasBlock() || a.hasAllow())
        .map((a) {
          var addresses =
              a.hasBlock() ? a.block.walletAddresses : a.allow.walletAddresses;
          var consent =
              a.hasBlock() ? ContactConsent.deny : ContactConsent.allow;
          return addresses
              .map((address) => MapEntry(_normalizeAddress(address), consent));
        })
        .expand((e) => e)
        .toList();
    _consentByAddress.addEntries(actions);
    _lastRefreshedConsentsAt = DateTime.now();
    return true;
  }

  Future<xmtp.PrivatePreferencesAction?> _actionFromMessage(
    xmtp.PrivateKeyBundle keys,
    List<int> payload,
  ) async {
    try {
      var decrypted = await libxmtp.userPreferencesDecrypt(
        publicKey: keys.identity.publicKey.getEncoded(false),
        privateKey: keys.identity.privateKey,
        encryptedMessage: Uint8List.fromList(payload),
      );
      return xmtp.PrivatePreferencesAction.fromBuffer(decrypted);
    } catch (err) {
      debugPrint('discarding bad user preference action: $err');
      return null;
    }
  }

  Future<bool> deny(
    xmtp.PrivateKeyBundle keys,
    EthereumAddress ethereumAddress,
  ) async {
    _consentByAddress[ethereumAddress.hexEip55] = ContactConsent.deny;
    var action = xmtp.PrivatePreferencesAction()
      ..block = xmtp.PrivatePreferencesAction_Block(
        walletAddresses: [ethereumAddress.hexEip55],
      );
    await _publishAction(keys, action);
    return true;
  }

  Future<bool> allow(
    xmtp.PrivateKeyBundle keys,
    EthereumAddress ethereumAddress,
  ) async {
    _consentByAddress[ethereumAddress.hexEip55] = ContactConsent.allow;
    var action = xmtp.PrivatePreferencesAction()
      ..allow = xmtp.PrivatePreferencesAction_Allow(
        walletAddresses: [ethereumAddress.hexEip55],
      );
    await _publishAction(keys, action);
    return true;
  }

  Future<xmtp.PublishResponse> _publishAction(
    xmtp.PrivateKeyBundle keys,
    xmtp.PrivatePreferencesAction action,
  ) async {
    var topic = await Topic.userPreferences(keys.identity.privateKey);
    var payload = await libxmtp.userPreferencesEncrypt(
      publicKey: keys.identity.publicKey.getEncoded(false),
      privateKey: keys.identity.privateKey,
      message: action.writeToBuffer(),
    );
    return _api.client.publish(
      xmtp.PublishRequest(
        envelopes: [
          xmtp.Envelope(
            contentTopic: topic,
            timestampNs: nowNs(),
            message: payload,
          )
        ],
      ),
    );
  }
}

String _normalizeAddress(String address) =>
    EthereumAddress.fromHex(address).hexEip55;

/// This is a compact representation of the user's consents.
///
/// For convenience, it includes serializing helpers to/from bytes.
class CompactConsents {
  // All explicitly allowed contacts.
  final xmtp.PrivatePreferencesAction_Allow allowed;

  // All explicitly denied contacts.
  final xmtp.PrivatePreferencesAction_Block denied;

  // The time we last refreshed consents from the network, if ever.
  final DateTime? lastRefreshedAt;

  CompactConsents(this.allowed, this.denied, this.lastRefreshedAt);

  static const _addressByteLength = EthereumAddress.addressByteLength;

  Uint8List writeToBuffer() {
    // 3 64-bit numbers in the header followed by the allowed/blocked addresses.
    var header = Uint8List(3 * 8);
    var lastRefreshed64 = lastRefreshedAt?.millisecondsSinceEpoch ?? 0;
    header.buffer.asByteData().setUint64(0, lastRefreshed64);
    header.buffer.asByteData().setUint64(8, allowed.walletAddresses.length);
    header.buffer.asByteData().setUint64(16, denied.walletAddresses.length);

    List<int> out = header;
    // Note: we sort the addresses so the output is deterministic.
    for (var address in List.of(allowed.walletAddresses)..sort()) {
      out += EthereumAddress.fromHex(address).addressBytes;
    }
    for (var address in List.of(denied.walletAddresses)..sort()) {
      out += EthereumAddress.fromHex(address).addressBytes;
    }
    return Uint8List.fromList(out);
  }

  static CompactConsents fromBuffer(List<int> buffer) {
    var input = Uint8List.fromList(buffer);

    // 3 64-bit numbers then the allowed and blocked messages.
    var lastRefreshed64 = input.buffer.asByteData().getUint64(0);
    var allowedLength = input.buffer.asByteData().getUint64(8);
    var blockedLength = input.buffer.asByteData().getUint64(16);
    checkArgument(
        buffer.length ==
            3 * 8 + (allowedLength + blockedLength) * _addressByteLength,
        message: 'invalid buffer length');

    var offset = 3 * 8;
    var allowed = List.generate(allowedLength, (i) {
      var address = EthereumAddress(
          Uint8List.view(input.buffer, offset, _addressByteLength));
      offset += _addressByteLength;
      return address.hexEip55;
    });

    var denied = List.generate(blockedLength, (i) {
      var address = EthereumAddress(
          Uint8List.view(input.buffer, offset, _addressByteLength));
      offset += _addressByteLength;
      return address.hexEip55;
    });

    return CompactConsents(
      xmtp.PrivatePreferencesAction_Allow(walletAddresses: allowed),
      xmtp.PrivatePreferencesAction_Block(walletAddresses: denied),
      lastRefreshed64 == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastRefreshed64, isUtc: true),
    );
  }
}

enum ContactConsent {
  /// This indicates that the user has not yet consented to the contact.
  unknown,

  /// This indicates that the user has consented to the contact.
  allow,

  /// This indicates that the user has explicitly denied the contact.
  deny,
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
              ),
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
