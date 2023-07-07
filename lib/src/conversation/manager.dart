import 'package:async/async.dart';
import 'package:web3dart/credentials.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import '../common/topic.dart';
import '../contact.dart';
import '../content/decoded.dart';
import 'conversation.dart';
import 'conversation_v1.dart';
import 'conversation_v2.dart';

/// This combines [_v1] and [_v2] conversation managers into
/// a single unified [Conversation].
///
/// This is responsible for merging listings across v1 and v2.
/// See [listConversations], [streamConversations]
///
/// And it is responsible for finding ongoing conversations
/// when they could exist across either v1 or v2.
/// See [newConversation]
class ConversationManager {
  final EthereumAddress _me;
  final ContactManager _contacts;
  final ConversationManagerV1 _v1;
  final ConversationManagerV2 _v2;

  ConversationManager(this._me, this._contacts, this._v1, this._v2);

  /// This creates or resumes a conversation with [address].
  /// This throws if [address] is not on the XMTP network.
  Future<Conversation> newConversation(
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
  ]) async {
    var invites = await _v2.listConversations(start, end, limit, sort);
    var intros = await _v1.listConversations(start, end, limit, sort);
    return [...invites, ...intros];
  }

  /// This exposes a stream of all new [Conversation]s for the user.
  Stream<Conversation> streamConversations() {
    return StreamGroup.merge([
      _v1.streamConversations(),
      _v2.streamConversations(),
    ]);
  }

  /// This lists the messages in [conversations].
  Future<List<DecodedMessage>> listMessages(
    Iterable<Conversation> conversations, [
    DateTime? start,
    DateTime? end,
    int? limit,
    xmtp.SortDirection? sort,
  ]) async {
    var cv1 = conversations.where((c) => c.version == xmtp.Message_Version.v1);
    var cv2 = conversations.where((c) => c.version == xmtp.Message_Version.v2);
    var messages = await Future.wait([
      _v1.listMessages(cv1, start, end, limit, sort),
      _v2.listMessages(cv2, start, end, limit, sort),
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
  ) async =>
      conversation.version == xmtp.Message_Version.v1
          ? _v1.decryptMessage(conversation, msg)
          : _v2.decryptMessage(conversation, msg);

  /// This exposes a stream of new messages in [conversations].
  Stream<DecodedMessage> streamMessages(
    Iterable<Conversation> conversations,
  ) =>
      StreamGroup.merge([
        _v1.streamMessages(
            conversations.where((c) => c.version == xmtp.Message_Version.v1)),
        _v2.streamMessages(
            conversations.where((c) => c.version == xmtp.Message_Version.v2)),
      ]);

  /// This sends [content] as a message to [conversation].
  Future<DecodedMessage> sendMessage(
    Conversation conversation,
    Object content, {
    xmtp.ContentTypeId? contentType,
  }) =>
      conversation.version == xmtp.Message_Version.v1
          ? _v1.sendMessage(conversation, content, contentType: contentType)
          : _v2.sendMessage(conversation, content, contentType: contentType);

  /// This sends the [encoded] message to the [conversation].
  /// If it cannot be decoded then it still sends but this returns `null`.
  Future<DecodedMessage?> sendMessageEncoded(
    Conversation conversation,
    xmtp.EncodedContent encoded,
  ) =>
      conversation.version == xmtp.Message_Version.v1
          ? _v1.sendMessageEncoded(conversation, encoded)
          : _v2.sendMessageEncoded(conversation, encoded);
}
