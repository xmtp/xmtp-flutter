import 'package:web3dart/credentials.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import '../content/decoded.dart';

/// This represents an ongoing conversation.
/// It exposes methods to [listMessages] and [send] them.
///
/// And it exposes a [streamMessages] that emits new messages as they arrive.
///
/// It attempts to give uniform shape to v1 and v2 conversations.
abstract class Conversation {
  /// This indicates whether this a v1 or v2 conversation.
  xmtp.Message_Version get version;

  /// This contains any additional conversation context.
  /// NOTE: this will be empty for V1 conversations.
  ConversationContext get context;

  /// This is the address for me, the configured client user.
  EthereumAddress get me;

  /// This is the address of the peer that I am talking to.
  EthereumAddress get peer;

  /// When the conversation was first created.
  DateTime get createdAt;

  /// This is the underlying unique topic name for this conversation.
  /// NOTE: this is a good identifier for local caching purposes.
  String get topic;

  /// This lists messages sent to this conversation.
  // TODO: support listing params per js-lib
  Future<List<DecodedMessage>> listMessages();

  /// This exposes a streams of new messages sent to this conversation.
  Stream<DecodedMessage> streamMessages();

  /// This sends a new message to this conversation.
  /// It returns the [DecodedMessage] to simplify optimistic local updates.
  ///  e.g. you can display the [DecodedMessage] immediately
  ///       without having to wait for it to come back down the stream.
  Future<DecodedMessage> send(
    Object content, {
    xmtp.ContentTypeId? contentType,
  });

  @override
  String toString() {
    return 'Conversation{version:$version me:$me peer:$peer topic:$topic}';
  }
}

/// This contains any additional conversation context from the invitation.
class ConversationContext {
  final String conversationId;
  final Map<String, String> metadata;

  ConversationContext(this.conversationId, this.metadata);
}
