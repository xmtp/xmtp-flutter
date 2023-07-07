import 'package:web3dart/credentials.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'auth.dart';
import 'common/api.dart';
import 'common/signature.dart';
import 'contact.dart';
import 'content/codec.dart';
import 'content/codec_registry.dart';
import 'content/composite_codec.dart';
import 'content/text_codec.dart';
import 'content/decoded.dart';
import 'conversation/conversation.dart';
import 'conversation/conversation_v1.dart';
import 'conversation/conversation_v2.dart';
import 'conversation/manager.dart';

/// This is the top-level entrypoint to the XMTP flutter SDK.
///
/// This client provides access to every user [Conversation].
/// See [listConversations], [streamConversations].
///
/// It also allows the user to create a new [Conversation].
/// See [newConversation].
///
/// And once a [Conversation] has been acquired, it can be used
/// to [listMessages], [streamMessages], and [sendMessage].
///
/// Creating a [Client] Instance
/// ----------------------------
/// The client has two constructors: [createFromWallet] and [createFromKeys].
///
/// The first time a user uses a new device they should call [createFromWallet].
/// This will prompt them to sign a message that either
///   creates a new identity (if they're new) or
///   enables their existing identity (if they've used XMTP before).
/// When this succeeds it configures the client with a bundle of [keys] that can
/// be stored securely on the device.
/// ```
///   var client = await Client.createFromWallet(wallet);
///   await mySecureStorage.save(client.keys);
/// ```
///
/// The second time a user launches the app they should call [createFromKeys]
/// using the stored [keys] from their previous session.
/// ```
///   var keys = await mySecureStorage.load();
///   var client = await Client.createFromKeys(keys);
/// ```
///
/// Caching / Offline Storage
/// -------
/// The two primary models [Conversation] and [DecodedMessage] are designed
/// with offline storage in mind.
/// See the example app for a demonstration.
/// TODO: consider adding offline storage support to the SDK itself.
///
/// Each [Conversation] is uniquely identified by its [Conversation.topic].
/// And each [DecodedMessage] is uniquely identified by its [DecodedMessage.id].
/// See note re "Offline Storage" atop [DecodedMessage].
///
class Client implements Codec<DecodedContent> {
  final EthereumAddress address;

  xmtp.PrivateKeyBundle get keys => _auth.keys;

  final Api _api;
  final ConversationManager _conversations;
  final AuthManager _auth;
  final ContactManager _contacts;
  final CodecRegistry _codecs;

  Client._(
    this.address,
    this._api,
    this._conversations,
    this._auth,
    this._contacts,
    this._codecs,
  );

  /// This creates a new [Client] instance using the [Signer] to
  /// trigger signature prompts to acquire user authentication keys.
  static Future<Client> createFromWallet(
    Api api,
    Signer wallet, {
    List<Codec> customCodecs = const [],
  }) async {
    var client = await _createUninitialized(api, wallet.address, customCodecs);
    await client._auth.authenticateWithCredentials(wallet);
    await client._contacts.ensureSavedContact(client._auth.keys);
    return client;
  }

  /// This creates a new [Client] using the saved [keys] from a
  /// previously successful authentication.
  static Future<Client> createFromKeys(
    Api api,
    xmtp.PrivateKeyBundle keys, {
    List<Codec> customCodecs = const [],
  }) async {
    var address = keys.wallet;
    var client = await _createUninitialized(api, address, customCodecs);
    await client._auth.authenticateWithKeys(keys);
    await client._contacts.ensureSavedContact(client._auth.keys);
    return client;
  }

  /// This creates a new [Client] for [address] using the [api].
  /// It assembles the graph of dependencies needed by the [Client].
  /// It does not perform authentication nor does it ensure the contact is saved.
  static Future<Client> _createUninitialized(
    Api api,
    EthereumAddress address,
    List<Codec> customCodecs,
  ) async {
    var auth = AuthManager(address, api);
    var contacts = ContactManager(api);
    var codecs = CodecRegistry();
    codecs.registerCodec(TextCodec());
    codecs.registerCodec(CompositeCodec(codecs));
    for (var codec in customCodecs) {
      codecs.registerCodec(codec);
    }
    var v1 = ConversationManagerV1(address, api, auth, codecs, contacts);
    var v2 = ConversationManagerV2(address, api, auth, codecs, contacts);
    var conversations = ConversationManager(address, contacts, v1, v2);
    return Client._(
      address,
      api,
      conversations,
      auth,
      contacts,
      codecs,
    );
  }

  /// Terminate this client.
  ///
  /// Already in progress calls will be terminated. No further calls can be made
  /// using this client.
  Future<void> terminate() async {
    return _api.terminate();
  }

  /// This lists all the [Conversation]s for the user.
  ///
  /// If [start] or [end] are specified then this will only list conversations
  /// created at or after [start] and at or before [end].
  ///
  /// If [limit] is specified then this returns no more than [limit] conversations.
  ///
  /// If [sort] is specified then that will control the sort order.
  Future<List<Conversation>> listConversations({
    DateTime? start,
    DateTime? end,
    int? limit,
    xmtp.SortDirection? sort = xmtp.SortDirection.SORT_DIRECTION_DESCENDING,
  }) =>
      _conversations.listConversations(start, end, limit, sort);

  /// This exposes a stream of new [Conversation]s for the user.
  Stream<Conversation> streamConversations() =>
      _conversations.streamConversations();

