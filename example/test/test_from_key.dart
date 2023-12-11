import 'package:flutter_test/flutter_test.dart';
import 'package:web3dart/web3dart.dart';
import 'package:xmtp/xmtp.dart' as xmtp;
import 'package:example/session/foreground_session.dart';
import "dart:math";

void main() {

  test('Test wallet authorization', () async {
    var wallet = EthPrivateKey.fromHex('953bcdf6bbb41880dcc2f78d7a29b922aff84b4278ff6f5126e99e35417cf720').asSigner();
    print('Wallet address: ${await wallet.address}');
    // Uncomment this to clear the DB on startup
    // await session.clear();
    //var api = xmtp.Api.create();
    var api = xmtp.Api.create(host: 'dev.xmtp.network');
    var client =  await xmtp.Client.createFromWallet(api, wallet);

    //Random
    var credentials1 = EthPrivateKey.createRandom(Random.secure());
    var wallet1 = credentials1.asSigner();
    print('Wallet address: ${await wallet1.address}');
    var api1 = xmtp.Api.create(host: 'dev.xmtp.network');
    var client1 =  await xmtp.Client.createFromWallet(api1, wallet1);
  });
}