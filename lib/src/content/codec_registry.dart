import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'codec.dart';
import 'decoded.dart';
import 'text_codec.dart';

/// This is a registry of codecs for particular types.
///
/// It knows how to apply the codecs to [decode] or [encode]
/// [xmtp.EncodedContent] to [DecodedContent]..
class CodecRegistry implements Codec<DecodedContent> {
  final Map<String, Codec> _codecs = {};

  void registerCodec(Codec codec) => _codecs[_key(codec.contentType)] = codec;

  String _key(xmtp.ContentTypeId type) => '${type.authorityId}/${type.typeId}';

  Codec? _codecFor(xmtp.ContentTypeId type) => _codecs[_key(type)];

  /// Use the registered codecs to decode the [encoded] content.
  @override
  Future<DecodedContent> decode(xmtp.EncodedContent encoded) async {
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
  @override
  Future<xmtp.EncodedContent> encode(DecodedContent decoded) async {
    var type = decoded.contentType;
    var codec = _codecFor(type);
    if (codec == null) {
      throw StateError("unable to encode unsupported type ${_key(type)}");
    }
    return codec.encode(decoded.content);
  }

  @override
  xmtp.ContentTypeId get contentType =>
      throw UnsupportedError("the registry, as a Codec, has no content type");

  @override
  String? fallback(DecodedContent content) {
    var type = content.contentType;
    var codec = _codecFor(type);
    return codec?.fallback(content.content);
  }
}
