import 'package:example/api.dart';
import 'package:example/session/isolate.dart';
import 'package:flutter/widgets.dart';
import 'package:quiver/check.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web3dart/credentials.dart';
import 'package:xmtp/xmtp.dart' as xmtp;

import '../codecs.dart';
import '../database/database.dart';

final ForegroundSession session = ForegroundSession.create();

/// This exposes XMTP data to the foreground.
/// It pulls/watches data from the [Database].
/// And it sends commands to the background [XmtpIsolate].
class ForegroundSession extends ChangeNotifier {
  bool initialized = false;
  EthereumAddress? me;
  final Database _db;

  ForegroundSession(this._db);

  ForegroundSession.create() : this(Database.connect());

  /// Commands sent to the background isolate

  /// Refreshes the messages in the conversation identified by [topic].
  Future<int> refreshMessages(List<String> topics, {DateTime? since}) =>
      XmtpIsolate.get().command("refreshMessages", args: [topics, since]);

  /// Refreshes the list of all conversations from the remote API.
  Future<int> refreshConversations({DateTime? since}) =>
      XmtpIsolate.get().command("refreshConversations", args: [since]);

  /// Whether or not we can send messages to [address].
  Future<bool> canMessage(String address) =>
      XmtpIsolate.get().command("canMessage", args: [address]);

  /// Starts a conversation with [address].
  /// Returns the conversation `topic` identifier.
  Future<String> newConversation(
    String address, {
    String conversationId = '',
    Map<String, String> metadata = const {},
  }) =>
      XmtpIsolate.get().command("newConversation",
          args: [address, conversationId, metadata]);

  /// Sends [content] to the conversation [topic].
  /// Returns the message `id`.
  Future<String> sendMessage(
    String topic,
    Object content, {
    xmtp.ContentTypeId? contentType,
  }) async =>
      XmtpIsolate.get().command("sendMessage", args: [
        topic,
        (await codecs.encode(xmtp.DecodedContent(
          contentType ?? xmtp.contentTypeText,
          content,
        )))
      ]);

  /// Finds saved list of conversations.
  Future<List<xmtp.Conversation>> findConversations() =>
      _db.selectConversations().get();

  /// Watch a stream that emits the list of conversations.
  Stream<List<xmtp.Conversation>> watchConversations() =>
      _db.selectConversations().watch();

  /// Finds the [xmtp.DecodedMessage]s for the given [topic] in our local database.
  Future<List<xmtp.DecodedMessage>> findMessages(String topic) =>
      _db.selectMessages(topic).get();

  /// Watch a stream that emits the list of messages in the [topic] conversation.
  Stream<List<xmtp.DecodedMessage>> watchMessages(String topic) =>
      _db.selectMessages(topic).watch();

  /// Finds the [xmtp.Conversation] for the given [topic] in our local database.
  Future<xmtp.Conversation?> findConversation(String topic) =>
      _db.selectConversation(topic).getSingleOrNull();

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

  /// This is called on app launch to initialize with saved keys.
  /// When keys are found, this starts the background isolate.
  Future<bool> loadSaved() async {
    checkState(!initialized, message: "already initialized");
    WidgetsFlutterBinding.ensureInitialized();
    var prefs = await SharedPreferences.getInstance();

    if (!prefs.containsKey('xmtp.keys')) {
      debugPrint("no saved keys");
      return false;
    }
    var keys = xmtp.PrivateKeyBundle.fromJson(prefs.getString('xmtp.keys')!);
    debugPrint('using saved keys for ${keys.wallet}');
    await XmtpIsolate.spawn(keys);
    me = keys.wallet;
    initialized = true;
    return true;
  }

  /// This runs when the user attempts to authorize a new wallet.
  /// It uses an ephemeral XMTP client in the foreground to do this.
  /// Once authorized keys are saved, this starts the background isolate.
  Future<bool> authorize(xmtp.Signer wallet) async {
    checkState(!initialized, message: "already initialized");
    try {
      WidgetsFlutterBinding.ensureInitialized();
      var prefs = await SharedPreferences.getInstance();
      var api = createApi();
      var client = await xmtp.Client.createFromWallet(api, wallet);
      me = client.keys.wallet;  // Update the wallet address
      initialized = true;  // Update the session state
   
      await prefs.setString("xmtp.keys", client.keys.writeToJson());
      await XmtpIsolate.spawn(client.keys);
      notifyListeners();
      
      return true;
    } catch (err) {
      return false;
    }
  }

  /// This runs when the user logs out.
  /// It kills the background isolate, clears their authorized keys, and
  /// empties the database.
  Future<void> clear() async {
    await XmtpIsolate.kill();
    var prefs = await SharedPreferences.getInstance();
    await prefs.remove('xmtp.keys');
    await _db.clear();
    initialized = false;
    notifyListeners();
  }
}
