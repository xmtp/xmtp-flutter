import 'dart:convert';

import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'codec.dart';

final contentTypeReaction = xmtp.ContentTypeId(
  authorityId: "xmtp.org",
  typeId: "reaction",
  versionMajor: 1,
  versionMinor: 0,
);

enum ReactionAction {
  added,
  removed,
}

enum ReactionSchema {
  unicode,
  shortcode,
  custom,
}

/// This is a reaction to another [reference] message.
class Reaction {
  final String reference;
  final ReactionAction action;
  final ReactionSchema schema;
  final String content;

  Reaction(this.reference, this.action, this.schema, this.content);

  String toJson() => json.encode({
        "reference": reference,
        "action": action.toString().split(".").last,
        "schema": schema.toString().split(".").last,
        "content": content,
      });

  static Reaction fromJson(String json) {
    var v = jsonDecode(json);
    return Reaction(
      v["reference"],
      ReactionAction.values
          .firstWhere((e) => e.toString().split(".").last == v["action"]),
      ReactionSchema.values
          .firstWhere((e) => e.toString().split(".").last == v["schema"]),
      v["content"],
    );
  }
}

/// This is a [Codec] that encodes a reaction to another message.
class ReactionCodec extends Codec<Reaction> {
  @override
  xmtp.ContentTypeId get contentType => contentTypeReaction;

  @override
  Future<Reaction> decode(xmtp.EncodedContent encoded) async =>
      Reaction.fromJson(utf8.decode(encoded.content));

  @override
  Future<xmtp.EncodedContent> encode(Reaction decoded) async =>
      xmtp.EncodedContent(
        type: contentTypeReaction,
        content: utf8.encode(decoded.toJson()),
      );

  @override
  String? fallback(Reaction content) {
    switch (content.action) {
      case ReactionAction.added:
        return "Reacted “${content.content}” to an earlier message";
      case ReactionAction.removed:
        return "Removed “${content.content}” from an earlier message";
      default:
        return null;
    }
  }
}
