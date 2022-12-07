import 'package:async/async.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import '../contact.dart';
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
  final ContactManager _contacts;
  final ConversationManagerV1 _v1;
  final ConversationManagerV2 _v2;

  ConversationManager(this._contacts, this._v1, this._v2);

  /// This creates or resumes a conversation with [address].
  /// This throws if [address] is not on the XMTP network.
  Future<Conversation> newConversation(
    String address, {
    xmtp.InvitationV1_Context? context,
  }) async {
    context ??= xmtp.InvitationV1_Context();
    var peerContacts = await _contacts.getUserContacts(address);
    if (peerContacts.isEmpty) {
      throw StateError("recipient $address is not on the XMTP network");
    }
    // We only check for an ongoing V1 when it includes no `conversationId`.
    if (!context.hasConversationId()) {
      var ongoing = await _v1.findConversation(address);
      if (ongoing != null) {
        return ongoing;
      }
    }
    var ongoing = await _v2.findConversation(address, context);
    if (ongoing != null) {
      return ongoing;
    }
    return _v2.newConversation(address, context);
  }

  /// This lists all [Conversation]s for the user.
  /// TODO: consider a more thoughtful sorting of v1/v2
  Future<List<Conversation>> listConversations() async {
    var invites = await _v2.listConversations();
    var intros = await _v1.listConversations();
    return [...invites, ...intros];
  }

  /// This exposes a stream of all new [Conversation]s for the user.
  Stream<Conversation> streamConversations() {
    return StreamGroup.merge([
      _v1.streamConversations(),
      _v2.streamConversations(),
    ]);
  }
}
