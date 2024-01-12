import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:web3dart/crypto.dart';
import 'package:xmtp/src/common/crypto.dart';
import 'package:xmtp/src/content/attachment_codec.dart';
import 'package:xmtp/src/content/encoded_content_ext.dart';

import '../../xmtp.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class EncryptedEncodedContent {
  final String contentDigest;
  final Uint8List secret;
  final Uint8List salt;
  final Uint8List nonce;
  final Uint8List payload;
  final int? contentLength;
  final String? fileName;

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
  final int? contentLength;
  final String? fileName;
  final Fetcher fetcher = HttpFetcher();

  RemoteAttachment(this.url, this.contentDigest, this.secret, this.salt,
      this.nonce, this.scheme, this.contentLength, this.fileName);

  dynamic load() async {
    var payload = await fetcher.fetch(url);
    if (payload.isEmpty) {
      throw StateError("No remote attachment payload");
    }
    var encrypted = EncryptedEncodedContent(
        contentDigest, secret, salt, nonce, payload, contentLength, fileName);
    var decrypted = await decryptEncoded(encrypted);
    return decrypted.decoded;
  }

  static Future<EncodedContent> decryptEncoded(
      EncryptedEncodedContent encrypted) async {
    var hashPayload = sha256(encrypted.payload);
    if (bytesToHex(hashPayload) != encrypted.contentDigest) {
      throw StateError("content digest does not match");
    }

    var aes = Ciphertext_Aes256gcmHkdfsha256(
        hkdfSalt: encrypted.salt,
        gcmNonce: encrypted.nonce,
        payload: encrypted.payload);

    var cipherText = xmtp.Ciphertext(aes256GcmHkdfSha256: aes);
    var decrypted = await decrypt(encrypted.secret, cipherText);

    return EncodedContent.fromBuffer(decrypted);
  }

  static Future<EncryptedEncodedContent> encodedEncrypted(
      dynamic content, Codec<dynamic> codec) async {
    var secret = List<int>.generate(
        32, (index) => SecureRandom.forTesting().nextUint32());
    var encodedContent = await codec.encode(content);
    var cipherText = await encrypt(secret, encodedContent.writeToBuffer());
    var contentDigest =
        bytesToHex(sha256(cipherText.aes256GcmHkdfSha256.payload));
    var fileName = content is Attachment ? content.filename : null;
    return EncryptedEncodedContent(
        contentDigest,
        Uint8List.fromList(secret),
        Uint8List.fromList(cipherText.aes256GcmHkdfSha256.hkdfSalt),
        Uint8List.fromList(cipherText.aes256GcmHkdfSha256.gcmNonce),
        Uint8List.fromList(cipherText.aes256GcmHkdfSha256.payload),
        encodedContent.content.length,
        fileName);
  }

  static RemoteAttachment from(
      Uri url, EncryptedEncodedContent encryptedEncodedContent) {
    if (url.scheme != "https") {
      throw StateError("scheme must be https://");
    }

    return RemoteAttachment(
        url,
        encryptedEncodedContent.contentDigest,
        encryptedEncodedContent.secret,
        encryptedEncodedContent.salt,
        encryptedEncodedContent.nonce,
        url.scheme,
        encryptedEncodedContent.contentLength,
        encryptedEncodedContent.fileName);
  }
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
        Uri.parse(utf8.decode(encoded.content)),
        encoded.parameters["contentDigest"] ?? "",
        Uint8List.fromList((encoded.parameters["secret"] ?? "").codeUnits),
        Uint8List.fromList((encoded.parameters["salt"] ?? "").codeUnits),
        Uint8List.fromList((encoded.parameters["nonce"] ?? "").codeUnits),
        encoded.parameters["scheme"] ?? "",
        encoded.content.length,
        encoded.parameters["filename"] ?? "",
      );

  @override
  Future<xmtp.EncodedContent> encode(RemoteAttachment decoded) async {
    var content = Uint8List.fromList(decoded.url.toString().codeUnits);
    var parameters = {
      "contentDigest": decoded.contentDigest,
      "secret": bytesToHex(decoded.secret),
      "salt": bytesToHex(decoded.salt),
      "nonce": bytesToHex(decoded.nonce),
      "scheme": decoded.scheme,
      "contentLength": content.length.toString(),
      "filename": decoded.fileName ?? "",
    };
    return EncodedContent(
      type: contentTypeRemoteAttachments,
      content: content,
      parameters: parameters,
    );
  }

  @override
  String? fallback(RemoteAttachment content) {
    return "Can’t display \"${content.fileName}\". This app doesn’t support remote attachments.";
  }
}
