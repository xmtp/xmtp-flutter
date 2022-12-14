import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:retry/retry.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp/xmtp.dart' as xmtp;

import 'database/database.dart';

/// The ambient [Session] that is used throughout the app.
/// See [initSession] and usage throughout `hooks.dart`.
late Session session;

/// Initialize the ambient [session] for use throughout the app.
///
/// This creates an [xmtp.Client] connected to the local network.
/// TODO: demo more configuration here
Future<Session> initSession(Credentials wallet) async {
  var api = xmtp.Api.create();
  var client = await xmtp.Client.createFromWallet(api, wallet);
  var database = Database.create(client);
  await database.clear();
  debugPrint("Client initialized: ${wallet.address.hexEip55}");
  return session = Session(client, database);
}

/// Manages conversations and messages with streaming updates.
///
/// This uses the [Database] and [xmtp.Client] to manage the local storage
/// of conversations and messages. It also exposes streams that can be used
/// to watch for changes.
///
/// When listeners are added to the streams, the [Session] will start
/// streaming the corresponding data from the remote network.
class Session {
  final xmtp.Client _client;
  final Database _db;

  /// Streams from our local database.
  ///
  /// When someone starts listening to these stream then this
  /// class starts listening to the corresponding API stream.
  /// And when someone stops listening to these then this class
  /// closes the corresponding API stream.
  late StreamController<List<xmtp.Conversation>> _dbStreamConversations;
  late Map<String, StreamController<xmtp.Conversation?>>
      _dbStreamConversationByTopic;
  late Map<String, StreamController<List<xmtp.DecodedMessage>>>
      _dbStreamMessagesByTopic;

  /// Streams from the remote API.
  ///
  /// These are activated when someone starts listening to the
  /// corresponding database stream. We close these when nobody
  /// else is listening to the corresponding database stream.
  ///
  /// When one of these errors, but someone is still listening
  /// to the corresponding database stream, then we attempt to
  /// recover the remote stream.
  StreamSubscription<xmtp.Conversation>? _apiStreamConversations;
  final Map<String, StreamSubscription<xmtp.DecodedMessage>>
      _apiStreamMessagesByTopic = {};

  /// Manages recovery attempts for remote streams that fail.
  final _Recovery _recovery = _Recovery();

  Session(this._client, this._db) {
    _dbStreamConversations = StreamController.broadcast(
      onListen: _onListenConversations,
      onCancel: _onCancelConversations,
    )..addStream(_db.selectConversations().watch());
    _dbStreamConversationByTopic = {};
    _dbStreamMessagesByTopic = {};
  }

  EthereumAddress get me => _client.address;

  /// Finds saved list of conversations.
  Future<List<xmtp.Conversation>> findConversations() =>
      _db.selectConversations().get();

  /// Watch a stream that emits the list of conversations.
  Stream<List<xmtp.Conversation>> watchConversations() =>
      _dbStreamConversations.stream;

  /// Finds the [xmtp.DecodedMessage]s for the given [topic] in our local database.
  Future<List<xmtp.DecodedMessage>> findMessages(String topic) =>
      _db.selectMessages(topic).get();

  /// Watch a stream that emits the list of messages in the [topic] conversation.
  Stream<List<xmtp.DecodedMessage>> watchMessages(String topic) {
    if (!_dbStreamMessagesByTopic.containsKey(topic)) {
      _dbStreamMessagesByTopic[topic] = StreamController.broadcast(
        onListen: () => _onListenMessages(topic),
        onCancel: () => _onCancelMessages(topic),
      )..addStream(_db.selectMessages(topic).watch());
    }
    return _dbStreamMessagesByTopic[topic]!.stream;
  }

  /// Finds the [xmtp.Conversation] for the given [topic] in our local database.
  Future<xmtp.Conversation?> findConversation(String topic) =>
      _db.selectConversation(topic).getSingleOrNull();

  /// Watches the [xmtp.Conversation] for the given [topic] in our local database.
  Stream<xmtp.Conversation?> watchConversation(String topic) {
    if (!_dbStreamConversationByTopic.containsKey(topic)) {
      _dbStreamConversationByTopic[topic] = StreamController.broadcast()
        ..addStream(_db.selectConversation(topic).watchSingleOrNull());
    }
    return _dbStreamConversationByTopic[topic]!.stream;
  }

  Future<int> findNewMessageCount(String topic) =>
      _db.selectUnreadMessageCount(topic).getSingle();

  Stream<int> watchNewMessageCount(String topic) =>
      _db.selectUnreadMessageCount(topic).watchSingle();

  Future<int> findTotalNewMessageCount() =>
      _db.selectTotalUnreadMessageCount().getSingle();

  Stream<int> watchTotalNewMessageCount() =>
      _db.selectTotalUnreadMessageCount().watchSingle();

  Future<void> updateLastOpenedAt(String topic) =>
      _db.updateLastOpenedAt(topic);

