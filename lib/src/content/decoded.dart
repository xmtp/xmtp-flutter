import 'package:web3dart/credentials.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

/// This represents a fully decoded message.
/// It attempts to give uniform shape to v1 and v2 messages.
///
/// Offline Storage
/// ---------------
/// Beyond ordinary offline storage concerns (secure the database, etc),
/// here are some tips for storing and indexing messages.
///
/// The [id] is a good message identifier for local storage purposes.
///  -> Tip: consider [id] as your primary key in the local database
///
/// But often you won't have an [id], instead you'll have a conversation
/// and want to list the messages sequentially.
/// To support this you'll want to key by the [topic] and [sentAt] together.
///  -> Tip: consider [topic]+[sentAt] as an index in the local database.
///
/// Storing the decoded [content] is difficult because it can be any type.
/// Instead you'll want to store the [encoded] content because it can be
/// reliably serialized. Later, you can decode it using [Client.decodeContent].
///  -> Tip: store the encoded content using `encoded.writeToBuffer()`
///
/// See the example app for a demonstration of the overall approach.
class DecodedMessage {
  /// This identifies which type of message this contains.
  /// For the most part, you are safe to ignore this.
  /// This SDK takes pains to help you ignore the distinctions.
  final xmtp.Message_Version version;

  /// A unique identifier for this message.
  /// Tip: this is a good identifier for local caching purposes.
  final String id;

  /// The topic identifier for the parent conversation.
  final String topic;

  /// When the [sender] sent this message.
  final DateTime sentAt;

  /// Who sent the message.
  final EthereumAddress sender;

  /// This identifies the [content]'s type.
  final xmtp.ContentTypeId contentType;

  /// This contains the [content] decoded by all registered codecs.
  ///  e.g. for [contentTypeText], the [content] will be a [String]
  final Object content;

  /// This contains the raw encoded content.
  final xmtp.EncodedContent encoded;

  DecodedMessage(
    this.version,
    this.sentAt,
    this.sender,
    this.encoded,
    this.contentType,
    this.content, {
    required this.id,
    required this.topic,
  });

  @override
  String toString() {
    return 'DecodedMessage{'
        'version: $version, '
        'id: $id, '
        'sender: $sender, '
        'contentType: $contentType}';
  }
}

/// This represents the result of decoding content.
/// See [Client.decodeContent].
class DecodedContent {
  final xmtp.ContentTypeId contentType;
  final Object content;

  DecodedContent(this.contentType, this.content);
}
