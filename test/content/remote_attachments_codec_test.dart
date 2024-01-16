import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xmtp/src/content/attachment_codec.dart';
import 'package:xmtp/src/content/encoded_content_ext.dart';
import 'package:xmtp/src/content/remote_attachment_codec.dart';
import 'package:xmtp/xmtp.dart';

void main() {
  test('Remote attachment must be encoded and decoded', () async {
    var attachment =
        Attachment("test.txt", "text/plain", utf8.encode("Hello world"));
    var codec = RemoteAttachmentCodec();
    var url = Uri.parse("https://abcdefg");
    var encryptedEncodedContent =
        RemoteAttachment.encodedEncrypted(attachment, AttachmentCodec());
    var remoteAttachment =
        RemoteAttachment.from(url, await encryptedEncodedContent);
    var encoded = await codec.encode(remoteAttachment);
    expect(encoded.type, contentTypeRemoteAttachments);
    expect(encoded.content.isNotEmpty, true);
    RemoteAttachment decoded = await codec.decode(encoded);
    expect(decoded.url, url);
    expect(decoded.fileName, 'test.txt');
  });

  test('Encryption content should be decryptable', () async {
    var attachment =
        Attachment("test.txt", "text/plain", utf8.encode("Hello world"));
    var encrypted =
        await RemoteAttachment.encodedEncrypted(attachment, AttachmentCodec());
    var decrypted = await RemoteAttachment.decryptEncoded(encrypted);
    Client.registerCodecs([RemoteAttachmentCodec(), AttachmentCodec()]);
    var decoded = await decrypted.decoded();
    expect(attachment.filename, (decoded.content as Attachment).filename);
    expect(attachment.mimeType, (decoded.content as Attachment).mimeType);
    expect(attachment.data, (decoded.content as Attachment).data);
  });

  test('Cannot use non https url', () async {
    var attachment =
        Attachment("test.txt", "text/plain", utf8.encode("Hello world"));
    Client.registerCodecs([RemoteAttachmentCodec(), AttachmentCodec()]);
    var encryptedEncodedContent =
        await RemoteAttachment.encodedEncrypted(attachment, AttachmentCodec());
    final file = File("abcdefg");
    file.writeAsBytesSync(encryptedEncodedContent.payload);
    expect(
        () => RemoteAttachment.from(
            Uri.parse("http://abcdefg"), encryptedEncodedContent),
        throwsStateError);
  });
}
