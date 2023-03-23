import 'dart:async';
import 'package:example/api.dart';
import 'package:flutter/foundation.dart';

import 'package:quiver/collection.dart';
import 'package:quiver/iterables.dart';
import 'package:xmtp/xmtp.dart' as xmtp;

import '../database/database.dart';
import './recovery.dart';

/// Manages conversations and messages with streaming updates.
///
/// This uses the [Database] and [xmtp.Client] to manage the local storage
/// of conversations and messages.
///
/// It can explicitly [refreshMessages] or [refreshConversations].
/// And it also can be told to [sendMessage].
///
/// It watches two streams for updates:
///  - new conversations [_conversationStream]
///  - new messages [_messageStream]
class BackgroundManager {
  final xmtp.Client _client;
  final Database _db;

  /// Streams from the remote API.
  ///
  /// These are activated when someone starts listening to the
  /// corresponding database stream. We close these when nobody
  /// else is listening to the corresponding database stream.
  ///
  /// When one of these errors, but someone is still listening
  /// to the corresponding database stream, then we attempt to
  /// recover the remote stream.
  StreamSubscription<xmtp.Conversation>? _conversationStream;
  StreamSubscription<xmtp.DecodedMessage>? _messageStream;
  final Set<String> _messageStreamTopics = {};

  /// Manages recovery attempts for remote streams that fail.
  final Recovery _recovery = Recovery();

  static Future<BackgroundManager> create(xmtp.PrivateKeyBundle keys) async {
    var client = await xmtp.Client.createFromKeys(createApi(), keys);
    return BackgroundManager(client, Database.connect());
  }

  BackgroundManager(this._client, this._db);

  Future<void> start() async {
    _restartConversationStream();
    _restartMessageStream();

    // Query for any new conversations.
    var lastConversation = await _db.selectLastConversation().getSingleOrNull();
    await refreshConversations(since: lastConversation?.createdAt);
    // Query for any new messages in known conversations.
    var conversations = await _db.selectConversations().get();
    var lastReceivedAt = await _db.selectLastReceivedSentAt().getSingleOrNull();
    await _refreshMessages(conversations, since: lastReceivedAt);
  }

  Future<void> stop() async {
    _stopConversationStream();
    _stopMessageStream();
    _recovery.reset();
  }

  Future<void> clear() async {
    await stop();
    await _db.clear();
    await _client.terminate();
  }

  /// Whether or not we can send messages to [address].
  Future<bool> canMessage(String address) => _client.canMessage(address);

  /// This creates or resumes a [Conversation] with [address].
  Future<xmtp.Conversation> newConversation(
    String address, {
    String conversationId = "",
    Map<String, String> metadata = const <String, String>{},
  }) =>
      _client.newConversation(
        address,
        conversationId: conversationId,
        metadata: metadata,
      );

  /// Sends the given [message] to the given [topic].
  Future<xmtp.DecodedMessage> sendMessage(
    String topic,
    xmtp.EncodedContent encoded,
  ) async {
    // First get the conversation.
    var convo = await _db.selectConversation(topic).getSingleOrNull();
    // Send the message to the network.
    var msg = await _client.sendMessageEncoded(convo!, encoded);
    // Optimistically insert the message into the local database.
    // When the network yields the real message it will be insertOrIgnored.
    await _db.saveMessages([msg]);
    return msg;
  }

  /// Refreshes the messages in the conversation identified by [topic].
  ///
  /// This will notify all database listeners to the [topic].
  Future<int> refreshMessages(
    Iterable<String> topics, {
    DateTime? since,
  }) async {
    Set<String> topicSet = Set.from(topics);
    var conversations = (await _db.selectConversations().get())
        // TODO: do this in the query ^
        .where((c) => topicSet.contains(c.topic));
    return _refreshMessages(
      conversations,
      since: since,
    );
  }

  Future<int> _refreshMessages(
    Iterable<xmtp.Conversation> conversations, {
    DateTime? since,
  }) async {
    var messagesLength = 0;
    for (var conversation in conversations) {
      var messages = await _client.listMessages(
        conversation,
        start: since,
      );
      await _db.saveMessages(messages);
      messagesLength += messages.length;
    }
    return messagesLength;
  }

  /// Refreshes the list of all conversations from the remote API.
  ///
  /// Note: updates are broadcast to listeners who [watchConversations] on the DB.
  Future<int> refreshConversations({DateTime? since}) async {
    if (since == null) {
      var c = await _db.selectLastConversation().getSingleOrNull();
      since = c?.createdAt;
    }
    var conversations = await _client.listConversations(start: since);
    await _db.saveConversations(conversations);
    _nudgeToBackfillEmptyHistories();
    return conversations.length;
  }

  // This slowly iterates through the conversations and ensures that the
  // message history for each has been saved.
  // Note: if there is any messages in the DB for a conversation we assume
  // we have already backfilled its history.
  void _nudgeToBackfillEmptyHistories() async {
    final clock = Stopwatch()..start();
    var conversations = await _db.selectEmptyConversations().get();
    debugPrint('backfill started: (count ${conversations.length})');
    // Split the conversations into batches so we load them in parallel.
    var batches = partition(conversations, 3);
    for (var batch in batches) {
      await Future.wait(batch.map((c) async {
        try {
          await _refreshMessages([c]);
        } catch (e) {
          debugPrint('error refreshing conversations: $e');
        }
      }));
    }
    debugPrint(
        'backfill finished: (count ${conversations.length}) ${clock.elapsedMilliseconds} ms');
  }

  Future<void> _restartConversationStream() async {
    _stopConversationStream();
    _conversationStream = _client.streamConversations().listen(
      (convo) async {
        await _db.saveConversations([convo]);
        await _refreshMessages([convo]);
        _restartMessageStream();
      },
      onError: (e) {
        _stopConversationStream();
        _recovery.attempt("conversations", _restartConversationStream);
      },
    );
  }

  /// This makes sure we're streaming new messages from every conversation.
  ///
  /// If the current [_messageStream] is adequate then this will no-op.
  /// Otherwise it will stop and restart it with the latest topic set.
  void _restartMessageStream() async {
    var convos = await _db.selectConversations().get();
    var topics = Set<String>.from(convos.map((c) => c.topic));
    if (setsEqual(topics, _messageStreamTopics)) {
      // No-op when we're already streaming everything.
      return;
    }
    // Stop any current stream.
    _stopMessageStream();
    if (convos.isEmpty) {
      return;
    }
    // Start the stream w/ the new conversation set.
    _messageStream = _client.streamBatchMessages(convos).listen((msg) async {
      var isFirstMessage =
          await _db.selectLastMessage(msg.topic).getSingleOrNull() == null;
      if (isFirstMessage) {
        // When this is the first message for this topic in the DB
        // we refresh the full conversation history to make sure we have it all.
        // Subsequently we will typically only look for newer messages.
        var convo = await _db.selectConversation(msg.topic).getSingleOrNull();
        _refreshMessages([convo!]);
      }
      _db.saveMessages([msg]);
    }, onError: (e) {
      _stopMessageStream();
      _recovery.attempt("messages", () => _restartMessageStream());
    });
  }

  /// This terminates the current API stream of messages (if any)
  void _stopMessageStream() {
    _recovery.cancel("messages");
    _messageStreamTopics.clear();
    _messageStream?.cancel();
    _messageStream = null;
  }

  /// This terminates the current API stream of conversations (if any)
  void _stopConversationStream() {
    _recovery.cancel("conversations");
    _conversationStream?.cancel();
    _conversationStream = null;
  }
}
