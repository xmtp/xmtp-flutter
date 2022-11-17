/// These are the texts that users are prompted to sign.
///
/// These must be kept in sync across the network.
/// See e.g. xmtp/xmtp-node-go/pkg/api/authentication.go#createIdentitySignRequest
///          xmtp-js/src/crypto/Signature.WalletSigner#identitySigRequestText
class SignatureText {
  /// This is the text that users sign when they want to create
  /// an identity key associated with their wallet.
  ///
  /// The `key` bytes contains an unsigned [xmtp.PublicKey] of the
  /// identity key to be created.
  ///
  /// The resulting signature is then published to prove that the
  /// identity key is authorized on behalf of the wallet.
  ///
  /// See [AuthorizingEthPrivateKey.createIdentity]
  static String createIdentity(List<int> key) =>
      "XMTP : Create Identity\n${_bytesToHex(key)}\n\nFor more info: https://xmtp.org/signatures/";

  /// This is the text that users sign when they want to save (encrypt)
  /// or to load (decrypt) keys using the network private storage.
  ///
  /// The `key` bytes contains the `walletPreKey` of the encrypted bundle.
  ///
  /// The resulting signature is the shared secret used to encrypt and
  /// decrypt the saved keys.
  ///
  /// See [AuthorizingEthPrivateKey.enableIdentitySaving]
  /// See [AuthorizingEthPrivateKey.enableIdentityLoading]
  static String enableIdentity(List<int> key) =>
      "XMTP : Enable Identity\n${_bytesToHex(key)}\n\nFor more info: https://xmtp.org/signatures/";

  static _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join("");
}
