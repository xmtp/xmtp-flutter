import 'dart:io';
import 'package:xmtp/xmtp.dart';

extension EncodedDecompressExt on EncodedContent {
  dynamic decoded() {
    var encodedContent = this;
    if (hasCompression()) {
      encodedContent = decompressContent();
    }
    return Client.codecs.decode(encodedContent);
  }

  EncodedContent compressContent() {
    var copy = this;
    switch (compression) {
      case Compression.COMPRESSION_DEFLATE:
        copy.compression = Compression.COMPRESSION_DEFLATE;
        copy.content = EncodedContentCompression.DEFLATE.compress(content);
        break;
      case Compression.COMPRESSION_GZIP:
        copy.compression = Compression.COMPRESSION_GZIP;
        copy.content = EncodedContentCompression.GZIP.compress(content);
        break;
    }
    return copy;
  }

  EncodedContent decompressContent() {
    if (!hasCompression()) {
      return this;
    }
    var copy = this;
    switch (compression) {
      case Compression.COMPRESSION_DEFLATE:
        copy = EncodedContentCompression.DEFLATE.decompress(content)
            as EncodedContent;
        break;
      case Compression.COMPRESSION_GZIP:
        copy = EncodedContentCompression.GZIP.decompress(content)
            as EncodedContent;
        break;
    }
    return copy;
  }
}

enum EncodedContentCompression {
  DEFLATE,
  GZIP;
}

extension EncodedContentCompressionExt on EncodedContentCompression {
  List<int> compress(List<int> content) {
    switch (this) {
      case EncodedContentCompression.DEFLATE:
        return zlib.encode(content);
      case EncodedContentCompression.GZIP:
        return gzip.encode(content);
    }
  }

  List<int> decompress(List<int> content) {
    switch (this) {
      case EncodedContentCompression.DEFLATE:
        return zlib.decode(content);
      case EncodedContentCompression.GZIP:
        return gzip.decode(content);
    }
  }
}
