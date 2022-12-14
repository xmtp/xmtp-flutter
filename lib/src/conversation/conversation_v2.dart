import 'dart:convert';
import 'dart:typed_data';

import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:web3dart/credentials.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import '../auth.dart';
import '../contact.dart';
import '../common/api.dart';
import '../common/crypto.dart';
import '../common/signature.dart';
import '../common/time64.dart';
import '../common/topic.dart';
import '../content/decoded.dart';
import '../content/codec_registry.dart';
import '../content/text_codec.dart';
import 'conversation.dart';

/// This manages all V2 conversations.
/// It provides instances of the V2 implementation of [Conversation].
/// NOTE: it aims to limit exposure of the V2 specific details.
class ConversationManagerV2 {
  final EthereumAddress _me;
  final Api _api;
  final AuthManager _auth;
  final CodecRegistry _codecs;
  final ContactManager _contacts;

  ConversationManagerV2(
    this._me,
    this._api,
    this._auth,
    this._codecs,
    this._contacts,
  );

  /// This creates a new conversation with [address] in the specified [context].
  /// This includes sending out the new chat invitations to [_me] and [peer].
  Future<Conversation> newConversation(
    String address,
    xmtp.InvitationV1_Context context,
  ) async {
    var peer = EthereumAddress.fromHex(address);
    var invite = _createInviteV1(context);
    var peerContact = await _contacts.getUserContactV2(peer.hex);
    var sealed = await _encryptInviteV1(
      _auth.keys,
      peerContact.v2.keyBundle,
      invite,
    );
    await _sendInvites(peer, sealed);
    return _conversationFromInvite(sealed);
  }

  /// This returns the latest [Conversation] with [address]
  /// that has the same [context.conversationId].
  /// If none can be found then this returns `null`.
  Future<Conversation?> findConversation(
    String address,
    xmtp.InvitationV1_Context context,
  ) async {
    var peer = EthereumAddress.fromHex(address);
    var conversations = await listConversations();
    try {
      return conversations.firstWhere((c) =>
          c.peer == peer &&
          c.invite.context.conversationId == context.conversationId);
    } catch (notFound) {
      return null;
    }
  }

  /// This returns the list of all invited [Conversation]s.
  Future<List<Conversation>> listConversations([
    DateTime? start,
    DateTime? end,
    int? limit,
    xmtp.SortDirection? sort,
  ]) async {
    var listing = await _api.client.query(xmtp.QueryRequest(
      contentTopics: [Topic.userInvite(_me.hex)],
      startTimeNs: start?.toNs64(),
      endTimeNs: end?.toNs64(),
      pagingInfo: xmtp.PagingInfo(
        limit: limit,
        direction: sort,
      ),
    ));
    var conversations = await Future.wait(listing.envelopes
        .map((e) => xmtp.SealedInvitation.fromBuffer(e.message))
        .map((sealed) => _conversationFromInvite(sealed)));
    // Remove duplicates by topic identifier.
    var unique = <String>{};
    return conversations.where((c) => unique.add(c.topic)).toList();
  }

  /// This exposes a stream of new [Conversation]s.
  Stream<Conversation> streamConversations() => _api.client
      .subscribe(xmtp.SubscribeRequest(contentTopics: [
        Topic.userInvite(_me.hex),
      ]))
      .map((e) => xmtp.SealedInvitation.fromBuffer(e.message))
      .asyncMap((sealed) => _conversationFromInvite(sealed));

  /// This helper adapts a [sealed] invitation into a [Conversation].
  Future<Conversation> _conversationFromInvite(
    xmtp.SealedInvitation sealed,
  ) async {
    var headerBytes = sealed.v1.headerBytes;
    var header = xmtp.SealedInvitationHeaderV1.fromBuffer(headerBytes);
    var invite = await decryptInviteV1(sealed.v1, _auth.keys);
    var createdAt = header.createdNs.toDateTime();
    var sender = header.sender.wallet;
    var recipient = header.recipient.wallet;
    var peer = {sender, recipient}.firstWhere((a) => a != _me);
    return Conversation.v2(
      invite,
      createdAt,
      me: _me,
      peer: peer,
    );
  }

  /// This sends the [content] as a message to the [conversation].
  Future<DecodedMessage> sendMessage(
    Conversation conversation,
    Object content, {
    xmtp.ContentTypeId? contentType,
  }) async {
    contentType ??= contentTypeText;
    var encoded = await _codecs.encode(DecodedContent(contentType, content));
    var header = xmtp.MessageHeaderV2(
      topic: conversation.topic,
      createdNs: nowNs(),
    );
    var signed = await _signContent(_auth.keys, header, encoded);
    var encrypted = await _encryptMessageV2(
        _auth.keys, conversation.invite, header, signed);
    var dm = xmtp.Message(v2: encrypted);
    await _api.client.publish(xmtp.PublishRequest(envelopes: [
      xmtp.Envelope(
        contentTopic: conversation.topic,
        timestampNs: nowNs(),
        message: dm.writeToBuffer(),
      ),
    ]));
    return _createDecodedMessage(dm, signed, contentType, content, encoded);
  }

