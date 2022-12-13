import 'package:web3dart/credentials.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import '../common/topic.dart';

/// This represents an ongoing conversation.
/// It can be provided to [Client] to [listMessages] and [sendMessage].
/// The [Client] also allows you to [streamMessages] from this [Conversation].
///
/// It attempts to give uniform shape to v1 and v2 conversations.
class Conversation {
  /// This indicates whether this a v1 or v2 conversation.
  final xmtp.Message_Version version;

  /// This is the underlying unique topic name for this conversation.
  /// NOTE: this is a good identifier for local caching purposes.
  final String topic;

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

  Conversation.v1(
    this.createdAt, {
    required this.me,
    required this.peer,
  })  : version = xmtp.Message_Version.v1,
        topic = Topic.directMessageV1(me.hex, peer.hex),
        conversationId = "",
        metadata = <String, String>{},
        invite = xmtp.InvitationV1();

  Conversation.v2(
    this.invite,
    this.createdAt, {
    required this.me,
    required this.peer,
  })  : version = xmtp.Message_Version.v2,
        topic = invite.topic,
        conversationId = invite.context.conversationId,
        metadata = invite.context.metadata;

  @override
  String toString() {
    return 'Conversation{version:$version me:$me peer:$peer topic:$topic}';
  }
}
