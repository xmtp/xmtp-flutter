import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:quiver/check.dart';
import 'package:quiver/iterables.dart';
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
  @visibleForTesting
  final Api api;
  @visibleForTesting
  final AuthManager auth;
  final CodecRegistry _codecs;
  @visibleForTesting
  final ContactManager contacts;

  ConversationManagerV2(
    this._me,
    this.api,
    this.auth,
    this._codecs,
    this.contacts,
  );

  /// This creates a new conversation with [address] in the specified [context].
  /// This includes sending out the new chat invitations to [_me] and [peer].
  Future<Conversation> newConversation(
    String address,
    xmtp.InvitationV1_Context context,
  ) async {
    var peer = EthereumAddress.fromHex(address);
    var peerContact = await contacts.getUserContactV2(peer.hex);
    var peerKeys = peerContact.v2.keyBundle;
    var invite = await createInviteV1(auth.keys, peerKeys, context);
    var now = nowNs();
    var sealed = await encryptInviteV1(
      auth.keys,
      peerKeys,
      invite,
      now,
    );
    await _sendInvites(peer, sealed, now);
    return _conversationFromInvite(sealed, now);
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
  ///
  /// Note: bad conversation invitation envelopes are discarded.
  Future<List<Conversation>> listConversations([
    DateTime? start,
    DateTime? end,
    int? limit,
    xmtp.SortDirection? sort,
  ]) async {
    var listing = api.client.envelopes(xmtp.QueryRequest(
      contentTopics: [Topic.userInvite(_me.hex)],
      startTimeNs: start?.toNs64(),
      endTimeNs: end?.toNs64(),
      pagingInfo: xmtp.PagingInfo(
        limit: limit,
        direction: sort,
      ),
    ));
    var conversations = listing.asyncMap((e) => _conversationFromEnvelope(e));
    var unique = <String>{};
    return conversations
        // Remove nulls (which are discarded bad envelopes).
        .where((c) => c != null)
        .map((c) => c!)
        // Remove duplicates by topic identifier.
        .where((c) => unique.add(c.topic))
        .toList();
  }

  /// This exposes a stream of new [Conversation]s.
  ///
  /// Note: bad conversation invitation envelopes are discarded.
  Stream<Conversation> streamConversations() => api.client
      .subscribe(xmtp.SubscribeRequest(contentTopics: [
        Topic.userInvite(_me.hex),
      ]))
      .asyncMap((envelope) => _conversationFromEnvelope(envelope))
      // Remove nulls (which are discarded bad envelopes).
      .where((convo) => convo != null)
      .map((convo) => convo!);

  Future<Conversation?> decryptConversation(xmtp.Envelope env) =>
      _conversationFromEnvelope(env);

  /// This helper adapts an [envelope] (with an invite) into a [Conversation].
  ///
  /// It returns `null` when the envelope could not be decoded.
  Future<Conversation?> _conversationFromEnvelope(xmtp.Envelope e) async {
    try {
      var invite = xmtp.SealedInvitation.fromBuffer(e.message);
      checkState(e.hasMessage(), message: 'missing envelope message');
      checkState(e.timestampNs > 0, message: 'missing envelope timestamp');
      return await _conversationFromInvite(invite, e.timestampNs);
    } catch (e) {
      debugPrint('discarding bad invite: $e');
      return null;
    }
  }

  /// This helper adapts a [sealed] invitation into a [Conversation].
  Future<Conversation> _conversationFromInvite(
    xmtp.SealedInvitation sealed,
    Int64 expectedTimestampNs,
  ) async {
    var headerBytes = sealed.v1.headerBytes;
    var header = xmtp.SealedInvitationHeaderV1.fromBuffer(headerBytes);
    var invite = await decryptInviteV1(sealed.v1, auth.keys);
    checkState(expectedTimestampNs == header.createdNs,
        message: 'envelope and header timestamp mismatch');
    var createdAt = header.createdNs.toDateTime();
    var sender = header.sender.wallet;
    var recipient = header.recipient.wallet;
    var peer = {sender, recipient}.firstWhere(
      (a) => a != _me,
      orElse: () => sender,
    );
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
    bool isEphemeral = false,
  }) async {
    contentType ??= contentTypeText;
    var encoded = await _codecs.encode(DecodedContent(contentType, content));
    var sent = await sendMessageEncoded(conversation, encoded, isEphemeral);
    return sent!;
  }

  /// This sends the [encoded] message to the [conversation].
  /// If it cannot be decoded then it still sends but this returns `null`.
  Future<DecodedMessage?> sendMessageEncoded(
    Conversation conversation,
    xmtp.EncodedContent encoded,
    bool isEphemeral,
  ) async {
    var now = nowNs();
    var header = xmtp.MessageHeaderV2(
      topic: conversation.topic,
      createdNs: now,
    );
    var signed = await signContent(auth.keys, header, encoded);
    var encrypted = await encryptMessageV2(conversation.invite, header, signed);
    var dm = xmtp.Message(v2: encrypted);
    await api.client.publish(xmtp.PublishRequest(envelopes: [
      xmtp.Envelope(
        contentTopic:
            isEphemeral ? conversation.ephemeralTopic : conversation.topic,
        timestampNs: now,
        message: dm.writeToBuffer(),
      ),
    ]));
    try {
      return await _createDecodedMessage(dm, signed);
    } catch (err) {
      debugPrint('unable to decode sent message');
      return null;
    }
  }

  /// This lists the current messages in the [conversations]
  Future<List<DecodedMessage>> listMessages(
    Iterable<Conversation> conversations, {
    Iterable<Pagination>? paginations,
    xmtp.SortDirection? sort,
  }) async {
    if (conversations.isEmpty) {
      return [];
    }
    var ps = paginations?.toList();
    var requests = enumerate(conversations).map((c) => xmtp.QueryRequest(
          contentTopics: [c.value.topic], // Limit one topic per query
          startTimeNs: ps?[c.index].start?.toNs64(),
          endTimeNs: ps?[c.index].end?.toNs64(),
          pagingInfo: xmtp.PagingInfo(
            limit: ps?[c.index].limit,
            direction: ps?[c.index].sort,
          ),
        ));
    // Batch up the requests to avoid requesting too many in one shot.
    var batches = partition(requests, maxQueryRequestsPerBatch);
    var compare = envelopeComparator(sort);
    var results = await Future.wait(batches.map((batch) => api.client
        .batchEnvelopes(xmtp.BatchQueryRequest(requests: batch))
        .toList()));
    var listing = results.reduce((l, r) => l..addAll(r)).sorted(compare);
    var convoByTopic = {for (var c in conversations) c.topic: c};
    var messages = await Future.wait(listing
        .where((e) => convoByTopic.containsKey(e.contentTopic))
        .map((e) => _decodedFromMessage(
              convoByTopic[e.contentTopic]!,
              xmtp.Message.fromBuffer(e.message),
            )));
    // Remove nulls (which are discarded bad envelopes).
    return messages.where((msg) => msg != null).map((msg) => msg!).toList();
  }

  /// This exposes the stream of new messages in the [conversations].
  Stream<DecodedMessage> streamMessages(Iterable<Conversation> conversations) {
    if (conversations.isEmpty) {
      return const Stream.empty();
    }
    var convoByTopic = {for (var c in conversations) c.topic: c};
    return api.client
        .subscribe(xmtp.SubscribeRequest(contentTopics: convoByTopic.keys))
        .where((e) => convoByTopic.containsKey(e.contentTopic))
        .asyncMap((e) => _decodedFromMessage(
              convoByTopic[e.contentTopic]!,
              xmtp.Message.fromBuffer(e.message),
            ))
        // Remove nulls (which are discarded bad envelopes).
        .where((msg) => msg != null)
        .map((msg) => msg!);
  }

  /// This exposes the stream of ephemeral messages in the [conversations].
  Stream<DecodedMessage> streamEphemeralMessages(
      Iterable<Conversation> conversations) {
    if (conversations.isEmpty) {
      return const Stream.empty();
    }
    var convoByTopic = {for (var c in conversations) c.ephemeralTopic: c};
    return api.client
        .subscribe(xmtp.SubscribeRequest(contentTopics: convoByTopic.keys))
        .where((e) => convoByTopic.containsKey(e.contentTopic))
        .asyncMap((e) => _decodedFromMessage(
              convoByTopic[e.contentTopic]!,
              xmtp.Message.fromBuffer(e.message),
            ))
        // Remove nulls (which are discarded bad envelopes).
        .where((msg) => msg != null)
        .map((msg) => msg!);
  }

  /// This decrypts and decodes the [xmtp.Message].
  ///
  /// It returns `null` when the message could not be decoded.
  Future<DecodedMessage?> decryptMessage(
    Conversation conversation,
    xmtp.Message msg,
  ) async =>
      _decodedFromMessage(
        conversation,
        msg,
      );

  /// This decrypts and decodes the [xmtp.Message].
  ///
  /// It returns `null` when the message could not be decoded.
  Future<DecodedMessage?> _decodedFromMessage(
    Conversation conversation,
    xmtp.Message msg,
  ) async {
    var signed = await _decryptMessageV2(msg.v2, conversation.invite);

    // Discard the message if the sender key bundle is invalid.
    if (!signed.sender.isValid()) {
      debugPrint('discarding message with invalid sender key bundle');
      return null;
    }

    // Discard the message if the payload is not properly signed.
    var digest = sha256(msg.v2.headerBytes + signed.payload);
    var signer = ecRecover(
      Uint8List.fromList(digest),
      signed.signature.toMsgSignature(),
    );
    if (signer.toEthereumAddress() != signed.sender.pre) {
      debugPrint('discarding message with bad signature');
      return null;
    }
    try {
      return await _createDecodedMessage(msg, signed);
    } catch (err) {
      debugPrint('discarding message that cannot be decoded');
      return null;
    }
  }

  /// This helper sends the [sealed] invite to [_me] and to [peer].
  Future<xmtp.PublishResponse> _sendInvites(
    EthereumAddress peer,
    xmtp.SealedInvitation sealed,
    Int64 timestampNs,
  ) =>
      api.client.publish(xmtp.PublishRequest(
        envelopes: [_me.hex, peer.hex].map(
          (walletAddress) => xmtp.Envelope(
            contentTopic: Topic.userInvite(walletAddress),
            timestampNs: timestampNs,
            message: sealed.writeToBuffer(),
          ),
        ),
      ));

  /// This creates the [DecodedMessage] from the various parts.
  Future<DecodedMessage> _createDecodedMessage(
    xmtp.Message dm,
    xmtp.SignedContent signed,
  ) async {
    var encoded = xmtp.EncodedContent.fromBuffer(signed.payload);
    var decoded = await _codecs.decode(encoded);
    var id = bytesToHex(sha256(dm.writeToBuffer()));
    var header = xmtp.MessageHeaderV2.fromBuffer(dm.v2.headerBytes);
    var sender = signed.sender.wallet;
    var sentAt = header.createdNs.toDateTime();
    return DecodedMessage(
      xmtp.Message_Version.v2,
      sentAt,
      sender,
      encoded,
      decoded.contentType,
      decoded.content,
      id: id,
      topic: header.topic,
    );
  }
}

