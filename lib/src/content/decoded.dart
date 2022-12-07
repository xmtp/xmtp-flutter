import 'package:web3dart/credentials.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

/// This represents a fully decoded message.
/// It attempts to give uniform shape to v1 and v2 messages.
class DecodedMessage {
  final xmtp.Message_Version version;
  final String id;

  final DateTime sentAt;
  final EthereumAddress sender;

  /// Any registered codecs have been applied -- so [content] is of the
  /// corresponding type.
  ///  e.g. for [contentTypeText] the [content] will be a [String]
  final xmtp.ContentTypeId contentType;
  final Object content;

  DecodedMessage(
    this.version,
    this.id,
    this.sentAt,
    this.sender,
    this.contentType,
    this.content,
  );
}

/// This represents the result of asking the registry to decode content.
class DecodedContent {
  final xmtp.ContentTypeId contentType;
  final Object content;

  DecodedContent(this.contentType, this.content);
}
