import 'dart:typed_data';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:web3dart/credentials.dart';
import 'package:xmtp_bindings_flutter/xmtp_bindings_flutter.dart' as libxmtp;
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;
import 'package:http/http.dart' as http;

import 'auth.dart';
import 'common/api.dart';
import 'common/signature.dart';
import 'contact.dart';
import 'content/attachment_codec.dart';
import 'content/codec.dart';
import 'content/codec_registry.dart';
import 'content/composite_codec.dart';
import 'content/reaction_codec.dart';
import 'content/remote_attachment_codec.dart';
import 'content/reply_codec.dart';
import 'content/text_codec.dart';
import 'content/decoded.dart';
import 'conversation/conversation.dart';
import 'conversation/conversation_v1.dart';
import 'conversation/conversation_v2.dart';
import 'conversation/conversation_v3.dart';
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
  final libxmtp.Client? _v3Client;
  final ConversationManager _conversations;
  final AuthManager _auth;
  final ContactManager _contacts;
  final CodecRegistry _codecs;

  Client._(
    this.address,
    this._api,
    this._v3Client,
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
    bool enableGroups = false,
  }) async {
    var client = await _createUninitialized(
      wallet,
      api,
      wallet.address,
      customCodecs,
      enableV3: enableGroups,
    );
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
    Signer? signer,
    bool enableGroups = false,
  }) async {
    var address = keys.wallet;
    var client = await _createUninitialized(
      signer,
      api,
      address,
      customCodecs,
      enableV3: enableGroups,
    );
    await client._auth.authenticateWithKeys(keys);
    await client._contacts.ensureSavedContact(client._auth.keys);
    return client;
  }

  /// This creates a new [Client] for [address] using the [api].
  /// It assembles the graph of dependencies needed by the [Client].
  /// It does not perform authentication nor does it ensure the contact is saved.
  static Future<Client> _createUninitialized(
    Signer? signer,
    Api api,
    EthereumAddress address,
    List<Codec> customCodecs, {
    bool enableV3 = false,
    // TODO: expose a way for the app to specify these (instead of ephemeral defaults)
    String? dbPath,
    libxmtp.U8Array32? encryptionKey,
  }) async {
    await libxmtp.libxmtpInit();
    var auth = AuthManager(address, api);
    var codecs = CodecRegistry();
    var commonCodecs = <Codec>[
      TextCodec(),
      CompositeCodec(),
      ReplyCodec(),
      ReactionCodec(),
      RemoteAttachmentCodec(),
      AttachmentCodec(),
    ];
    for (var codec in commonCodecs..addAll(customCodecs)) {
      if (codec is NestedContentCodec) {
        codec.setRegistry(codecs);
      }
      codecs.registerCodec(codec);
    }
    var contacts = ContactManager(api, auth);
    // TODO: permit disabling of "legacy" v1/v2 and just use libxmtp/v3
    var v1 = ConversationManagerV1(address, api, auth, codecs, contacts);
    var v2 = ConversationManagerV2(address, api, auth, codecs, contacts);
    ConversationManagerV3? v3;
    libxmtp.Client? v3Client;
    if (enableV3) {
      // TODO: default to path_provider app folder instead of tmp
      dbPath ??= p.join(
        Directory.systemTemp.createTempSync().path,
        "${address.hex}.${api.config.env}.xmtp.db",
      );
      // TODO: default to a consistent/stored key
      encryptionKey ??= libxmtp.U8Array32.init();
      var scheme = api.config.isSecure ? "https": "http";
      var created = await libxmtp.createClient(
        host: "$scheme://${api.config.host}:${api.config.port}",
        isSecure: api.config.isSecure,
        dbPath: dbPath,
        encryptionKey: encryptionKey,
        accountAddress: address.hex,
      );
      v3Client = switch (created) {
        libxmtp.CreatedClient_Ready(field0: var v3Client) => v3Client,
        libxmtp.CreatedClient_RequiresSignature(field0: var req) =>
          signer == null
              ? throw StateError("signer required to initialize client")
              : await req.sign(
                  signature: await signer.signPersonalMessage(req.textToSign),
                ),
      };
      v3 = ConversationManagerV3(address, v3Client, codecs);
    }
    var conversations = ConversationManager(address, contacts, v1, v2, v3);
    return Client._(
      address,
      api,
      v3Client,
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
  /// If [limit] is specified then results are pulled in pages of that size.
  ///
  /// If [sort] is specified then that will control the sort order.
  Future<List<Conversation>> listConversations({
    DateTime? start,
    DateTime? end,
    int? limit,
    xmtp.SortDirection? sort = xmtp.SortDirection.SORT_DIRECTION_DESCENDING,
    @experimental
    bool includeGroups = false, // TODO enable by default when we're ready
    bool includeDirects = true,
  }) =>
      _conversations.listConversations(
        start,
        end,
        limit,
        sort,
        includeGroups,
        includeDirects,
      );

  @experimental
  Future<GroupConversation> createGroup({
    List<String> addresses = const [],
  }) =>
      _v3Client == null
          ? throw UnsupportedError("groups are not enabled")
          : _conversations.createGroup(addresses);

  /// This exposes a stream of new [Conversation]s for the user.
  Stream<Conversation> streamConversations({
    @experimental
    bool includeGroups = false, // TODO enable by default when we're ready
    bool includeDirects = true,
}) =>
      _conversations.streamConversations(
        includeGroups,
        includeDirects,
      );

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
  Future<DirectConversation> newConversation(
    String address, {
    String conversationId = "",
    Map<String, String> metadata = const <String, String>{},
  }) async {
    // Starting a conversation implies allowing an unknown contact.
    if (checkContactConsent(address) == ContactConsent.unknown) {
      await allowContact(address);
    }
    return _conversations.newConversation(address, conversationId, metadata);
  }

  /// Whether or not we can send messages to [address].
  ///
  /// This will return false when [address] has never signed up for XMTP
  /// or when the message is addressed to the sender (no self-messaging).
  Future<bool> canMessage(String address) async =>
      EthereumAddress.fromHex(address) != this.address &&
      await _contacts.hasUserContacts(address);

  /// Indicate that the user does not want to be contacted by [address].
  /// This will be published to the network and added to the local cache.
  Future<bool> denyContact(String address) async =>
      _contacts.deny(_auth.keys, EthereumAddress.fromHex(address));

  /// Indicate that the user does want to be contacted by [address].
  /// This will be published to the network and added to the local cache.
  Future<bool> allowContact(String address) async =>
      _contacts.allow(_auth.keys, EthereumAddress.fromHex(address));

  /// Look-up existing consent for the current user to allow or block [address].
  /// This uses the local cache of contact consent preferences.
  ///   See [refreshContactConsentPreferences] to refresh the cache.
  ///   See [allowContact] and [blockContact] to modify consent.
  ContactConsent checkContactConsent(String address) =>
      _contacts.checkConsent(EthereumAddress.fromHex(address));

  /// Export consents from the local cache for use in a future session.
  /// This aims to allow apps to have immediate access to prior consents
  /// even before the device has network connectivity in a future session.
  CompactConsents exportContactConsents() => _contacts.exportConsents();

  /// Import consents from a prior session to the local cache.
  /// This will not publish them to the network. Instead, this aims to
  /// allow apps to have immediate access to prior consents even before
  /// the device has network connectivity.
  Future<bool> importContactConsents({
    Iterable<String> allowedWalletAddresses = const [],
    Iterable<String> deniedWalletAddresses = const [],
    DateTime? lastRefreshedAt,
  }) =>
      _contacts.importConsents(
        allowedWalletAddresses: allowedWalletAddresses,
        deniedWalletAddresses: deniedWalletAddresses,
        lastRefreshedAt: lastRefreshedAt,
      );

  /// Refresh the local cache of contact consent preferences.
  /// When [fullRefresh] is true then this will rebuild the local cache
  /// by fetching the full history of consent actions.
  /// When [fullRefresh] is false then this will only fetch consent actions
  /// newer than the latest in the cache.
  Future<bool> refreshContactConsentPreferences({bool fullRefresh = false}) =>
      _contacts.refreshConsents(_auth.keys, fullRefresh: fullRefresh);

  /// This downloads the [attachment] and returns the [DecodedContent].
  /// If [downloader] is specified then that will be used to fetch the payload.
  Future<DecodedContent> download(
    RemoteAttachment attachment, {
    RemoteDownloader? downloader,
  }) async {
    downloader ??= (url) => http.readBytes(Uri.parse(url));
    var decrypted = await attachment.download(downloader);
    return decode(decrypted);
  }

  /// This uploads the [attachment] and returns the [RemoteAttachment].
  /// The [uploader] will be used to upload the payload and produce the URL.
  /// It will be uploaded after applying the specified [compression].
  Future<RemoteAttachment> upload(
    Attachment attachment,
    RemoteUploader uploader, {
    xmtp.Compression? compression = xmtp.Compression.COMPRESSION_GZIP,
  }) async {
    var content = DecodedContent(contentTypeAttachment, attachment);
    var encoded = await _codecs.encode(content, compression: compression);
    return RemoteAttachment.upload(attachment.filename, encoded, uploader);
  }

  /// This lists messages sent to the [conversation].
  ///
  /// For listing multiple conversations, see [listBatchMessages].
  ///
  /// If [start] or [end] are specified then this will only list messages
  /// sent at or after [start] and at or before [end].
  ///
  /// If [limit] is specified then results are pulled in pages of that size.
  ///
  /// If [sort] is specified then that will control the sort order.
  Future<List<DecodedMessage>> listMessages(
    Conversation conversation, {
    DateTime? start,
    DateTime? end,
    int? limit,
    xmtp.SortDirection sort = xmtp.SortDirection.SORT_DIRECTION_DESCENDING,
  }) =>
      _conversations.listMessages(
        [conversation],
        start: start,
        end: end,
        limit: limit,
        sort: sort,
      );

  /// This lists messages sent to the [conversations].
  /// This is identical to [listMessages] except it pulls messages from
  /// multiple conversations in a single call.
  Future<List<DecodedMessage>> listBatchMessages(
    Iterable<Conversation> conversations, {
    Iterable<Pagination>? paginations,
    DateTime? start,
    DateTime? end,
    int? limit,
    xmtp.SortDirection sort = xmtp.SortDirection.SORT_DIRECTION_DESCENDING,
  }) =>
      _conversations.listMessages(
        conversations,
        paginations: paginations,
        start: start,
        end: end,
        limit: limit,
        sort: sort,
      );

  /// This exposes a stream of new messages sent to the [conversation].
  /// For streaming multiple conversations, see [streamBatchMessages].
  Stream<DecodedMessage> streamMessages(Conversation conversation) =>
      _conversations.streamMessages([conversation]);

  /// This exposes a stream of ephemeral messages sent to the [conversation].
  Stream<DecodedMessage> streamEphemeralMessages(Conversation conversation) =>
      _conversations.streamEphemeralMessages([conversation]);

  /// This exposes a stream of ephemeral messages sent to any of [conversations].
  Stream<DecodedMessage> streamBatchEphemeralMessages(
          Iterable<Conversation> conversations) =>
      _conversations.streamEphemeralMessages(conversations);

  /// This exposes a stream of new messages sent to any of the [conversations].
  Stream<DecodedMessage> streamBatchMessages(
          Iterable<Conversation> conversations) =>
      _conversations.streamMessages(conversations);

  /// This sends a new message to the [conversation].
  /// It returns the [DecodedMessage] to simplify optimistic local updates.
  ///  e.g. you can display the [DecodedMessage] immediately
  ///       without having to wait for it to come back down the stream.
  /// When [isEphemeral] the message is only sent to [streamEphemeralMessages].
  ///  e.g. so you can send "typing..." or other live indicators
  Future<DecodedMessage> sendMessage(
    Conversation conversation,
    Object content, {
    xmtp.ContentTypeId? contentType,
    bool isEphemeral = false,
    // TODO: support fallback and compression
  }) async {
    // Sending a message implies allowing an unknown contact.
    if (conversation is DirectConversation &&
        checkContactConsent(conversation.peer.hex) == ContactConsent.unknown) {
      await allowContact(conversation.peer.hex);
    }
    return _conversations.sendMessage(
      conversation,
      content,
      contentType: contentType,
      isEphemeral: isEphemeral,
    );
  }

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

  /// This may provide text that can be displayed instead of the content.
  /// It can be used in contexts that do not support rendering a content type.
  @override
  String? fallback(DecodedContent content) => _codecs.fallback(content);
}
