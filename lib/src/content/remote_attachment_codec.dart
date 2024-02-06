import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web3dart/crypto.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;
import '../common/crypto.dart' as crypto;

import 'codec.dart';

final contentTypeRemoteAttachment = xmtp.ContentTypeId(
  authorityId: "xmtp.org",
  typeId: "remoteStaticAttachment",
  versionMajor: 1,
  versionMinor: 0,
);

/// This should download the [url] and return the data.
typedef RemoteDownloader = Future<List<int>> Function(String url);

/// This should upload the [data] and return the URL.
typedef RemoteUploader = Future<String> Function(List<int> data);

/// This is a remote encrypted file URL.
class RemoteAttachment {
  final List<int> salt;
  final List<int> nonce;
  final List<int> secret;
  final String scheme;
  final String url;
  final String filename;
  final int contentLength;
  final String contentDigest;

  RemoteAttachment({
    required this.salt,
    required this.nonce,
    required this.secret,
    required this.scheme,
    required this.url,
    required this.filename,
    required this.contentLength,
    required this.contentDigest,
  });

  /// This uploads the [encoded] file using the [uploader].
  /// See [Client.upload] for typical usage.
  static Future<RemoteAttachment> upload(
    String filename,
    xmtp.EncodedContent encoded,
    RemoteUploader uploader,
  ) async {
    var secret = crypto.generateRandomBytes(32);
    var encrypted = await crypto.encrypt(
      secret,
      encoded.writeToBuffer(),
    );
    var url = await uploader(encrypted.aes256GcmHkdfSha256.payload);
    return RemoteAttachment(
      salt: encrypted.aes256GcmHkdfSha256.hkdfSalt,
      nonce: encrypted.aes256GcmHkdfSha256.gcmNonce,
      secret: secret,
      scheme: "https://",
      url: url,
      filename: filename,
      contentLength: encrypted.aes256GcmHkdfSha256.payload.length,
      contentDigest:
          bytesToHex(crypto.sha256(encrypted.aes256GcmHkdfSha256.payload)),
    );
  }

  /// This downloads the file from the [url] and decrypts it.
  /// See [Client.download] for typical usage.
  Future<xmtp.EncodedContent> download(RemoteDownloader downloader) async {
    var payload = await downloader(url);
    var decrypted = await crypto.decrypt(
        secret,
        xmtp.Ciphertext(
          aes256GcmHkdfSha256: xmtp.Ciphertext_Aes256gcmHkdfsha256(
            hkdfSalt: salt,
            gcmNonce: nonce,
            payload: payload,
          ),
        ));
    return xmtp.EncodedContent.fromBuffer(decrypted);
  }
}

/// This is a [Codec] that encodes a remote encrypted file URL as the content.
class RemoteAttachmentCodec extends Codec<RemoteAttachment> {
  @override
  xmtp.ContentTypeId get contentType => contentTypeRemoteAttachment;

  @override
  Future<RemoteAttachment> decode(xmtp.EncodedContent encoded) async =>
      RemoteAttachment(
        url: utf8.decode(encoded.content),
        filename: encoded.parameters["filename"] ?? "",
        salt: hexToBytes(encoded.parameters["salt"] ?? ""),
        nonce: hexToBytes(encoded.parameters["nonce"] ?? ""),
        secret: hexToBytes(encoded.parameters["secret"] ?? ""),
        contentLength: int.parse(encoded.parameters["contentLength"] ?? "0"),
        contentDigest: encoded.parameters["contentDigest"] ?? "",
        scheme: "https://",
      );

  @override
  Future<xmtp.EncodedContent> encode(RemoteAttachment decoded) async =>
      xmtp.EncodedContent(
        type: contentTypeRemoteAttachment,
        parameters: {
          "filename": decoded.filename,
          "secret": bytesToHex(decoded.secret),
          "salt": bytesToHex(decoded.salt),
          "nonce": bytesToHex(decoded.nonce),
          "contentLength": decoded.contentLength.toString(),
          "contentDigest": decoded.contentDigest,
        },
        content: utf8.encode(decoded.url),
      );

  @override
  String? fallback(RemoteAttachment content) {
    return "Can’t display \"${content.filename}\". This app doesn’t support attachments.";
  }
}
