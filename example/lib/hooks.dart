import 'package:async/async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart' as fh;
import 'package:web3dart/web3dart.dart';
import 'package:xmtp/xmtp.dart' as xmtp;
import 'session/foreground_session.dart';

/// Helpful hooks used throughout the app.
///
/// See https://pub.dev/packages/flutter_hooks
/// and https://medium.com/@dan_abramov/making-sense-of-react-hooks-fdbde8803889

/// The configured user's address.
EthereumAddress? useMe() => session.me;

/// The list of all conversations.
///
/// This updates whenever new conversations arrive.
///
/// This causes the remote list of conversations to be
/// streamed by the [ForegroundSession] while the hooked widget is active.
AsyncSnapshot<List<xmtp.Conversation>> useConversationList() =>
    _useLookupStream(
      () => session.findConversations(),
      () => session.watchConversations(),
    );

/// The details of a single conversation.
AsyncSnapshot<xmtp.Conversation?> useConversation(String topic) => fh
    .useFuture(fh.useMemoized(() => session.findConversation(topic), [topic]));

/// The list of messages in a conversation.
///
/// This updates whenever a new message in this [topic] arrives.
///
/// This causes the remote [topic] to be streamed by the [ForegroundSession]
/// while the hooked widget is active.
AsyncSnapshot<List<xmtp.DecodedMessage>> useMessages(String topic) =>
    _useLookupStream(
      () => session.findMessages(topic),
      () => session.watchMessages(topic),
      [topic],
    );

/// The last message in a conversation.
///
/// This updates whenever a new message in this [topic] arrives.
AsyncSnapshot<xmtp.DecodedMessage?> useLastMessage(String topic) {
  var messages = useMessages(topic);
  return AsyncSnapshot.withData(
      messages.connectionState,
      messages.hasData && messages.data!.isNotEmpty
          ? messages.data!.first
          : null);
}

/// The number of unread messages in a conversation.
///
/// This updates whenever a new message arrives or the conversation is opened.
AsyncSnapshot<int> useNewMessageCount(String topic) => _useLookupStream(
      () => session.findNewMessageCount(topic),
      () => session.watchNewMessageCount(topic),
      [topic],
    );

/// A callable to explicitly refresh the messages in a conversation.
///
/// The returned [Future] completes when the refresh is done.
///
/// Any new messages are added to the database which automatically
/// notifies any relevant listeners.
Future<void> Function() useMessagesRefresher(String topic) =>
    () => session.refreshMessages([topic]);

/// A callable to explicitly refresh the list of conversations.
///
/// The returned [Future] completes when the refresh is done.
///
/// Any new conversations are added to the database which automatically
/// notifies any relevant listeners.
useConversationsRefresher() => session.refreshConversations;

/// A callable to send a message to a conversation.
///
/// The returned [Future] completes when the message is sent.
///
/// The message is optimistically inserted into the local database so
/// any relevant listeners are notified immediately.
useSendMessage() => session.sendMessage;

/// Records that [topic] conversation was read.
///
/// This notifies relevant listeners to clear the unread message count.
useMarkAsOpened(topic) => fh.useEffect(() {
      // Update when the conversation is opened and again when it is closed.
      session.updateLastOpenedAt(topic);
      return () => session.updateLastOpenedAt(topic);
    }, [topic]);

// Helpers

/// Combine a [find] lookup and a [watch] stream into a single stream.
///
/// This gives listeners an initial value (from the [find])
/// and then updates them whenever it changes (from the [watch]).
AsyncSnapshot<T> _useLookupStream<T>(
  Future<T> Function() find,
  Stream<T> Function() watch, [
  List<Object?> keys = const <Object>[],
]) =>
    fh.useStream(fh.useMemoized(
        () => StreamGroup.mergeBroadcast([find().asStream(), watch()]), keys));
