import 'dart:async';
import 'dart:typed_data';

import 'package:web3dart/credentials.dart';
import 'package:web3dart/crypto.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import '../auth.dart';
import '../common/api.dart';
import '../common/crypto.dart';
import '../common/signature.dart';
import '../common/topic.dart';
import '../common/time64.dart';
import '../contact.dart';
import '../content/text_codec.dart';
import '../content/codec_registry.dart';
import '../content/decoded.dart';
import 'conversation.dart';

/// This manages all V1 conversations.
/// It provides instances of the V1 implementation of [Conversation].
/// NOTE: it aims to limit exposure of the V1 specific details.
class ConversationManagerV1 {
  final EthereumAddress _me;
  final Api _api;
  final AuthManager _auth;
  final CodecRegistry _codecs;
  final ContactManager _contacts;

  // This is a session-cache of known conversations.
  // We use this to decide whether a message requires us to fire off intros.
  final Set<String> _seenTopics = {};

  ConversationManagerV1(
    this._me,
    this._api,
    this._auth,
    this._codecs,
    this._contacts,
  );

  Future<Conversation> fromBlob(Uint8List blob) async {
    return _conversationFromIntro(xmtp.Message.fromBuffer(blob));
  }

  Future<Conversation> newConversation(String address) async {
    var peer = EthereumAddress.fromHex(address);
    var createdAt = DateTime.now();
    return Conversation.v1(createdAt, me: _me, peer: peer);
  }

  /// This returns the latest [Conversation] with [address].
  /// If none can be found then this returns `null`.
  Future<Conversation?> findConversation(String address) async {
    var peer = EthereumAddress.fromHex(address);
    var conversations = await listConversations();
    try {
      return conversations.firstWhere((c) => c.peer == peer);
    } catch (notFound) {
      return null;
    }
  }

  Future<List<Conversation>> listConversations() async {
    var listing = await _api.client.query(xmtp.QueryRequest(
      contentTopics: [Topic.userIntro(_me.hex)],
      // TODO: support listing params per js-lib
    ));
    var conversations = await Future.wait(listing.envelopes
        .map((e) => xmtp.Message.fromBuffer(e.message))
        .map((msg) => _conversationFromIntro(msg)));
    // Remove duplicates by topic identifier.
    var unique = <String>{};
    return conversations.where((c) => unique.add(c.topic)).toList();
  }

  Stream<Conversation> streamConversations() => _api.client
      .subscribe(xmtp.SubscribeRequest(contentTopics: [
        Topic.userIntro(_me.hex),
      ]))
      .map((e) => xmtp.Message.fromBuffer(e.message))
      .asyncMap((msg) => _conversationFromIntro(msg));

  Future<Conversation> _conversationFromIntro(xmtp.Message msg) async {
    var header = xmtp.MessageHeaderV1.fromBuffer(msg.v1.headerBytes);
    var encoded = await decryptMessageV1(msg.v1, _auth.keys);
    var decoded = await _codecs.decodeContent(encoded);
    var intro = await _createDecodedMessage(
      msg,
      decoded.contentType,
      decoded.content,
      encoded,
    );
    var createdAt = intro.sentAt;
    var sender = intro.sender;
    var recipient = header.recipient.identityKey
        .recoverWalletSignerPublicKey()
        .toEthereumAddress();
    var peer = {sender, recipient}.firstWhere((a) => a != _me);
    var topic = Topic.directMessageV1(_me.hex, peer.hex);
    _seenTopics.add(topic);
    return Conversation.v1(createdAt, me: _me, peer: peer);
  }

  Future<List<DecodedMessage>> listMessages(
    Conversation conversation,
  ) async {
    var listing = await _api.client.query(xmtp.QueryRequest(
      contentTopics: [conversation.topic],
      // TODO: support listing params per js-lib
    ));
    return Future.wait(listing.envelopes
        .map((e) => xmtp.Message.fromBuffer(e.message))
        .map((msg) => _decodedFromMessage(msg)));
  }

  Stream<DecodedMessage> streamMessages(Conversation conversation) =>
      _api.client
          .subscribe(xmtp.SubscribeRequest(contentTopics: [conversation.topic]))
          .map((e) => xmtp.Message.fromBuffer(e.message))
          .asyncMap((msg) => _decodedFromMessage(msg));

  /// This decrypts and decodes the [xmtp.Message].
  Future<DecodedMessage> _decodedFromMessage(xmtp.Message msg) async {
    var encoded = await decryptMessageV1(msg.v1, _auth.keys);
    var decoded = await _codecs.decodeContent(encoded);
    return _createDecodedMessage(
      msg,
      decoded.contentType,
      decoded.content,
      encoded,
    );
  }

  Future<DecodedMessage> sendMessage(
    Conversation conversation,
    Object content, {
    xmtp.ContentTypeId? contentType,
  }) async {
    contentType ??= contentTypeText;
    var encoded = await _codecs.encodeContent(contentType, content);
    var peerContact = await _contacts.getUserContactV1(conversation.peer.hex);
    var encrypted = await encryptMessageV1(
      _auth.keys,
      peerContact.v1.keyBundle,
      encoded,
    );
    var msg = xmtp.Message(v1: encrypted);
    if (!_seenTopics.contains(conversation.topic)) {
      _seenTopics.add(conversation.topic);
      await _sendIntros(conversation, encrypted);
    }
    await _api.client.publish(xmtp.PublishRequest(envelopes: [
      xmtp.Envelope(
        contentTopic: conversation.topic,
        timestampNs: nowNs(),
        message: msg.writeToBuffer(),
      ),
    ]));

    // This returns a decoded edition for optimistic local updates.
    return _createDecodedMessage(msg, contentType, content, encoded);
  }

  Future<xmtp.PublishResponse> _sendIntros(
    Conversation conversation,
    xmtp.MessageV1 msg,
  ) async {
    var addresses = [
      conversation.me.hex,
      conversation.peer.hex,
    ];
    var timestampNs = nowNs();
    var message = xmtp.Message(v1: msg).writeToBuffer();
    return _api.client.publish(xmtp.PublishRequest(
      envelopes: addresses.map(
        (a) => xmtp.Envelope(
          contentTopic: Topic.userIntro(a),
          timestampNs: timestampNs,
          message: message,
        ),
      ),
    ));
  }
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
    timestamp: nowMs(),
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

/// This creates the [DecodedMessage] from the various parts.
Future<DecodedMessage> _createDecodedMessage(
  xmtp.Message dm,
  xmtp.ContentTypeId contentType,
  Object content,
  xmtp.EncodedContent encoded,
) async {
  var id = bytesToHex(await sha256(dm.writeToBuffer()));
  var header = xmtp.MessageHeaderV1.fromBuffer(dm.v1.headerBytes);
  var sender = header.sender.wallet;
  var sentAt = header.timestamp.toDateTime();
  var topic = Topic.directMessageV1(sender.hex, header.recipient.wallet.hex);
  return DecodedMessage(
    xmtp.Message_Version.v1,
    sentAt,
    sender,
    encoded,
    contentType,
    content,
    id: id,
    topic: topic,
  );
}
