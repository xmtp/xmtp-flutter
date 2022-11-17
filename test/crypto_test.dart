import 'package:flutter_test/flutter_test.dart';
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

import 'package:xmtp/src/crypto.dart';

void main() {
  test('codec', () async {
    const message = [5, 5, 5];
    const secret = [1, 2, 3, 4];
    var encrypted = await encrypt(secret, message);
    var decrypted = await decrypt(secret, encrypted);
    expect(decrypted, message);
  });
  test('decrypting known cyphertext', () async {
    const message = [5, 5, 5];
    const secret = [1, 2, 3, 4];
    var encrypted = xmtp.Ciphertext.fromBuffer([
      // This was generated using xmtp-js code for encrypt().
      10, 69, 10, 32, 23, 10, 217, 190, 235, 216, 145,
      38, 49, 224, 165, 169, 22, 55, 152, 150, 176, 65,
      207, 91, 45, 45, 16, 171, 146, 125, 143, 60, 152,
      128, 0, 120, 18, 12, 219, 247, 207, 184, 141, 179,
      171, 100, 251, 171, 120, 137, 26, 19, 216, 215, 152,
      167, 118, 59, 93, 177, 53, 242, 147, 10, 87, 143,
      27, 245, 154, 169, 109
    ]);
    var decrypted = await decrypt(secret, encrypted);
    expect(decrypted, message);
  });
}
