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

  test('compression should work during encoding and decoding', () async {
    var registry = CodecRegistry();
    registry.registerCodec(TextCodec());
    var someText = "blah blah blah" * 100;
    for (var compression in CodecRegistry.supportedCompressions) {
      var encodedSmall = await registry.encode(
        DecodedContent(contentTypeText, someText),
        compression: compression,
      );
      var encodedLarge = await registry.encode(
        DecodedContent(contentTypeText, someText),
      );
      expect(encodedSmall.type, contentTypeText);
      expect(encodedLarge.type, contentTypeText);
      expect(encodedSmall.hasCompression(), true);
      expect(encodedLarge.hasCompression(), false);
      expect(encodedSmall.content.isNotEmpty, true);
      expect(encodedLarge.content.isNotEmpty, true);
      expect(encodedSmall.content.length < encodedLarge.content.length, true);
      var decodedSmall = await registry.decode(encodedSmall);
      var decodedLarge = await registry.decode(encodedLarge);
      expect(decodedSmall.contentType, contentTypeText);
      expect(decodedLarge.contentType, contentTypeText);
      expect(decodedSmall.content, someText);
      expect(decodedLarge.content, someText);
    }
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
