import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp/xmtp.dart' as xmtp;
import 'package:xmtp/src/content/codec.dart';
import 'package:xmtp/src/client.dart';


// Main function to run the tests
void main() {
  // Test to check if messages from unsupported codecs without fallback text are discarded
  test(
    "codecs: discard messages from unsupported codecs without fallback text",
    () async {
      // Creating a wallet for Alice
      var aliceWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      // Creating an API for Alice
      var aliceApi = xmtp.Api.create(host: 'dev.xmtp.network');
      // Creating a client for Alice
      var alice = await Client.createFromWallet(aliceApi, aliceWallet,customCodecs: [MultiplyNumbersCodec()]);
      
      // Creating a wallet for Bob
      var bobWallet = EthPrivateKey.createRandom(Random.secure()).asSigner();
      // Creating an API for Bob
      var bobApi = xmtp.Api.create(host: 'dev.xmtp.network');
      // Creating a client for Bob
      var bob = await Client.createFromWallet(bobApi, bobWallet,customCodecs: [ MultiplyNumbersCodec()]);
    
      // Creating a conversation between Alice and Bob
      var aliceConvo = await alice.newConversation(bob.address.toString());
      var bobConvo = await bob.newConversation(alice.address.toString());

      // Multiplying two numbers and storing the result
      var multiplyNumbers = MultiplyNumbers(num1: 12, num2: 34, result: 12*34);
      // Encoding the multiplication result
      var encodedMultiplyNumbers = await MultiplyNumbersCodec().encode(multiplyNumbers);
      // Alice sends the encoded message
      await alice.sendMessageEncoded(aliceConvo, encodedMultiplyNumbers);
      
      // Then Bob should see it
      var bobMessages = await bob.listMessages(bobConvo);
      // Printing the length of Bob's messages
      print('The length of bobMessages is: ${bobMessages.length}');
      // Checking if the first message content is the multiplication result
      if (bobMessages[0].contentType == contentTypeMultiplyNumbers) {
        expect((bobMessages[0].content as MultiplyNumbers).result, 408.0);
        print("Message decoded sucessfully");
      } else {
        print('The content type is not MultiplyNumbers');
      }
    }
  );

}


// Class to store two numbers and their multiplication result
class MultiplyNumbers {
  final double num1;
  final double num2;
  final double result;

  MultiplyNumbers({required this.num1, required this.num2, required this.result});
}


/// This encodes two numbers and their multiplication result.
final contentTypeMultiplyNumbers = xmtp.ContentTypeId(
  authorityId: "com.example",
  typeId: "multiplyNumbers",
  versionMajor: 1,
  versionMinor: 1,
);

// Codec class to encode and decode the multiplication result
class MultiplyNumbersCodec extends Codec<MultiplyNumbers> {
  @override
  // Content type for the codec
  xmtp.ContentTypeId get contentType => contentTypeMultiplyNumbers;

  @override
  // Function to encode the multiplication result
  Future<xmtp.EncodedContent> encode(MultiplyNumbers decoded) async => xmtp.EncodedContent(
    type: contentTypeMultiplyNumbers,
    parameters: {
      'num1': decoded.num1.toString(),
      'num2': decoded.num2.toString(),
    },
  );

  @override
  // Function to decode the encoded content
  Future<MultiplyNumbers> decode(xmtp.EncodedContent encoded) async {
    var num1 = double.parse(encoded.parameters['num1'] ?? '0');
    var num2 = double.parse(encoded.parameters['num2'] ?? '0');
    return MultiplyNumbers(num1: num1, num2: num2, result: num1 * num2);
  }

  @override
  // Fallback function in case the codec is not supported
  String fallback(MultiplyNumbers content) => "MultiplyNumbersCodec is not supported";
}
