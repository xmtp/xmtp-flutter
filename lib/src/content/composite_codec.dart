import 'package:xmtp/src/content/codec_registry.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'codec.dart';
import 'decoded.dart';

final contentTypeComposite = xmtp.ContentTypeId(
  authorityId: "xmtp.org",
  typeId: "composite",
  versionMajor: 1,
  versionMinor: 0,
);

/// This is a [Codec] that can handle a composite of other content types.
///
/// It is initialized with a [CodecRegistry] that it uses to encode and decode
/// the parts of the composite.
///
/// Both [encode] and [decode] are implemented by recursing through the
/// composite and serializing/deserializing to the [xmtp.Composite] as
/// the [content] bytes in a [xmtp.EncodedContent] of type [contentTypeComposite].
class CompositeCodec extends Codec<DecodedComposite> {
  final Codec<DecodedContent> _registry;

  CompositeCodec(this._registry);

  @override
  xmtp.ContentTypeId get contentType => contentTypeComposite;

  @override
  Future<DecodedComposite> decode(xmtp.EncodedContent encoded) async =>
      _decode(xmtp.Composite.fromBuffer(encoded.content));

  @override
  Future<xmtp.EncodedContent> encode(DecodedComposite decoded) async {
    var composite = await _encode(decoded);
    return xmtp.EncodedContent(
      type: contentTypeComposite,
      content: composite.writeToBuffer(),
    );
  }

  /// Decode the [composite] into a [DecodedComposite].
  ///
  /// This recursively decodes the parts of the composite.
  Future<DecodedComposite> _decode(xmtp.Composite composite) async {
    var results = <DecodedComposite>[];
    for (var part in composite.parts) {
      if (part.hasPart()) {
        var decoded = await _registry.decode(part.part);
        results.add(DecodedComposite.ofContent(decoded));
      } else {
        var decoded = await _decode(part.composite);
        results.add(decoded);
      }
    }
    if (results.length == 1) {
      return results[0];
    }
    return DecodedComposite.withParts(results);
  }

  /// Encode the [decoded] into a [xmtp.Composite].
  ///
  /// This recursively encodes the parts of the composite.
  Future<xmtp.Composite> _encode(DecodedComposite decoded) async {
    if (decoded.hasContent) {
      var encoded = await _registry.encode(decoded.content!);
      return xmtp.Composite()..parts.add(xmtp.Composite_Part(part: encoded));
    }
    var result = xmtp.Composite();
    for (var part in decoded.parts) {
      if (part.hasContent) {
        var encoded = await _registry.encode(part.content!);
        result.parts.add(xmtp.Composite_Part(part: encoded));
      } else {
        result.parts.add(xmtp.Composite_Part(composite: await _encode(part)));
      }
    }
    return result;
  }
}
