import 'package:flutter/foundation.dart';
import 'package:quiver/check.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

/// This is `addr(bytes32 node) returns (address)` from the ENS resolver.
const _addrFn = ContractFunction(
    'addr', [FunctionParameter('node', FixedBytes(32))],
    outputs: [FunctionParameter('address', AddressType())]);

/// This is `name(bytes32 node) returns (string)` from the ENS resolver.
const _nameFn = ContractFunction(
    'name', [FunctionParameter('node', FixedBytes(32))],
    outputs: [FunctionParameter('name', StringType())]);

/// This is `resolver(bytes32 node) returns (address)` from the ENS registry.
const _resolverFn = ContractFunction(
    'resolver', [FunctionParameter('node', FixedBytes(32))],
    outputs: [FunctionParameter('resolver', AddressType())]);

/// This yields the address of the ENS deployment.
EthereumAddress ensRegistryForChain(int chainId) {
  checkArgument([1, 3, 4, 5].contains(chainId),
      message: "ENS unavailable on chain $chainId (only [1, 3, 4, 5])");
  // ENS is deployed at the same address across mainnet and testnets.
  // See https://docs.ens.domains/ens-deployments
  return EthereumAddress.fromHex("0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e");
}

/// This hashes the [name] according to the ENS namehash algorithm.
///
/// TODO: implement ENS name normalization
/// See https://github.com/ethers-io/ethers.js/blob/master/packages/hash/lib/ens-normalize/lib.js#L76
List<int> nameHash(String name) {
  var node = Uint8List.fromList(List.filled(32, 0));
  name.split('.').reversed.where((label) => label.isNotEmpty).forEach((label) {
    var normalized = (label); // TODO: implement normalization
    var labelHash = keccakUtf8(normalized);
    node = keccak256(Uint8List.fromList(node + labelHash));
  });
  return node;
}

/// This adds ENS helpers to the [Web3Client].
///
/// It adds [resolveName] and [lookupAddress] for converting
/// between names and addresses.
extension Web3Ens on Web3Client {
  /// Returns the canonical ENS name for the given [address].
  ///
  /// If no name is registered, this will return `null`.
  Future<String?> lookupAddress(EthereumAddress address) async {
    var reverseName = "${address.hex.substring(2).toLowerCase()}.addr.reverse";
    var node = nameHash(reverseName);
    var resolver = await getResolver(reverseName);
    if (resolver == null) {
      debugPrint('No resolver for $reverseName');
      return null;
    }
    var res = await callRaw(
      contract: resolver,
      data: _nameFn.encodeCall([node]),
    );
    var name = _nameFn.decodeReturnValues(res)[0];
    if (address != await resolveName(name)) {
      // Discard when it doesn't forward resolve to this address.
      return null;
    }
    return name;
  }

  /// Returns the address for the given ENS [name].
  ///
  /// If [name] has no address registered, this will return `null`.
  Future<EthereumAddress?> resolveName(String name) async {
    var resolver = await getResolver(name);
    if (resolver == null) {
      return null;
    }
    var node = nameHash(name);
    var res = await callRaw(
      contract: resolver,
      data: _addrFn.encodeCall([node]),
    );
    return _addrFn.decodeReturnValues(res)[0];
  }

  /// Returns the registered resolver for the given ENS [name].
  ///
  /// Returns `null` if no resolver is registered.
  Future<EthereumAddress?> getResolver(String name) async {
    // TODO: support EIP-2544 wildcards (walk parents, checking for wildcards)
    try {
      var node = nameHash(name);
      var chainId = await getChainId();
      var registry = ensRegistryForChain(chainId.toInt());
      var res = await callRaw(
        contract: registry,
        data: _resolverFn.encodeCall([node]),
      );
      return _resolverFn.decodeReturnValues(res)[0];
    } catch (e) {
      debugPrint("getResolver failed: $e");
      return null;
    }
  }
}
