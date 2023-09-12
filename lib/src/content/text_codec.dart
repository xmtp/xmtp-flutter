import 'dart:convert';

import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'codec.dart';

final contentTypeText = xmtp.ContentTypeId(
  authorityId: "xmtp.org",
  typeId: "text",
  versionMajor: 1,
  versionMinor: 0,
);

const Set<String> supportedEncodings = {'UTF-8'};
const String defaultEncoding = 'UTF-8';

/// This is a basic text [Codec] that supports UTF-8 encoding.
class TextCodec extends Codec<String> {
  @override
  xmtp.ContentTypeId get contentType => contentTypeText;

  @override
  Future<String> decode(xmtp.EncodedContent encoded) async {
    var encoding = encoded.parameters['encoding'] ?? defaultEncoding;
    if (!supportedEncodings.contains(encoding)) {
      throw StateError("unsupported text encoding '$encoding'");
    }
    return utf8.decode(encoded.content);
  }

  @override
  Future<xmtp.EncodedContent> encode(String decoded) async =>
      xmtp.EncodedContent(
        type: contentTypeText,
        parameters: {'encoding': defaultEncoding},
        content: utf8.encode(decoded),
      );

  @override
  String? fallback(String content) {
    return null;
  }
}
