import 'package:flutter/foundation.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'decoded.dart';

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

  String? fallback(T content);
}

/// This is a [Codec] that can handle nested generic content.
///
/// These codecs need the full [CodecRegistry] to decode and encode some nested
/// content as part of implementing their own [encode] and [decode].
///
/// See e.g. [CompositeCodec] and [ReplyCodec].
abstract class NestedContentCodec<T extends Object> implements Codec<T> {
  @protected
  late Codec<DecodedContent> registry;

  void setRegistry(Codec<DecodedContent> registry_) {
    registry = registry_;
  }
}
