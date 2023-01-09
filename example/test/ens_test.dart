import 'package:convert/convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';

import 'package:example/ens.dart' as ens;

void main() {
  test(
    'nameHash',
    () {
      var hashes = {
        'dmccartney.eth':
            'fcd7eb9842d9ce2c18171a5071a9ffec30d316a6fe281b9f96e598582a5312b9',
        'saulmc.eth':
            '2b0454f61cba2a8dbc63f6a28bebe0093ea57470dcf3b5ba534c59505585fd17',
        'anoopr.eth':
            '115c6af238d99d5d25be936d361228ce57af4c2124b95d5cc51452da055ba6f7',
        'vitalik.eth':
            'ee6c4522aab0003e8d14cd40a6af439055fd2577951148c14b6cea9a53475835',
        '359b0ceb2dabcbb6588645de3b480c8203aa5b76.addr.reverse':
            'a8ce0b162a49f36bac0e7df761f95767b7e718137488484118aa6e155682b650',
      };
      hashes.forEach((name, hash) {
        expect(hex.encode(ens.nameHash(name)), hash);
      });
    },
  );
  test(
    skip: "manual testing only",
    'lookupAddress / resolveName',
    () async {
      // Set the RPC url here.
      // e.g. 'https://mainnet.infura.io/v3/...',
      //      'https://eth-mainnet.g.alchemy.com/v2/...'
      var rpcUrl = '...';
      var web3 = Web3Client(rpcUrl, http.Client());
      var addrs = {
        "dmccartney.eth": "0x359B0ceb2daBcBB6588645de3B480c8203aa5b76",
        "saulmc.eth": "0xf0EA7663233F99D0c12370671abBb6Cca980a490",
        "anoopr.eth": "0x66942eC8b0A6d0cff51AEA9C7fd00494556E705F",
        "vitalik.eth": "0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045",
      };
      for (var name in addrs.keys) {
        var addr = EthereumAddress.fromHex(addrs[name]!);
        expect(await web3.lookupAddress(addr), name);
        expect(await web3.resolveName(name), addr);
      }
    },
  );
}
