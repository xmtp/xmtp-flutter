import 'dart:convert' as convert;
import 'dart:io' as io;

import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'codec.dart';
import 'decoded.dart';
import 'text_codec.dart';

typedef Compressor = convert.Codec<List<int>, List<int>>;

/// This is a registry of codecs for particular types.
///
/// It knows how to apply the codecs to [decode] or [encode]
/// [xmtp.EncodedContent] to [DecodedContent]..
class CodecRegistry implements Codec<DecodedContent> {
  final Map<String, Codec> _codecs = {};
  static final Map<xmtp.Compression, Compressor> _compressors = {
    xmtp.Compression.COMPRESSION_GZIP: io.gzip,
    xmtp.Compression.COMPRESSION_DEFLATE: io.zlib,
  }; // TODO: consider supporting custom compressors
  static final Set<xmtp.Compression> supportedCompressions =
      _compressors.keys.toSet();

  void registerCodec(Codec codec) => _codecs[_key(codec.contentType)] = codec;

  String _key(xmtp.ContentTypeId type) => '${type.authorityId}/${type.typeId}';

  Codec? _codecFor(xmtp.ContentTypeId type) => _codecs[_key(type)];

  /// Use the registered codecs to decode the [encoded] content.
  @override
  Future<DecodedContent> decode(xmtp.EncodedContent encoded) async {
    if (encoded.hasCompression()) {
      var compressor = _compressors[encoded.compression];
      if (compressor == null) {
        throw StateError(
            "unable to decode unsupported compression ${encoded.compression}");
      }
      var decompressed = compressor.decode(encoded.content);
      encoded = xmtp.EncodedContent()
        ..mergeFromMessage(encoded)
        ..clearCompression()
        ..content = decompressed;
    }
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
  Future<xmtp.EncodedContent> encode(
    DecodedContent decoded, {
    xmtp.Compression? compression,
  }) async {
    var type = decoded.contentType;
    var codec = _codecFor(type);
    if (codec == null) {
      throw StateError("unable to encode unsupported type ${_key(type)}");
    }
    var encoded = await codec.encode(decoded.content);
    // TODO: consider warning if it isn't compressed but should be
    if (compression != null) {
      var compressor = _compressors[compression];
      if (compressor == null) {
        throw StateError(
            "unable to encode unsupported compression $compression");
      }
      var compressed = compressor.encode(encoded.content);
      encoded = xmtp.EncodedContent()
        ..mergeFromMessage(encoded)
        ..compression = compression
        ..content = compressed;
    }
    return encoded;
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
