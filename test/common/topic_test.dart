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
}
