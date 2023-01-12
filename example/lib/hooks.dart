import 'package:async/async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart' as fh;
import 'package:quiver/cache.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp/xmtp.dart' as xmtp;
import 'package:http/http.dart' as http;

import 'config.dart';
import 'session.dart';
import 'ens.dart';

/// Helpful hooks used throughout the app.
///
/// See https://pub.dev/packages/flutter_hooks
/// and https://medium.com/@dan_abramov/making-sense-of-react-hooks-fdbde8803889

/// The configured user's address.
EthereumAddress useMe() => session.me;

var _web3 = Web3Client(ethRpcUrl, http.Client());
var _addressNames = MapCache<EthereumAddress, String>.lru(maximumSize: 100);

/// This returns a name for the [address].
/// If there is no ENS name it uses an abbreviation of the [address] hex.
String useAddressName(EthereumAddress? address) {
  var hex = address?.hexEip55 ?? "";
  var abbreviated =
      hex.isEmpty ? "" : "${hex.substring(0, 6)}…${hex.substring(38)}";
  var lookup = address == null
      ? Future.value(null)
      : _addressNames.get(
          address,
          ifAbsent: (address) =>
              _web3.lookupAddress(address).then((name) => name ?? ""),
        );
  var name = fh.useFuture(lookup, initialData: abbreviated);
  if ((name.data ?? "").isEmpty) {
    return abbreviated;
  }
  return name.data!;
}

/// The list of all conversations.
///
/// This updates whenever new conversations arrive.
///
/// This causes the remote list of conversations to be
/// streamed by the [Session] while the hooked widget is active.
AsyncSnapshot<List<xmtp.Conversation>> useConversationList() =>
    _useLookupStream(
      () => session.findConversations(),
      () => session.watchConversations(),
    );

/// The details of a single conversation.
AsyncSnapshot<xmtp.Conversation?> useConversation(String topic) =>
    _useLookupStream(
      () => session.findConversation(topic),
      () => session.watchConversation(topic),
      [topic],
    );

/// The list of messages in a conversation.
///
/// This updates whenever a new message in this [topic] arrives.
///
/// This causes the remote [topic] to be streamed by the [Session]
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
AsyncSnapshot<Future<List<xmtp.DecodedMessage>> Function()?>
    useMessagesRefresher(String topic) {
  var convo = useConversation(topic);
  return AsyncSnapshot.withData(convo.connectionState,
      convo.hasData ? () => session.refreshMessages(convo.data!) : null);
}

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