  /// Sends the given [message] to the given [topic].
  Future<xmtp.DecodedMessage> sendMessage(
    String topic,
    Object content, {
    xmtp.ContentTypeId? contentType,
  }) async {
    // First get the conversation.
    var convo = await findConversation(topic);
    // Send the message to the network.
    var msg = await _client.sendMessage(
      convo!,
      content,
      contentType: contentType,
    );
    // Optimistically insert the message into the local database.
    // When the network yields the real message it will be insertOrIgnored.
    await _db.saveMessages([msg]);
    return msg;
  }

  /// Refreshes the messages in the conversation identified by [topic].
  ///
  /// This is called automatically when the first listener subscribes to
  /// [watchMessages] for the [topic]. And it can be called explicitly.
  ///
  /// Note: this will notify all listeners to [watchMessages] for the [topic].
  Future<List<xmtp.DecodedMessage>> refreshMessages(
      xmtp.Conversation convo) async {
    var messages = await _client.listMessages(convo);
    await _db.saveMessages(messages);
    return messages;
  }

  /// Refreshes the list of all conversations from the remote API.
  ///
  /// This is called automatically when the first listener subscribes to
  /// [watchConversations]. And it can be called explicitly (e.g. when a user
  /// pulls down to refresh the listing of conversations).
  ///
  /// Note: these updates are broadcast to all listeners to [watchConversations].
  Future<List<xmtp.Conversation>> refreshConversations() async {
    var conversations = await _client.listConversations();
    await _db.saveConversations(conversations);
    return conversations;
  }

  /// When the listeners to [_dbStreamConversations] goes from zero to 1.
  void _onListenConversations() async {
    _apiStreamConversations ??= _client.streamConversations().listen(
      (convo) {
        _db.saveConversations([convo]);
      },
      onError: (e) {
        _apiStreamConversations?.cancel();
        _apiStreamConversations = null;
        if (_dbStreamConversations.hasListener) {
          _recovery.attempt("conversations", _onListenConversations);
        }
      },
    );
    await refreshConversations();
  }

  /// When the listeners to [_dbStreamConversations] goes from 1 to zero.
  void _onCancelConversations() {
    _recovery.cancel("conversations");
    _apiStreamConversations?.cancel();
    _apiStreamConversations = null;
  }

  /// When listeners to `_dbStreamMessagesByTopic[topic]` goes from zero to 1.
  void _onListenMessages(String topic) async {
    var convo = await _db.selectConversation(topic).getSingleOrNull();
    _apiStreamMessagesByTopic[topic] ??= _client.streamMessages(convo!).listen(
      (msg) {
        _db.saveMessages([msg]);
      },
      onError: (e) {
        _apiStreamMessagesByTopic[topic]?.cancel();
        _apiStreamMessagesByTopic.remove(topic);
        if (_dbStreamMessagesByTopic[topic]?.hasListener ?? false) {
          _recovery.attempt("messages-$topic", () => _onListenMessages(topic));
        }
      },
    );
    await refreshMessages(convo!);
  }

  /// When listeners to `_dbStreamMessagesByTopic[topic]` goes from 1 to zero.
  void _onCancelMessages(String topic) {
    _recovery.cancel("messages-$topic");
    _apiStreamMessagesByTopic[topic]?.cancel();
    _apiStreamMessagesByTopic.remove(topic);
  }
}

/// Manager of recover attempts that enforces exponential backoff.
///
/// This allows attempts to recover to happen eventually,
/// but not too aggressively.
///
/// It tracks the number of recent attempts and uses that as the
/// exponent when delaying the next attempt.
///
/// All attempts are uniquely named and can be later cancelled by name.
class _Recovery {
  final Map<String, Timer> _attempts = {};
  final RetryOptions _config = const RetryOptions();

  /// This is an expiring stack whose height is the number of recent attempts.
  /// See [_incrementRecentCount].
  final List<DateTime> _recentStack = [];

  /// Attempts the named recovery method after some backoff-dependent delay.
  ///
  /// The delay is calculated using exponential backoff where the number of
  /// streams that have recently attempted to recover is used as the exponent.
  ///
  /// The maximum delay is 30 seconds.
  /// See [RetryOptions] from https://pub.dev/packages/retry
  void attempt(String name, void Function() doRecovery) =>
      _attempts[name] ??= Timer(_config.delay(_incrementRecentCount()), () {
        _attempts.remove(name);
        doRecovery();
      });

  /// Cancel the named recovery attempt.
  void cancel(String name) => _attempts.remove(name)?.cancel();

  /// Add to the number of recent attempts and return the current count.
  ///
  /// This maintains the expiring count of recent attempts.
  /// "Recent" means during the last [maxDelay].
  ///
  /// The result will never exceed [maxAttempts].
  int _incrementRecentCount() {
    var now = DateTime.now();
    _recentStack
      ..insert(0, now)
      // Remove all not-recent attempts.
      ..removeWhere((t) => t.isBefore(now.subtract(_config.maxDelay)))
      // And also trim it to the maximum count.
      ..length = min(_recentStack.length, _config.maxAttempts);
    return _recentStack.length;
  }
}
