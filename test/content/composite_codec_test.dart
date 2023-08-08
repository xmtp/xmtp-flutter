import 'package:flutter_test/flutter_test.dart';

import 'package:xmtp/src/content/codec_registry.dart';
import 'package:xmtp/src/content/composite_codec.dart';
import 'package:xmtp/src/content/decoded.dart';
import 'package:xmtp/src/content/text_codec.dart';

void main() {
  test('single nested string should be encoded/decoded', () async {
    var registry = CodecRegistry()..registerCodec(TextCodec());
    var codec = CompositeCodec();
    codec.setRegistry(registry);

    var encoded = await codec.encode(
        DecodedComposite.ofContent(DecodedContent(contentTypeText, "foo bar")));
    expect(encoded.type, contentTypeComposite);
    expect(encoded.content.isNotEmpty, true);
    var decoded = await codec.decode(encoded);
    expect(decoded.hasContent, true);
    expect(decoded.content!.contentType, contentTypeText);
    expect(decoded.content!.content, "foo bar");
  });

  test('multiple strings should be encoded/decoded', () async {
    var registry = CodecRegistry()..registerCodec(TextCodec());
    var codec = CompositeCodec();
    codec.setRegistry(registry);

    var encoded = await codec.encode(DecodedComposite.withParts([
      DecodedComposite.ofContent(DecodedContent(contentTypeText, "foo")),
      DecodedComposite.ofContent(DecodedContent(contentTypeText, "bar")),
      DecodedComposite.ofContent(DecodedContent(contentTypeText, "baz")),
    ]));

    expect(encoded.type, contentTypeComposite);
    expect(encoded.content.isNotEmpty, true);

    var decoded = await codec.decode(encoded);
    expect(decoded.hasContent, false);
    expect(decoded.parts.length, 3);
    expect(decoded.parts[0].content!.contentType, contentTypeText);
    expect(decoded.parts[0].content!.content, "foo");
    expect(decoded.parts[1].content!.contentType, contentTypeText);
    expect(decoded.parts[1].content!.content, "bar");
    expect(decoded.parts[2].content!.contentType, contentTypeText);
    expect(decoded.parts[2].content!.content, "baz");
  });
}
