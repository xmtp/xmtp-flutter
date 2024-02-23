import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:quiver/check.dart';
import 'package:quiver/iterables.dart';
import 'package:web3dart/credentials.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import '../common/api.dart';
import '../common/topic.dart';
import '../contact.dart';
import '../content/decoded.dart';
import 'conversation.dart';
import 'conversation_v1.dart';
import 'conversation_v2.dart';
import 'conversation_v3.dart';

/// This combines [_v1], [_v2], and [_v3] conversation managers into
/// a single unified [Conversation].
///
/// This is responsible for merging listings across v1, v2, and v3.
/// See [listConversations], [streamConversations]
///
/// And it is responsible for finding ongoing conversations
/// when they could exist across either v1 or v2.
/// See [newConversation]
///
/// TODO: doc how to enable v3
/// TODO: doc how to create a group
class ConversationManager {
  final EthereumAddress _me;
  final ContactManager _contacts;
  final ConversationManagerV1 _v1;
  final ConversationManagerV2 _v2;
  final ConversationManagerV3? _v3;

  ConversationManager(this._me, this._contacts, this._v1, this._v2, this._v3);

  /// This creates or resumes a conversation with [address].
  /// This throws if [address] is not on the XMTP network.
  Future<DirectConversation> newConversation(
    String address,
    String conversationId,
    Map<String, String> metadata,
  ) async {
    if (EthereumAddress.fromHex(address) == _me) {
      throw ArgumentError.value(address, 'address',
          'no self-messaging, sender and recipient must be different');
    }
    var peerContacts = await _contacts.getUserContacts(address);
    if (peerContacts.isEmpty) {
      throw StateError("recipient $address is not on the XMTP network");
    }
    // We only check for an ongoing V1 when it includes no `conversationId`.
    if (conversationId.isEmpty) {
      var ongoing = await _v1.findConversation(address);
      if (ongoing != null) {
        return ongoing;
      }
    }
    var context = xmtp.InvitationV1_Context(
      conversationId: conversationId,
      metadata: metadata,
    );
    var ongoing = await _v2.findConversation(address, context);
    if (ongoing != null) {
      return ongoing;
    }
    return _v2.newConversation(address, context);
  }

  /// This lists all [Conversation]s for the user.
  /// TODO: consider a more thoughtful sorting of v1/v2
  Future<List<Conversation>> listConversations([
    DateTime? start,
    DateTime? end,
    int? limit,
    xmtp.SortDirection? sort,
    bool includeGroups = false, // TODO enable by default when we're ready
    bool includeDirects = true,
  ]) async {
    var groups = [];
    var invites = [];
    var intros = [];
    if (includeGroups) {
      groups = await _v3?.listGroups(start, end, limit, sort) ?? [];
    }
    if (includeDirects) {
      invites = await _v2.listConversations(start, end, limit, sort);
      intros = await _v1.listConversations(start, end, limit, sort);
    }
    return [...groups, ...invites, ...intros];
  }

  Future<GroupConversation> createGroup(List<String> addresses) async {
    if (_v3 == null) {
      throw UnsupportedError("groups are not enabled");
    }
    return _v3!.createGroup(addresses);
  }

  /// This exposes a stream of all new [Conversation]s for the user.
  Stream<Conversation> streamConversations([
    bool includeGroups = false, // TODO enable by default when we're ready
    bool includeDirects = true,
  ]) {
    return StreamGroup.merge([]
      ..addAll(includeDirects
          ? [_v1.streamConversations(), _v2.streamConversations()]
          : [])
      ..addAll(includeGroups
          ? [_v3?.streamConversations() ?? const Stream.empty()]
          : []));
  }

  /// This lists the messages in [conversations].
  Future<List<DecodedMessage>> listMessages(
    Iterable<Conversation> conversations, {
    Iterable<Pagination>? paginations,
    DateTime? start,
    DateTime? end,
    int? limit,
    xmtp.SortDirection? sort,
  }) async {
    checkState(
        paginations == null || paginations.length == conversations.length,
        message: 'mismatched pagination/conversation specification count');
    var ps = paginations?.toList() ??
        List.filled(conversations.length, Pagination(start, end, limit, sort));

    // Index the conversations so when we split them up by type we can still
    // pair them with the corresponding Pagination by index.
    var indexed = enumerate(conversations);
    var directs = indexed.where((c) => c.value is DirectConversation);
    var v1 = directs.where((c) =>
        (c.value as DirectConversation).version == xmtp.Message_Version.v1);
    var v2 = directs.where((c) =>
        (c.value as DirectConversation).version == xmtp.Message_Version.v2);
    var v3 = indexed.where((c) => c.value is GroupConversation);
    var messages = await Future.wait([
      _v1.listMessages(
        v1.map((c) => c.value as DirectConversation),
        paginations: v1.map((c) => ps[c.index]),
        sort: sort,
      ),
      _v2.listMessages(
        v2.map((c) => c.value as DirectConversation),
        paginations: v2.map((c) => ps[c.index]),
        sort: sort,
      ),
      _v3?.listMessages(
            v3.map((c) => c.value as GroupConversation),
            paginations: v3.map((c) => ps[c.index]),
            sort: sort,
          ) ??
          Future.value(const <DecodedMessage>[]),
    ]);
    return messages.expand((m) => m).toList();
  }

