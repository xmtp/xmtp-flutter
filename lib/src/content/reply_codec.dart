import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'codec.dart';
import 'decoded.dart';

final contentTypeReply = xmtp.ContentTypeId(
  authorityId: "xmtp.org",
  typeId: "reply",
  versionMajor: 1,
  versionMinor: 0,
);

/// This is a reply to another [reference] message.
class Reply {
  /// This is the message ID of the parent message.
  /// See [DecodedMessage.id]
  final String reference;
  final DecodedContent content;

  Reply(this.reference, this.content);
}

extension on xmtp.ContentTypeId {
  String toText() => "$authorityId/$typeId:$versionMajor.$versionMinor";
}

/// This is a [Codec] that encodes a reply to another message.
class ReplyCodec extends NestedContentCodec<Reply> {
  @override
  xmtp.ContentTypeId get contentType => contentTypeReply;

  @override
  Future<Reply> decode(xmtp.EncodedContent encoded) async => Reply(
        encoded.parameters["reference"] ?? "",
        await registry.decode(xmtp.EncodedContent.fromBuffer(encoded.content)),
      );

  @override
  Future<xmtp.EncodedContent> encode(Reply decoded) async =>
      xmtp.EncodedContent(
        type: contentTypeReply,
        parameters: {
          "reference": decoded.reference,
          // TODO: cut when we know nothing looks here for the content type
          "contentType": decoded.content.contentType.toText(),
        },
        content: (await registry.encode(decoded.content)).writeToBuffer(),
      );

  @override
  String? fallback(Reply content) {
    if (content.content.contentType.typeId == "text") {
      return "Replied with “${content.content.content}” to an earlier message";
    }
    return "Replied to an earlier message";
  }
}
