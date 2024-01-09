import 'package:flutter_test/flutter_test.dart';

import 'package:xmtp/src/content/attachment_codec.dart';

void main() {
  test('attached file should be encoded and decoded', () async {
    var codec = AttachmentCodec();

    var encoded = await codec
        .encode(Attachment("file.bin", "application/octet-stream", [3, 2, 1]));
    expect(encoded.type, contentTypeAttachment);
    expect(encoded.content.isNotEmpty, true);
    var decoded = await codec.decode(encoded);
    expect(decoded.filename, "file.bin");
    expect(decoded.mimeType, "application/octet-stream");
    expect(decoded.data, [3, 2, 1]);
  });
}
