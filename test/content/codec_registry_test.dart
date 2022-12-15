import 'package:flutter_test/flutter_test.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/content/codec_registry.dart';
import 'package:xmtp/src/content/decoded.dart';
import 'package:xmtp/src/content/text_codec.dart';

void main() {
  test('known types should be encoded and decoded', () async {
    var registry = CodecRegistry();
    registry.registerCodec(TextCodec());
    var encoded =
        await registry.encode(DecodedContent(contentTypeText, "foo bar"));
    expect(encoded.type, contentTypeText);
    expect(encoded.content.isNotEmpty, true);
    var decoded = await registry.decode(encoded);
    expect(decoded.contentType, contentTypeText);
    expect(decoded.content, "foo bar");
  });

  test('unknown types should throw', () async {
    var registry = CodecRegistry();
    registry.registerCodec(TextCodec());
    var unknownType = xmtp.ContentTypeId(
      authorityId: "example.com",
      typeId: "unknown",
    );
    expect(
      () async => await registry.encode(DecodedContent(unknownType, "foo bar")),
      throwsStateError,
    );
    expect(
      () async => await registry.decode(
        xmtp.EncodedContent(type: unknownType, content: [0x01, 0x02]),
      ),
      throwsStateError,
    );
  });

  test('when unsupported content includes fallback text, that should be used',
      () async {
    var registry = CodecRegistry();
    registry.registerCodec(TextCodec());
    var unsupportedType = xmtp.ContentTypeId(
      authorityId: "example.com",
      typeId: "unsupported",
    );
    var decoded = await registry.decode(
      xmtp.EncodedContent(
        type: unsupportedType,
        content: [0x01, 0x02],
        fallback: "some fallback text",
      ),
    );
    expect(decoded.contentType, contentTypeText);
    expect(decoded.content, "some fallback text");
  });
}
