import 'dart:typed_data';

import 'package:quiver/check.dart';
import 'package:web3dart/credentials.dart';
import 'package:xmtp_bindings_flutter/xmtp_bindings_flutter.dart';

/// Clients interact with XMTP by querying, subscribing, and publishing
/// to these topics.
///
/// NOTE: wallet addresses are normalized.
/// See [EIP 55](https://github.com/ethereum/EIPs/blob/master/EIPS/eip-55.md)
class Topic {
  /// All topics are in this format.
  static String _content(String name) => '$_versionPrefix/$name/proto';

  static const String _versionPrefix = "/xmtp/0";

  /// This represents direct message conversation between `sender` and `recipient`.
  /// NOTE: the addresses are normalized (EIP-55) and then sorted.
  static String directMessageV1(String senderAddress, String recipientAddress) {
    var addresses = [
      _normalize(senderAddress),
      _normalize(recipientAddress),
    ];
    addresses.sort();
    return _content('dm-${addresses.join('-')}');
  }

  /// This contains ephemeral messages belonging to the `conversationTopic`.
  /// It knows how to create the ephemeral topic for both v1 and v2.
  static String ephemeralMessage(String conversationTopic) {
    checkArgument(
        conversationTopic.startsWith('$_versionPrefix/dm-') ||
            conversationTopic.startsWith('$_versionPrefix/m-'),
        message: 'invalid conversation topic');
    return conversationTopic
        .replaceFirst('$_versionPrefix/dm-', '$_versionPrefix/dmE-')
        .replaceFirst('$_versionPrefix/m-', '$_versionPrefix/mE-');
  }

  /// This represents a message conversation.
  static String messageV2(String randomString) => _content('m-$randomString');

  /// This represents a published contact for the user.
  static String userContact(String walletAddress) =>
      _content('contact-${_normalize(walletAddress)}');

  static String userIntro(String walletAddress) =>
      _content('intro-${_normalize(walletAddress)}');

  static String userInvite(String walletAddress) =>
      _content('invite-${_normalize(walletAddress)}');

  /// This topic stores private key bundles for the specified wallet.
  /// They are encrypted so that only that wallet can see them.
  static String userPrivateStoreKeyBundle(String walletAddress) =>
      _content('privatestore-${_normalize(walletAddress)}/key_bundle');

  static Future<String> userPreferences(List<int> privateKey) async => _content(
      'userpreferences-${await generateUserPreferencesIdentifier(privateKey)}');

  static _normalize(String walletAddress) =>
      EthereumAddress.fromHex(walletAddress).hexEip55;
}

Future<String> generateUserPreferencesIdentifier(List<int> privateKey) async {
  await libxmtpInit(); // typically no-op because it's already initialized
  return generatePrivatePreferencesTopicIdentifier(
    privateKeyBytes: Uint8List.fromList(privateKey),
  );
}
