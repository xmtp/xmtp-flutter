import 'package:flutter_test/flutter_test.dart';

import 'package:xmtp/src/content/reaction_codec.dart';

void main() {
  test('reaction should be encoded and decoded', () async {
    var codec = ReactionCodec();

    var encoded = await codec.encode(
        Reaction("abc123", ReactionAction.added, ReactionSchema.unicode, "👍"));
    expect(encoded.type, contentTypeReaction);
    expect(encoded.content.isNotEmpty, true);
    var decoded = await codec.decode(encoded);
    expect(decoded.reference, "abc123");
    expect(decoded.action, ReactionAction.added);
    expect(decoded.schema, ReactionSchema.unicode);
    expect(decoded.content, "👍");
  });
}
