import 'package:web3dart/credentials.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'common/api.dart';
import 'auth.dart';
import 'contact.dart';
import 'content/codec_registry.dart';
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
class Client implements ContentDecoder {
  final EthereumAddress address;

  xmtp.PrivateKeyBundle get keys => _auth.keys;

  final ConversationManager _conversations;
  final AuthManager _auth;
  final ContactManager _contacts;
  final CodecRegistry _codecs;

  Client._(
    this.address,
    this._conversations,
    this._auth,
    this._contacts,
    this._codecs,
  );

  /// This creates a new [Client] instance using the [wallet] to
  /// trigger signature prompts to acquire user authentication keys.
  static Future<Client> createFromWallet(
    Api api,
    Credentials wallet,
  ) async {
    var address = await wallet.extractAddress();
    var client = await _createUninitialized(api, address);
    await client._auth.authenticateWithCredentials(wallet);
    await client._contacts.ensureSavedContact(client._auth.keys);
    return client;
  }

  /// This creates a new [Client] using the saved [keys] from a
  /// previously successful authentication.
  static Future<Client> createFromKeys(
    Api api,
    xmtp.PrivateKeyBundle keys,
  ) async {
    var address = keys.wallet;
    var client = await _createUninitialized(api, address);
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
  ) async {
    var auth = AuthManager(address, api);
    var contacts = ContactManager(api);
    var codecs = CodecRegistry();
    codecs.registerCodec(TextCodec());
    // TODO: codecs.registerCodec(CompositeCodec(codecs));
    var v1 = ConversationManagerV1(address, api, auth, codecs, contacts);
    var v2 = ConversationManagerV2(address, api, auth, codecs, contacts);
    var conversations = ConversationManager(contacts, v1, v2);
    return Client._(
      address,
      conversations,
      auth,
      contacts,
      codecs,
    );
  }

  /// This lists all the [Conversation]s for the user.
  Future<List<Conversation>> listConversations() =>
      _conversations.listConversations();

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

  /// This lists messages sent to the [conversation].
  // TODO: support listing params per js-lib
  Future<List<DecodedMessage>> listMessages(
    Conversation conversation,
  ) =>
      _conversations.listMessages(conversation);

  /// This exposes a stream of new messages sent to the [conversation].
  Stream<DecodedMessage> streamMessages(Conversation conversation) =>
      _conversations.streamMessages(conversation);

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

  /// This uses all registered codecs to decode the [encoded] content.
  ///
  /// Decoding happens automatically when you [listMessages] or [streamMessages].
  /// This method is exposed to help support offline storage of the
  /// otherwise unwieldy content.
  /// See note re "Offline Storage" atop [DecodedMessage].
  @override
  Future<DecodedContent> decodeContent(xmtp.EncodedContent encoded) =>
      _codecs.decodeContent(encoded);
}
