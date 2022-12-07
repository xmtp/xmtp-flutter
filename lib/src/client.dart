import 'package:web3dart/credentials.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'common/api.dart';
import 'auth.dart';
import 'contact.dart';
import 'content/codec_registry.dart';
import 'content/text_codec.dart';
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
class Client {
  final EthereumAddress address;

  xmtp.PrivateKeyBundle get keys => _auth.keys;

  final ConversationManager _conversations;
  final AuthManager _auth;
  final ContactManager _contacts;

  Client(
    this.address,
    this._conversations,
    this._auth,
    this._contacts,
  );

  /// This creates a new [Client] instance using the [wallet] to
  /// trigger signature prompts to acquire user authentication keys.
  static Future<Client> createFromWallet(
    Api api,
    Credentials wallet,
  ) async {
    var address = await wallet.extractAddress();
    var client = await _createUninitialized(api, address);
    await client._authenticateWithCredentials(wallet);
    await client._ensureSavedContact();
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
    await client._authenticateWithKeys(keys);
    await client._ensureSavedContact();
    return client;
  }

  /// This creates a new [Client] for [address] using the [api].
  /// It assembles the graph of dependencies needed by the [Client].
  /// It does not perform authentication nor does it ensure the contact is saved.
  /// See [_authenticateWithCredentials], [_authenticateWithKeys].
  /// See [_ensureSavedContact].
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
    return Client(
      address,
      conversations,
      auth,
      contacts,
    );
  }

  Future<List<Conversation>> listConversations() =>
      _conversations.listConversations();

  Stream<Conversation> streamConversations() =>
      _conversations.streamConversations();

  Future<Conversation> newConversation(
    String address, {
    xmtp.InvitationV1_Context? context,
  }) =>
      _conversations.newConversation(address, context: context);

  /// During construction, this helper authenticates with saved [keys].
  _authenticateWithKeys(xmtp.PrivateKeyBundle keys) =>
      _auth.authenticateWithKeys(keys);

  /// During construction, this helper authenticates with [wallet] prompts.
  _authenticateWithCredentials(Credentials wallet) =>
      _auth.authenticateWithCredentials(wallet);

  /// During construction, this helper ensures the user has a published contact.
  Future<Client> _ensureSavedContact() async {
    var myContacts = await _contacts.getUserContacts(address.hex);
    if (myContacts.isEmpty) {
      await _contacts.saveContact(_auth.keys);
    }
    return this;
  }
}
