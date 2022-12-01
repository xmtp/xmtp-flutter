import 'dart:convert';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:web3dart/web3dart.dart';

import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import './auth.dart';
import './contact.dart';
import './crypto.dart';
import './signature.dart';

/// This uses the provided `context` to create a new conversation invitation.
/// It randomly generates the topic identifier and encryption key material.
xmtp.InvitationV1 createInviteV1(xmtp.InvitationV1_Context context) {
  // The topic is a random string of alphanumerics.
  // This base64 encodes some random bytes and strips non-alphanumerics.
  // Note: we don't rely on this being valid base64 anywhere.
  var topic = base64.encode(generateRandomBytes(32));
  topic = topic.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');

  var keyMaterial = generateRandomBytes(32);
  return xmtp.InvitationV1(
    topic: topic,
    aes256GcmHkdfSha256: xmtp.InvitationV1_Aes256gcmHkdfsha256(
      keyMaterial: keyMaterial,
    ),
    context: context,
  );
}

/// This uses `keys` to encrypt the `invite` to `recipient`.
/// It derives the 3DH secret and uses that to encrypt the ciphertext.
Future<xmtp.SealedInvitation> encryptInviteV1(
  xmtp.PrivateKeyBundle keys,
  xmtp.SignedPublicKeyBundle recipient,
  xmtp.InvitationV1 invite,
) async {
  var isRecipientMe = false;
  var secret = compute3DHSecret(
    createECPrivateKey(keys.identity.privateKey),
    createECPrivateKey(keys.preKeys.first.privateKey),
    createECPublicKey(recipient.identityKey.publicKeyBytes),
    createECPublicKey(recipient.preKey.publicKeyBytes),
    isRecipientMe,
  );
  var header = xmtp.SealedInvitationHeaderV1(
    sender: createContactBundleV2(keys).v2.keyBundle,
    recipient: recipient,
    createdNs: Int64(DateTime.now().millisecondsSinceEpoch) * 1000000,
  );
  var headerBytes = header.writeToBuffer();
  var ciphertext = await encrypt(
    secret,
    invite.writeToBuffer(),
    aad: headerBytes,
  );
  return xmtp.SealedInvitation(
    v1: xmtp.SealedInvitationV1(
      headerBytes: header.writeToBuffer(),
      ciphertext: ciphertext,
    ),
  );
}

/// This decrypts the `sealed` invitation using the `keys`.
/// It derives the 3DH secret and uses that to decrypt the ciphertext.
Future<xmtp.InvitationV1> decryptInviteV1(
  xmtp.SealedInvitationV1 sealed,
  xmtp.PrivateKeyBundle keys,
) async {
  var header = xmtp.SealedInvitationHeaderV1.fromBuffer(sealed.headerBytes);
  var recipientAddress = header.recipient.identity;
  var isRecipientMe = recipientAddress == keys.identity.address;
  var me = isRecipientMe ? header.recipient : header.sender;
  var peer = !isRecipientMe ? header.recipient : header.sender;

  var secret = compute3DHSecret(
    createECPrivateKey(keys.identity.privateKey),
    createECPrivateKey(keys.getPre(me.pre).privateKey),
    createECPublicKey(peer.identityKey.publicKeyBytes),
    createECPublicKey(peer.preKey.publicKeyBytes),
    isRecipientMe,
  );
  var decrypted = await decrypt(
    secret,
    sealed.ciphertext,
    aad: sealed.headerBytes,
  );
  return xmtp.InvitationV1.fromBuffer(decrypted);
}

/// This uses `keys` to sign the `content` and then encrypts it
/// using the key material from the `invite`.
Future<xmtp.MessageV2> encryptMessageV2(
  xmtp.PrivateKeyBundle keys,
  xmtp.InvitationV1 invite,
  xmtp.EncodedContent content,
) async {
  var header = xmtp.MessageHeaderV2(
    topic: invite.topic,
    createdNs: Int64(DateTime.now().millisecondsSinceEpoch) * 1000000,
  );
  var headerBytes = header.writeToBuffer();
  var secret = invite.aes256GcmHkdfSha256.keyMaterial;
  var signed = await _signContent(keys, header, content);
  var ciphertext = await encrypt(
    secret,
    signed.writeToBuffer(),
    aad: headerBytes,
  );
  return xmtp.MessageV2(
    headerBytes: headerBytes,
    ciphertext: ciphertext,
  );
}

/// This decrypts the `msg` using the key material from the `invite`.
Future<xmtp.SignedContent> decryptMessageV2(
  xmtp.MessageV2 msg,
  xmtp.InvitationV1 invite,
) async {
  var secret = invite.aes256GcmHkdfSha256.keyMaterial;
  var decryptedBytes = await decrypt(
    secret,
    msg.ciphertext,
    aad: msg.headerBytes,
  );
  return xmtp.SignedContent.fromBuffer(decryptedBytes);
}

