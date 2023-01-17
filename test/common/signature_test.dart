import 'package:flutter_test/flutter_test.dart';

import 'package:xmtp/src/common/signature.dart';

void main() {
  test('toEthereumAddress: leading-zero keys should safely convert', () {
    // This reproduces a squirrelly bug we were seeing periodically in tests.
    // gist: if the first bytes of a public key are zero then the EC recovery
    //       from a signature trims those from the byte-list (so length < 64).
    // This test verifies the fix (of padding to 64 with leading zero-bytes).
    var publicKey = [
      // These are the 63-bytes of a random public key that were returned
      // when we recovered it from a signature.
      0x38, 0xd0, 0x85, 0x99, 0x49, 0x90, 0x52, 0x9d,
      0x86, 0x0d, 0xea, 0x01, 0x65, 0x7c, 0x7a, 0xb2,
      0x76, 0xe2, 0xc1, 0x41, 0xa5, 0xbc, 0x00, 0x07,
      0x66, 0x71, 0x47, 0xb4, 0x76, 0xf1, 0xba, 0x6f,
      0x78, 0xa9, 0x6b, 0x4f, 0x65, 0x0a, 0x17, 0x3a,
      0x18, 0x54, 0x56, 0x04, 0x70, 0x53, 0xa1, 0x10,
      0xbd, 0xb5, 0x20, 0xa7, 0x70, 0x48, 0x10, 0x03,
      0xaa, 0x0f, 0xad, 0xbc, 0xf6, 0xe2, 0xdc,
    ];
    // We should produce the expected address even with only the 63 bytes.
    expect(
      publicKey.toEthereumAddress().hexEip55,
      "0xf2794A7b21AD11d107468AAbee88Cde88Fb56113",
    );
    // And it should yield the same address when it includes all 64 bytes.
    expect(
      ([0x00] + publicKey).toEthereumAddress().hexEip55,
      "0xf2794A7b21AD11d107468AAbee88Cde88Fb56113",
    );
  });
}
