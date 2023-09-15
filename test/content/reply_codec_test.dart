import 'package:flutter_test/flutter_test.dart';

import 'package:xmtp/src/content/codec_registry.dart';
import 'package:xmtp/src/content/decoded.dart';
import 'package:xmtp/src/content/text_codec.dart';
import 'package:xmtp/src/content/reply_codec.dart';

void main() {
  test('reply text should be encoded and decoded', () async {
    var registry = CodecRegistry()..registerCodec(TextCodec());
    var codec = ReplyCodec();
    codec.setRegistry(registry);

    var parentMessageId = "abc123";
    var encoded = await codec.encode(
        Reply(parentMessageId, DecodedContent(contentTypeText, "foo bar")));
    expect(encoded.type, contentTypeReply);
    expect(encoded.content.isNotEmpty, true);
    var decoded = await codec.decode(encoded);
    expect(decoded.reference, parentMessageId);
    expect(decoded.content!.contentType, contentTypeText);
    expect(decoded.content!.content, "foo bar");
    expect(encoded.fallback, "Replied with “foo bar” to an earlier message");
  });
}
