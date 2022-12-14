import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'codec.dart';
import 'decoded.dart';
import 'text_codec.dart';

/// This is a registry of codecs for particular types.
/// It knows how to apply the codecs to [decodeContent] or [encodeContent].
class CodecRegistry implements ContentDecoder {
  final Map<String, Codec> _codecs = {};

  void registerCodec(Codec codec) => _codecs[_key(codec.contentType)] = codec;

  String _key(xmtp.ContentTypeId type) => '${type.authorityId}/${type.typeId}';

  Codec? _codecFor(xmtp.ContentTypeId type) => _codecs[_key(type)];

  /// Use the registered codecs to decode the [encoded] content.
  @override
  Future<DecodedContent> decodeContent(xmtp.EncodedContent encoded) async {
    var codec = _codecFor(encoded.type);
    if (codec == null) {
      if (encoded.hasFallback()) {
        return DecodedContent(contentTypeText, encoded.fallback);
      }
      throw StateError(
          "unable to decode unsupported type ${_key(encoded.type)}");
    } else {
      return DecodedContent(encoded.type, await codec.decode(encoded));
    }
  }

  /// Use the registered codecs to encode the [content].
  Future<xmtp.EncodedContent> encodeContent(
    xmtp.ContentTypeId? type,
    Object content,
  ) async {
    type ??= contentTypeText;
    var codec = _codecFor(type);
    if (codec == null) {
      throw StateError("unable to encode unsupported type ${_key(type)}");
    }
    return codec.encode(content);
  }
}
