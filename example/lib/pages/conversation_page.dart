import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:intl/intl.dart';
import 'package:xmtp/xmtp.dart' as xmtp;

import '../components/address_avatar.dart';
import '../components/address_chip.dart';
import '../hooks.dart';

/// A page showing the details of a single conversation.
///
/// It lists the messages in the conversation, and allows
/// the user to send new messages.
///
/// It listens to the stream of new messages.
/// And the user can pull to refresh it.
class ConversationPage extends HookWidget {
  final String topic;

  ConversationPage({Key? key, required this.topic}) : super(key: Key(topic));

  @override
  Widget build(BuildContext context) {
    var sender = useSendMessage();
    var sending = useState(false);
    var messages = useMessages(topic);
    var refresher = useMessagesRefresher(topic);
    var me = useMe();
    var input = useTextEditingController();
    var canSend = useState(false);
    useMarkAsOpened(topic);

    input.addListener(() => canSend.value = input.text.isNotEmpty);
    submitHandler() async {
      sending.value = true;
      await sender(topic, input.text)
          .then((_) => input.clear())
          .whenComplete(() => sending.value = false);
    }

    return Scaffold(
      appBar: AppBar(),
      body: RefreshIndicator(
        onRefresh: refresher,
        child: ListView.builder(
          reverse: true,
          // separatorBuilder: (BuildContext context, int index) => const Divider(color: Colors.brown),
          itemBuilder: (context, index) => MessageListItem(
            message: messages.data![index],
          ),
          itemCount: messages.data?.length ?? 0,
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
              child: AddressAvatar(address: me),
            ),
            Expanded(
              child: TextField(
                controller: input,
                readOnly: sending.value,
                textInputAction: TextInputAction.send,
                onSubmitted: (value) => canSend.value ? submitHandler : null,
                decoration: const InputDecoration(
                  hintText: 'Send a message',
                ),
                minLines: 1,
                maxLines: 6,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              // Disable sending when we can't or when we are already sending.
              onPressed: canSend.value && !sending.value ? submitHandler : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// An item in the conversation's message list.
class MessageListItem extends HookWidget {
  final xmtp.DecodedMessage message;

  MessageListItem({Key? key, required this.message})
      : super(key: Key(message.id));

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: AddressAvatar(address: message.sender),
      title: Row(children: [AddressChip(address: message.sender)]),
      horizontalTitleGap: 8,
      trailing: Text(DateFormat.jm().format(message.sentAt)),
      subtitle: Padding(
        padding: const EdgeInsets.only(left: 12.0),
        child: Text(message.content as String),
      ),
      // onTap: () => context.go('/conversation/$topic'),
    );
  }
}
