import 'package:flutter/foundation.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:web3dart/crypto.dart';
import 'package:xmtp/xmtp.dart' as xmtp;

/// The ambient [Wallet] used if the user needs to authenticate.
final Wallet wallet = Wallet._().._init();

/// A [WalletConnect] wrapper that notifies of changes.
///
/// It can be used [asSigner] when initializing an [xmtp.Client].
///
/// This class is a singleton, and should be accessed via [wallet].
///
/// When a user needs to authenticate they can [connect] to begin
/// a new WalletConnect session. Updates for the session will notify
/// listeners to the [Wallet].
class Wallet extends ChangeNotifier {
  final WalletConnect wc;
  String displayUri = '';

  Wallet._()
      : wc = WalletConnect(
          bridge: 'https://bridge.walletconnect.org',
          clientMeta: const PeerMeta(
            name: 'XMTP Flutter Example',
            description: 'An XMTP example app.',
            url: 'https://xmtp.org',
            icons: ['https://xmtp.vercel.app/xmtp-icon.png'],
          ),
        );

  /// Register the listeners with the [WalletConnect] instance.
  void _init() {
    wc.registerListeners(
      onConnect: onConnectRequest,
      onSessionUpdate: onSessionUpdate,
      onDisconnect: onDisconnect,
    );
  }

  /// Initiate a new [WalletConnect] session.
  Future<SessionStatus> connect() =>
      wc.createSession(onDisplayUri: onDisplayUri);

  /// Adapt the connected [WalletConnect] session as an [xmtp.Signer]
  /// for use when initializing an [xmtp.Client].
  xmtp.Signer asSigner() {
    if (wc.session.accounts.isEmpty) {
      throw WalletConnectException("no accounts available for signing");
    }
    var address = wc.session.accounts.first;
    return xmtp.Signer.create(
        address,
        (text) => wc.sendCustomRequest(
              method: "personal_sign",
              params: [text, address],
            ).then((res) => hexToBytes(res)));
  }

  void onConnectRequest(SessionStatus status) {
    debugPrint("Wallet: onConnectRequest $status");
    notifyListeners();
  }

  void onSessionUpdate(WCSessionUpdateResponse response) {
    debugPrint("Wallet: onSessionUpdate $response");
    notifyListeners();
  }

  void onDisconnect() {
    debugPrint("Wallet: onDisconnect");
    notifyListeners();
  }

  void onDisplayUri(String uri) {
    debugPrint("Wallet: onDisplayUri $uri");
    displayUri = uri;
    notifyListeners();
  }
}
