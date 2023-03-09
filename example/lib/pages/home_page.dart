import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../components/address_avatar.dart';
import '../components/address_chip.dart';
import '../hooks.dart';
import '../session/foreground_session.dart';

/// A page showing the list of all conversations for the user.
///
/// It indicates which conversations have new messages.
///
/// It listens to the stream of new conversations.
/// And the user can pull to refresh it.
class HomePage extends HookWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var me = useMe();
    var conversations = useConversationList();
    var refresher = useConversationsRefresher();
    debugPrint('conversations ${conversations.data?.length ?? 0}');
    return Scaffold(
        appBar: AppBar(title: AddressChip(address: me), actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => session.clear(),
          ),
        ]),
        body: RefreshIndicator(
          onRefresh: refresher,
          child: ListView.builder(
            itemBuilder: (context, index) => conversations.hasData
                ? ConversationListItem(topic: conversations.data![index].topic)
                : Container(), // TODO: use shimmering skeleton
            itemCount: conversations.hasData ? conversations.data!.length : 0,
          ),
        ));
  }
}

/// An item in the list of conversations.
///
/// It previews the most recent message and indicates when it was sent.
///
/// It indicates (via background color) when there are unread messages.
///
/// Tapping it goes to that conversation's page.
class ConversationListItem extends HookWidget {
  final String topic;

  ConversationListItem({Key? key, required this.topic})
      : super(key: Key(topic));

  @override
  Widget build(BuildContext context) {
    var me = useMe();
    var conversation = useConversation(topic);
    var lastMessage = useLastMessage(topic);
    var unreadCount = useNewMessageCount(topic).data ?? 0;
    var content = (lastMessage.data?.content ?? "") as String;
    var meSentLast = (lastMessage.data?.sender == me);
    var lastSentAt = lastMessage.data?.sentAt ?? DateTime.now();
    return ListTile(
      tileColor: unreadCount > 0 ? Colors.grey[200] : null,
      leading: AddressAvatar(address: conversation.data?.peer),
      title: Row(children: [AddressChip(address: conversation.data?.peer)]),
      horizontalTitleGap: 8,
      trailing: Text(DateFormat.jm().format(lastSentAt)),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 12.0),
        child: Text(
          // Preview the most recent message but try to make clear who sent it.
          meSentLast ? "You: $content" : content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      onTap: () => context.goNamed('conversation', params: {'topic': topic}),
    );
  }
}