  /// This creates or resumes a [Conversation] with [address].
  /// If a [conversationId] is specified then that will
  /// distinguish multiple conversations with the same user.
  /// A new [conversationId] always creates a new conversation.
  ///
  ///  e.g. This creates 2 conversations with the same [friend].
  ///  ```
  ///  var fooChat = await client.newConversation(
  ///    friend,
  ///    conversationId: 'https://example.com/foo',
  ///    metadata: {"title": "Foo Chat"},
  ///  );
  ///  var barChat = await client.newConversation(
  ///    friend,
  ///    conversationId: 'https://example.com/bar',
  ///    metadata: {"title": "Bar Chat"},
  ///  );
  ///  ```
  Future<Conversation> newConversation(
    String address, {
    String conversationId = "",
    Map<String, String> metadata = const <String, String>{},
  }) =>
      _conversations.newConversation(address, conversationId, metadata);

  /// Whether or not we can send messages to [address].
  ///
  /// This will return false when [address] has never signed up for XMTP
  /// or when the message is addressed to the sender (no self-messaging).
  Future<bool> canMessage(String address) async =>
      EthereumAddress.fromHex(address) != this.address &&
      await _contacts.hasUserContacts(address);

  /// This lists messages sent to the [conversation].
  ///
  /// For listing multiple conversations, see [listBatchMessages].
  ///
  /// If [start] or [end] are specified then this will only list messages
  /// sent at or after [start] and at or before [end].
  ///
  /// If [limit] is specified then this returns no more than [limit] messages.
  ///
  /// If [sort] is specified then that will control the sort order.
  Future<List<DecodedMessage>> listMessages(
    Conversation conversation, {
    DateTime? start,
    DateTime? end,
    int? limit,
    xmtp.SortDirection sort = xmtp.SortDirection.SORT_DIRECTION_DESCENDING,
  }) =>
      _conversations.listMessages([conversation], start, end, limit, sort);

  /// This lists messages sent to the [conversations].
  /// This is identical to [listMessages] except it pulls messages from
  /// multiple conversations in a single call.
  Future<List<DecodedMessage>> listBatchMessages(
    Iterable<Conversation> conversations, {
    DateTime? start,
    DateTime? end,
    int? limit,
    xmtp.SortDirection sort = xmtp.SortDirection.SORT_DIRECTION_DESCENDING,
  }) =>
      _conversations.listMessages(conversations, start, end, limit, sort);

  /// This exposes a stream of new messages sent to the [conversation].
  /// For streaming multiple conversations, see [streamBatchMessages].
  Stream<DecodedMessage> streamMessages(Conversation conversation) =>
      _conversations.streamMessages([conversation]);

  /// This exposes a stream of new messages sent to any of the [conversations].
  Stream<DecodedMessage> streamBatchMessages(
          Iterable<Conversation> conversations) =>
      _conversations.streamMessages(conversations);

  /// This sends a new message to the [conversation].
  /// It returns the [DecodedMessage] to simplify optimistic local updates.
  ///  e.g. you can display the [DecodedMessage] immediately
  ///       without having to wait for it to come back down the stream.
  Future<DecodedMessage> sendMessage(
    Conversation conversation,
    Object content, {
    xmtp.ContentTypeId? contentType,
    // TODO: support fallback and compression
  }) =>
      _conversations.sendMessage(
        conversation,
        content,
        contentType: contentType,
      );

  /// This sends the already [encoded] message to the [conversation].
  /// This is identical to [sendMessage] but can be helpful when you
  /// have already encoded the message to send.
  /// If it cannot be decoded then it still sends but this returns `null`.
  Future<DecodedMessage?> sendMessageEncoded(
    Conversation conversation,
    xmtp.EncodedContent encoded,
  ) =>
      _conversations.sendMessageEncoded(conversation, encoded);

  /// These use all registered codecs to decode and encode content.
  ///
  /// This happens automatically when you [listMessages] or [streamMessages]
  /// and also when you [sendMessage].
  ///
  /// These method are exposed to help support offline storage of the
  /// otherwise unwieldy content.
  /// See note re "Offline Storage" atop [DecodedMessage].
  @override
  Future<DecodedContent> decode(xmtp.EncodedContent encoded) =>
      _codecs.decode(encoded);

  @override
  Future<xmtp.EncodedContent> encode(DecodedContent decoded) =>
      _codecs.encode(decoded);

  /// This decrypts a [Conversation] from an `envelope`.
  ///
  /// This decryption happens automatically when you `listConversations`.
  /// But this method exists to enable out-of-band receipt of messages that
  /// can then be decrypted (e.g. when receiving a push notification).
  ///
  /// It returns `null` when the conversation could not be decrypted.
  @override
  Future<Conversation?> decryptConversation(
    xmtp.Envelope envelope,
  ) =>
      _conversations.decryptConversation(envelope);

  /// This decrypts and decodes the `message` belonging to `conversation`.
  ///
  /// This decryption/decoding happens automatically when you `listMessages`.
  /// But this method exists to enable out-of-band receipt of messages that
  /// can then be decrypted (e.g. when receiving a push notification).
  ///
  /// It returns `null` when the message could not be decoded.
  @override
  Future<DecodedMessage?> decryptMessage(
    Conversation conversation,
    xmtp.Message message,
  ) =>
      _conversations.decryptMessage(conversation, message);

  /// This completes the implementation of the [Codec] interface.
  @override
  xmtp.ContentTypeId get contentType => throw UnsupportedError(
        "the Client, as a Codec, does not advertise a single content type",
      );
}
