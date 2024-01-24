import 'package:flutter_test/flutter_test.dart';
import 'package:xmtp/src/common/topic.dart';

void main() {
  test('generateUserPreferencesIdentifier', () async {
    const key = [
      // Randomly generated key with a known-reference identifier.
      // This ensures that we're generating consistently across SDKs.
      69, 239, 223, 17, 3, 219, 126, 21, 172, 74, 55, 18, 123, 240, 246, 149,
      158, 74, 183,
      229, 236, 98, 133, 184, 95, 44, 130, 35, 138, 113, 36, 211,
    ];
    var identifier = await generateUserPreferencesIdentifier(key);
    expect(identifier, "EBsHSM9lLmELuUVCMJ-tPE0kDcok1io9IwUO6WPC-cM");
  });

  test('ephemeralMessage v1', () {
    // V1 ephemeral topic should be `dmE-` instead of `dm-`.
    var addressA = "0x7E75Ee2a9f7D65E49cd8619b24B5731EbFa8064C"; // random
    var addressB = "0xFE4464Ea091FE9A8bE25BF7B413616b087F1D896"; // random
    var conversationTopic = Topic.directMessageV1(addressA, addressB);
    expect(
      conversationTopic,
      '/xmtp/0/dm-$addressA-$addressB/proto',
    );
    expect(
      Topic.ephemeralMessage(conversationTopic),
      '/xmtp/0/dmE-$addressA-$addressB/proto',
    );
  });

  test('ephemeralMessage v2', () {
    var randomId = "abc123";
    var conversationTopic = Topic.messageV2(randomId);
    expect(
      conversationTopic,
      '/xmtp/0/m-$randomId/proto',
    );
    expect(
      Topic.ephemeralMessage(conversationTopic),
      '/xmtp/0/mE-$randomId/proto',
    );
  });
}
