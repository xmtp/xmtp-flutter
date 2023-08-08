import 'package:flutter/foundation.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'codec.dart';

final contentTypeAttachment = xmtp.ContentTypeId(
  authorityId: "xmtp.org",
  typeId: "attachment",
  versionMajor: 1,
  versionMinor: 0,
);

/// This is a file attached as the message content.
///
/// Note: this is limited to small files that can fit in the message payload.
/// For larger files, use [RemoteAttachment].
class Attachment {
  final String filename;
  final String mimeType;
  final List<int> data;

  Attachment(this.filename, this.mimeType, this.data);
}

/// This is a [Codec] that encodes a file attached as the message content.
class AttachmentCodec extends Codec<Attachment> {
  @override
  xmtp.ContentTypeId get contentType => contentTypeAttachment;

  @override
  Future<Attachment> decode(xmtp.EncodedContent encoded) async =>
      Attachment(
        encoded.parameters["filename"] ?? "",
        encoded.parameters["mimeType"] ?? "",
        encoded.content,
      );

  @override
  Future<xmtp.EncodedContent> encode(Attachment decoded) async => xmtp.EncodedContent(
    type: contentTypeAttachment,
    parameters: {
      "filename": decoded.filename,
      "mimeType": decoded.mimeType,
    },
    content: decoded.data,
  );
}
