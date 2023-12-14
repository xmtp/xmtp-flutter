import 'dart:convert';
import 'dart:typed_data';

import '../../xmtp.dart';
import 'codec.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

final contentTypeReadReceipt = xmtp.ContentTypeId(
  authorityId: "xmtp.org",
  typeId: "readReceipt",
  versionMajor: 1,
  versionMinor: 0,
);

class ReadReceipt {}

class ReadReceiptCodec extends Codec<ReadReceipt> {
  @override
  xmtp.ContentTypeId get contentType => contentTypeReadReceipt;

  @override
  Future<ReadReceipt> decode(EncodedContent encoded) async {
    return ReadReceipt();
  }

  @override
  Future<xmtp.EncodedContent> encode(ReadReceipt decoded) async =>
      xmtp.EncodedContent(
        type: contentTypeReadReceipt,
        content: Uint8List.fromList([]),
      );

  @override
  String? fallback(ReadReceipt content) {
    return null;
  }
}