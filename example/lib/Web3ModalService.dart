import 'package:flutter/cupertino.dart';
import 'package:web3modal_flutter/web3modal_flutter.dart';
import 'package:xmtp/xmtp.dart' as xmtp;

const PROJECT_ID = 'af3346694438a7a937ee3aee9968e8fa';// change this to your project id, for more info visit https://cloud.walletconnect.com/

final Web3ModalService w3mService = Web3ModalService._();

class Web3ModalService extends ChangeNotifier {
  W3MService w3mService;
  void Function(SessionConnect?)? onSessionConnectCallback;

  Web3ModalService._()
      : w3mService = W3MService(
          projectId: PROJECT_ID,
          metadata: const PairingMetadata(
            name: 'XMTP.org',
            description: 'XMTP Flutter Example',
            url: 'https://www.xmtp.org/',
            icons: ['https://avatars.githubusercontent.com/u/82580170?s=48&v=4'],
            redirect: Redirect(
              native: 'xmtp-example-wc://request',
              universal: 'https://www.walletconnect.com',
            ),
          ),
        );

  void init({required void Function(SessionConnect?) callback}) async {
    onSessionConnectCallback = callback;
    await w3mService.init();
    w3mService.onSessionConnectEvent.subscribe(_onSessionConnect);
    w3mService.onSessionUpdateEvent.subscribe((args) { notifyListeners(); });
    w3mService.onSessionExpireEvent.subscribe((args) { notifyListeners(); });
    w3mService.onSessionDeleteEvent.subscribe((args) { notifyListeners(); });


  }

  xmtp.Signer asSigner() {
    var address = w3mService.session?.address;
    debugPrint('address: $address');
    w3mService.launchConnectedWallet();
    return xmtp.Signer.create(
        address!,
        (text) => w3mService.web3App!.request(
          topic: w3mService.session!.topic!,
          chainId: 'eip155:1',
          request: SessionRequestParams(
              method: 'personal_sign', params: [text, address]),
        ).then((answer) =>
            hexToBytes(answer)
        )
    );
  }

  sendSignReq(text, address) {
    w3mService.web3App!.request(
      topic: w3mService.session!.topic!,
      chainId: 'eip155:1',
      request: SessionRequestParams(
          method: 'personal_sign', params: [text, address]),
    ).then((answer) =>
      hexToBytes(answer)
    );

  }

  void _onSessionConnect(SessionConnect? args) {
    debugPrint('[$runtimeType] _onSessionConnect $args');
    if (onSessionConnectCallback != null) {
      onSessionConnectCallback!(args);
    }
  }


}
