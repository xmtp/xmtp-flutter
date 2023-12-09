
import 'package:flutter_test/flutter_test.dart';
import 'package:xmtp/src/content/read_receipt_codec.dart';

void main() {
  test('receipt must be encoded and decoded', () async {
    var codec = ReadReceiptCodec();
    String timestamp = '2019-09-26T07:58:30.996+0200';
    var receipt = ReadReceipt(timestamp);
    var encoded = await codec.encode(receipt);
    expect(encoded.type, contentTypeReadReceipt);
    expect(encoded.content.isNotEmpty, true);
    var decoded = await codec.decode(encoded);
    expect(decoded.timestamp, receipt.timestamp);
  });
}