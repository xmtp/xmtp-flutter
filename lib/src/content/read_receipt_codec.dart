import 'dart:convert';

import '../../xmtp.dart';
import 'codec.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

final contentTypeReadReceipt = xmtp.ContentTypeId(
  authorityId: "xmtp.org",
  typeId: "readReceipt",
  versionMajor: 1,
  versionMinor: 0,
);

class ReadReceipt {
  String timestamp;

  ReadReceipt(this.timestamp);
}

class ReadReceiptCodec extends Codec<ReadReceipt> {
  @override
  xmtp.ContentTypeId get contentType => contentTypeReadReceipt;

  @override
  Future<ReadReceipt> decode(EncodedContent encoded) async {
    var timestamp = encoded.parameters['timestamp'];
    if (timestamp == null) {
      throw StateError("Invalid Content");
    }
    return ReadReceipt(timestamp);
  }

  @override
  Future<xmtp.EncodedContent> encode(ReadReceipt decoded) async =>
      xmtp.EncodedContent(
        type: contentTypeReadReceipt,
        parameters: {'timestamp': decoded.timestamp},
        content: utf8.encode(decoded.timestamp),
      );

}