  /// This lists the current messages in the [conversation]
  Future<List<DecodedMessage>> listMessages(
    Conversation conversation, [
    DateTime? start,
    DateTime? end,
    int? limit,
    xmtp.SortDirection? sort,
  ]) async {
    var listing = await _api.client.query(xmtp.QueryRequest(
      contentTopics: [conversation.topic],
      startTimeNs: start?.toNs64(),
      endTimeNs: end?.toNs64(),
      pagingInfo: xmtp.PagingInfo(
        limit: limit,
        direction: sort,
      ),
    ));
    return Future.wait(listing.envelopes
        .map((e) => xmtp.Message.fromBuffer(e.message))
        .map((msg) => _decodedFromMessage(conversation, msg)));
  }

  /// This exposes the stream of new messages in the [conversation].
  Stream<DecodedMessage> streamMessages(
    Conversation conversation,
  ) =>
      _api.client
          .subscribe(xmtp.SubscribeRequest(contentTopics: [conversation.topic]))
          .map((e) => xmtp.Message.fromBuffer(e.message))
          .asyncMap((msg) => _decodedFromMessage(conversation, msg));

  /// This decrypts and decodes the [xmtp.Message].
  Future<DecodedMessage> _decodedFromMessage(
    Conversation conversation,
    xmtp.Message msg,
  ) async {
    var signed = await _decryptMessageV2(msg.v2, conversation.invite);
    var encoded = xmtp.EncodedContent.fromBuffer(signed.payload);
    var decoded = await _codecs.decode(encoded);
    return _createDecodedMessage(
      msg,
      signed,
      decoded.contentType,
      decoded.content,
      encoded,
    );
  }

  /// This helper sends the [sealed] invite to [_me] and to [peer].
  Future<xmtp.PublishResponse> _sendInvites(
    EthereumAddress peer,
    xmtp.SealedInvitation sealed,
  ) =>
      _api.client.publish(xmtp.PublishRequest(
        envelopes: [_me.hex, peer.hex].map(
          (walletAddress) => xmtp.Envelope(
            contentTopic: Topic.userInvite(walletAddress),
            timestampNs: nowNs(),
            message: sealed.writeToBuffer(),
          ),
        ),
      ));
}

/// This uses the provided `context` to create a new conversation invitation.
/// It randomly generates the topic identifier and encryption key material.
xmtp.InvitationV1 _createInviteV1(xmtp.InvitationV1_Context context) {
  // The topic is a random string of alphanumerics.
  // This base64 encodes some random bytes and strips non-alphanumerics.
  // Note: we don't rely on this being valid base64 anywhere.
  var randomId = base64.encode(generateRandomBytes(32));
  randomId = randomId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  var topic = Topic.messageV2(randomId);

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
Future<xmtp.SealedInvitation> _encryptInviteV1(
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
    createdNs: nowNs(),
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
Future<xmtp.MessageV2> _encryptMessageV2(
  xmtp.PrivateKeyBundle keys,
  xmtp.InvitationV1 invite,
  xmtp.MessageHeaderV2 header,
  xmtp.SignedContent signed,
) async {
  var headerBytes = header.writeToBuffer();
  var secret = invite.aes256GcmHkdfSha256.keyMaterial;
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
Future<xmtp.SignedContent> _decryptMessageV2(
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
  var signature = sign(Uint8List.fromList(digest), preKey.privateKey);
  return xmtp.SignedContent(
    payload: payload,
    sender: createContactBundleV2(keys).v2.keyBundle,
    signature: xmtp.Signature(
      ecdsaCompact: signature.toEcdsaCompact(),
    ),
  );
}

/// This creates the [DecodedMessage] from the various parts.
Future<DecodedMessage> _createDecodedMessage(
  xmtp.Message dm,
  xmtp.SignedContent signed,
  xmtp.ContentTypeId contentType,
  Object content,
  xmtp.EncodedContent encoded,
) async {
  var id = bytesToHex(await sha256(dm.writeToBuffer()));
  var header = xmtp.MessageHeaderV2.fromBuffer(dm.v2.headerBytes);
  var sender = signed.sender.wallet;
  var sentAt = header.createdNs.toDateTime();
  return DecodedMessage(
    xmtp.Message_Version.v2,
    sentAt,
    sender,
    encoded,
    contentType,
    content,
    id: id,
    topic: header.topic,
  );
}
