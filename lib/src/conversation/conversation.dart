import 'dart:typed_data';
import 'package:web3dart/credentials.dart';
import 'package:web3dart/crypto.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import '../common/topic.dart';

/// This represents an ongoing conversation.
/// It can be provided to [Client] to [listMessages] and [sendMessage].
/// The [Client] also allows you to [streamMessages] from this [Conversation].
sealed class Conversation {
  /// This is a unique identifier for this conversation.
  /// NOTE: this is a good identifier for local caching purposes.
  String get id;

  /// When the conversation was first created.
  DateTime get createdAt;
}

/// This represents a group conversation.
class GroupConversation extends Conversation {
  final Uint8List groupId;
  @override
  final DateTime createdAt;

  GroupConversation.v3(this.groupId, this.createdAt);

  @override
  String get id => bytesToHex(groupId);
}

/// This represents a direct message conversation.
///
/// It attempts to give uniform shape to v1 and v2 conversations.
class DirectConversation extends Conversation {
  /// This indicates whether this a v1 or v2 conversation.
  final xmtp.Message_Version version;

  /// This is the underlying unique topic name for this conversation.
  final String topic;

  /// This is the ephemeral message topic for this conversation.
  final String ephemeralTopic;

  /// This distinctly identifies between two addresses.
  /// Note: this will be empty for older v1 conversations.
  final String conversationId;

  /// This contains any additional conversation context.
  /// Note: this will be empty for older v1 conversations.
  final Map<String, String> metadata;

  /// This contains the invitation to this conversation.
  /// Note: this will be empty for older v1 conversations.
  final xmtp.InvitationV1 invite;

  /// This is the address for me, the configured client user.
  final EthereumAddress me;

  /// This is the address of the peer that I am talking to.
  final EthereumAddress peer;

  /// When the conversation was first created.
  final DateTime createdAt;

  DirectConversation.v1(
    this.createdAt, {
    required this.me,
    required this.peer,
  })  : version = xmtp.Message_Version.v1,
        topic = Topic.directMessageV1(me.hex, peer.hex),
        ephemeralTopic =
            Topic.ephemeralMessage(Topic.directMessageV1(me.hex, peer.hex)),
        conversationId = "",
        metadata = <String, String>{},
        invite = xmtp.InvitationV1();

  DirectConversation.v2(
    this.invite,
    this.createdAt, {
    required this.me,
    required this.peer,
  })  : version = xmtp.Message_Version.v2,
        topic = invite.topic,
        ephemeralTopic = Topic.ephemeralMessage(invite.topic),
        conversationId = invite.context.conversationId,
        metadata = invite.context.metadata;

  @override
  String get id => topic;

  @override
  String toString() {
    return 'DirectConversation{version:$version me:$me peer:$peer topic:$topic}';
  }
}

/// Sort and return the sorted list inline
extension ListSorted<T> on List<T> {
  List<T> sorted(int Function(T a, T b) compare) => [...this]..sort(compare);
}