/// This signs the `content` to prove that it was sent
/// by the `keys` sender to the `header` conversation.
Future<xmtp.SignedContent> _signContent(
  xmtp.PrivateKeyBundle keys,
  xmtp.MessageHeaderV2 header,
  xmtp.EncodedContent content,
) async {
  var headerBytes = header.writeToBuffer();
  var payload = content.writeToBuffer();
  var digest = await sha256(headerBytes + payload);
  var preKey = keys.preKeys.first;
  var signature = await preKey.signToSignature(Uint8List.fromList(digest));
  return xmtp.SignedContent(
    payload: payload,
    sender: createContactBundleV2(keys).v2.keyBundle,
    signature: xmtp.Signature(
      ecdsaCompact: signature.toEcdsaCompact(),
    ),
  );
}

/// This decrypts the `msg` using the `keys`.
/// It derives the 3DH secret and uses that to decrypt the ciphertext.
Future<xmtp.EncodedContent> decryptMessageV1(
  xmtp.MessageV1 msg,
  xmtp.PrivateKeyBundle keys,
) async {
  var header = xmtp.MessageHeaderV1.fromBuffer(msg.headerBytes);
  var recipientAddress = header.recipient.identity;
  var isRecipientMe = recipientAddress == keys.identity.address;
  var me = isRecipientMe ? header.recipient : header.sender;
  var peer = !isRecipientMe ? header.recipient : header.sender;

  var secret = compute3DHSecret(
    createECPrivateKey(keys.identity.privateKey),
    createECPrivateKey(keys.getPre(me.pre).privateKey),
    createECPublicKey(peer.identityKey.secp256k1Uncompressed.bytes),
    createECPublicKey(peer.preKey.secp256k1Uncompressed.bytes),
    isRecipientMe,
  );
  var decrypted = await decrypt(
    secret,
    msg.ciphertext,
    aad: msg.headerBytes,
  );
  return xmtp.EncodedContent.fromBuffer(decrypted);
}

/// This uses `keys` to encrypt the `content` as a [xmtp.MessageV1]
/// to `recipient`.
/// It derives the 3DH secret and uses that to encrypt the ciphertext.
Future<xmtp.MessageV1> encryptMessageV1(
  xmtp.PrivateKeyBundle keys,
  xmtp.PublicKeyBundle recipient,
  xmtp.EncodedContent content,
) async {
  var isRecipientMe = false;
  var secret = compute3DHSecret(
    createECPrivateKey(keys.identity.privateKey),
    createECPrivateKey(keys.preKeys.first.privateKey),
    createECPublicKey(recipient.identityKey.secp256k1Uncompressed.bytes),
    createECPublicKey(recipient.preKey.secp256k1Uncompressed.bytes),
    isRecipientMe,
  );
  var header = xmtp.MessageHeaderV1(
    sender: xmtp.PublicKeyBundle(
      identityKey: keys.toV1().identityKey.publicKey,
      preKey: keys.toV1().preKeys.first.publicKey,
    ),
    recipient: recipient,
    timestamp: Int64(DateTime.now().millisecondsSinceEpoch),
  );
  var headerBytes = header.writeToBuffer();
  var ciphertext = await encrypt(
    secret,
    content.writeToBuffer(),
    aad: headerBytes,
  );
  return xmtp.MessageV1(
    headerBytes: headerBytes,
    ciphertext: ciphertext,
  );
}

/// This adds helpers on [xmtp.PublicKeyBundle] to clean up header parsing.
extension _PKBundleToEthAddresses on xmtp.PublicKeyBundle {
  EthereumAddress get wallet =>
      identityKey.recoverWalletSignerPublicKey().toEthereumAddress();

  EthereumAddress get identity =>
      identityKey.secp256k1Uncompressed.bytes.toEthereumAddress();

  EthereumAddress get pre =>
      preKey.secp256k1Uncompressed.bytes.toEthereumAddress();
}

/// This adds helpers on [xmtp.SignedPublicKeyBundle] to clean up header parsing.
extension _SPKBundleToEthAddresses on xmtp.SignedPublicKeyBundle {
  EthereumAddress get wallet =>
      identityKey.recoverWalletSignerPublicKey().toEthereumAddress();

  EthereumAddress get identity =>
      identityKey.publicKeyBytes.toEthereumAddress();

  EthereumAddress get pre => preKey.publicKeyBytes.toEthereumAddress();
}

/// This adds helper to grab the public key bytes from an [xmtp.SignedPublicKey]
extension _ToPublicKeyBytes on xmtp.SignedPublicKey {
  List<int> get publicKeyBytes =>
      xmtp.UnsignedPublicKey.fromBuffer(keyBytes).secp256k1Uncompressed.bytes;
}

/// TODO: consider reorganizing when we introduce codecs
final contentTypeText = xmtp.ContentTypeId(
  authorityId: "xmtp.org",
  typeId: "text",
  versionMajor: 1,
  versionMinor: 0,
);