  /// This decrypts a [Conversation] from an `envelope`.
  ///
  /// It returns `null` when the conversation could not be decrypted.
  Future<Conversation?> decryptConversation(xmtp.Envelope envelope) async {
    if (envelope.contentTopic == Topic.userIntro(_me.hex)) {
      return _v1.decryptConversation(envelope);
    } else if (envelope.contentTopic == Topic.userInvite(_me.hex)) {
      return _v2.decryptConversation(envelope);
    }
    return null;
  }

  /// This decrypts and decodes the `msg`.
  ///
  /// It returns `null` when the message could not be decoded.
  Future<DecodedMessage?> decryptMessage(
    Conversation conversation,
    xmtp.Message msg,
  ) async {
    switch (conversation) {
      case DirectConversation():
        return conversation.version == xmtp.Message_Version.v1
            ? _v1.decryptMessage(conversation, msg)
            : _v2.decryptMessage(conversation, msg);
      case GroupConversation():
        if (_v3 == null) {
          throw UnsupportedError("groups are not enabled");
        }
        // TODO: support explicitly decrypting received messages in v3
        throw UnsupportedError("groups cannot decrypt messages explicitly");
        // TODO: return _v3!.decryptMessage(conversation, msg);
    }
  }

  /// This exposes a stream of new messages in [conversations].
  Stream<DecodedMessage> streamMessages(
    Iterable<Conversation> conversations,
  ) {
    var directs = conversations.whereType<DirectConversation>();
    var groups = conversations.whereType<GroupConversation>();
    return StreamGroup.merge([
        _v1.streamMessages(
            directs.where((c) => c.version == xmtp.Message_Version.v1)),
        _v2.streamMessages(
            directs.where((c) => c.version == xmtp.Message_Version.v2)),
        _v3?.streamMessages(groups) ?? const Stream.empty(),
      ]);
  }

  /// This exposes a stream of ephemeral messages in [conversations].
  Stream<DecodedMessage> streamEphemeralMessages(
    Iterable<Conversation> conversations,
  ) {
    var directs = conversations.whereType<DirectConversation>();
    // TODO: consider if groups support ephemeral messages
    return StreamGroup.merge([
        _v1.streamEphemeralMessages(
            directs.where((c) => c.version == xmtp.Message_Version.v1)),
        _v2.streamEphemeralMessages(
            directs.where((c) => c.version == xmtp.Message_Version.v2)),
      ]);
  }

  /// This sends [content] as a message to [conversation].
  Future<DecodedMessage> sendMessage(
    Conversation conversation,
    Object content, {
    xmtp.ContentTypeId? contentType,
    bool isEphemeral = false,
  }) {
    switch (conversation) {
      case DirectConversation():
        return conversation.version == xmtp.Message_Version.v1
            ? _v1.sendMessage(conversation, content,
                contentType: contentType, isEphemeral: isEphemeral)
            : _v2.sendMessage(conversation, content,
                contentType: contentType, isEphemeral: isEphemeral);
      case GroupConversation():
        if (_v3 == null) {
          throw UnsupportedError("groups are not enabled");
        }
        if (isEphemeral) {
          throw UnsupportedError("groups do not support ephemeral messages");
        }
        return _v3!.sendMessage(
          conversation,
          content,
          contentType: contentType,
        );
    }
  }

  /// This sends the [encoded] message to the [conversation].
  /// If it cannot be decoded then it still sends but this returns `null`.
  Future<DecodedMessage?> sendMessageEncoded(
    Conversation conversation,
    xmtp.EncodedContent encoded, {
    bool isEphemeral = false,
  }) {
    switch (conversation) {
      case DirectConversation():
        return conversation.version == xmtp.Message_Version.v1
      ? _v1.sendMessageEncoded(conversation, encoded, isEphemeral)
          : _v2.sendMessageEncoded(conversation, encoded, isEphemeral);
      case GroupConversation():
        if (_v3 == null) {
          throw UnsupportedError("groups are not enabled");
        }
        return _v3!.sendMessageEncoded(conversation, encoded);
    }
  }}