/// This uses the provided `context` to create a new conversation invitation.
/// To avoid duplicates, it uses the `authKeys`, `peerKeys`, and `context`
/// to consistently generate the topic identifier and encryption key material.
@visibleForTesting
Future<xmtp.InvitationV1> createInviteV1(
  xmtp.PrivateKeyBundle authKeys,
  xmtp.SignedPublicKeyBundle peerKeys,
  xmtp.InvitationV1_Context context,
) async {
  // This mirrors xmtp-js -- see InMemoryKeystore.createInvite()
  var myAddress = authKeys.wallet.hexEip55;
  var theirAddress = peerKeys.wallet.hexEip55;

  var secret = compute3DHSecret(
    createECPrivateKey(authKeys.identity.privateKey),
    createECPrivateKey(authKeys.preKeys.first.privateKey),
    createECPublicKey(peerKeys.identityKey.publicKeyBytes),
    createECPublicKey(peerKeys.preKey.publicKeyBytes),
    myAddress.compareTo(theirAddress) < 0,
  );
  var addresses = [
    myAddress,
    theirAddress,
  ]..sort();
  var msg = (context.conversationId ?? "") + addresses.join(",");
  var topicId = bytesToHex(await calculateMac(utf8.encode(msg), secret));
  var keyMaterial = await deriveKey(
    secret,
    nonce: utf8.encode('__XMTP__INVITATION__SALT__XMTP__'),
    info: utf8.encode(['0', ...addresses].join('|')),
  );
  return xmtp.InvitationV1(
    topic: Topic.messageV2(topicId),
    aes256GcmHkdfSha256: xmtp.InvitationV1_Aes256gcmHkdfsha256(
      keyMaterial: keyMaterial,
    ),
    context: context,
  );
}

/// This uses `keys` to encrypt the `invite` to `recipient`.
/// It derives the 3DH secret and uses that to encrypt the ciphertext.
@visibleForTesting
Future<xmtp.SealedInvitation> encryptInviteV1(
  xmtp.PrivateKeyBundle keys,
  xmtp.SignedPublicKeyBundle recipient,
  xmtp.InvitationV1 invite,
  Int64 createdNs,
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
    createdNs: createdNs,
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
@visibleForTesting
Future<xmtp.MessageV2> encryptMessageV2(
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
@visibleForTesting
Future<xmtp.SignedContent> signContent(
  xmtp.PrivateKeyBundle keys,
  xmtp.MessageHeaderV2 header,
  xmtp.EncodedContent content,
) async {
  var headerBytes = header.writeToBuffer();
  var payload = content.writeToBuffer();
  var digest = sha256(headerBytes + payload);
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
