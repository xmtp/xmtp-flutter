import '../../xmtp.dart';
import 'codec.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class EncryptedEncodedContent {
  final String contentDigest;
  final Uint8List secret;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List payload;
  final int contentLength;
  final String fileName;

  EncryptedEncodedContent(this.contentDigest, this.secret, this.salt,
      this.nonce, this.payload, this.contentLength, this.fileName);
}

class RemoteAttachment {
  final Uri url;
  final String contentDigest;
  final Uint8List secret;
  final Uint8List salt;
  final Uint8List nonce;
  final String scheme;
  final int contentLength;
  final String fileName;
  final Fetcher fetcher;

  RemoteAttachment(this.url, this.contentDigest, this.secret, this.salt,
      this.nonce, this.scheme, this.contentLength, this.fileName, this.fetcher);
}

abstract class Fetcher {
  Future<Uint8List> fetch(Uri url);
}

class HttpFetcher implements Fetcher {
  @override
  Future<Uint8List> fetch(Uri url) async {
    return await http.readBytes(url);
  }
}

final contentTypeRemoteAttachments = xmtp.ContentTypeId(
  authorityId: "xmtp.org",
  typeId: "remoteStaticAttachment",
  versionMajor: 1,
  versionMinor: 0,
);

class RemoteAttachmentCodec extends Codec<RemoteAttachment> {
  @override
  xmtp.ContentTypeId get contentType => contentTypeRemoteAttachments;

  @override
  Future<RemoteAttachment> decode(EncodedContent encoded) async =>
      RemoteAttachment(
          Uri.parse(encoded.content.toString()),
          encoded.parameters["contentDigest"] ?? "",
          secret,
          salt,
          nonce,
          scheme,
          int.parse(encoded.parameters["contentLength"] ?? ""),
          encoded.parameters["filename"] ?? "",
          fetcher
      );

  @override
  Future<xmtp.EncodedContent> encode(RemoteAttachment decoded) {
    // TODO: implement encode
    throw UnimplementedError();
  }

  @override
  String? fallback(RemoteAttachment content) {
    return "Can’t display \"${content.fileName}\". This app doesn’t support remote attachments.";
  }

}
