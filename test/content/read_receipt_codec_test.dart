import 'package:flutter_test/flutter_test.dart';
import 'package:xmtp/src/content/read_receipt_codec.dart';

void main() {
  test('receipt must be encoded and decoded', () async {
    var codec = ReadReceiptCodec();
    var receipt = ReadReceipt();
    var encoded = await codec.encode(receipt);
    expect(encoded.type, contentTypeReadReceipt);
    expect(encoded.content.isEmpty, true);
    var decoded = await codec.decode(encoded);
    expect(decoded is ReadReceipt, true);
  });
}
