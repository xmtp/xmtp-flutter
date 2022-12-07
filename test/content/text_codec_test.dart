import 'package:flutter_test/flutter_test.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/content/text_codec.dart';

void main() {
  test('strings should be encoded and decoded', () async {
    var codec = TextCodec();
    var encoded = await codec.encode("foo bar");
    expect(encoded.type, contentTypeText);
    expect(encoded.content.isNotEmpty, true);
    var decoded = await codec.decode(encoded);
    expect(decoded, "foo bar");
  });

  test('unknown encodings should throw', () async {
    var codec = TextCodec();
    expect(
      () async => await codec.decode(xmtp.EncodedContent(
        type: contentTypeText,
        parameters: {'encoding': 'foo bar'},
      )),
      throwsStateError,
    );
  });
}
