import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

/// This defines the interface for a content codec of a particular type [T].
/// It is responsible for knowing how to [encode] the content [T].
/// And it is responsible for knowing how to [decode] the [EncodedContent].
abstract class Codec<T extends Object> {
  /// This identifies the flavor of content this codec can handle.
  /// It advertises the ability to be responsible for the specified
  /// [ContentTypeId.authorityId]/[ContentTypeId.typeId].
  xmtp.ContentTypeId get contentType;

  /// This is called to decode the content captured by [encoded].
  Future<T> decode(xmtp.EncodedContent encoded);

  /// This is called to encode the content
  Future<xmtp.EncodedContent> encode(T decoded);
}
