import "dart:math";

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:web3modal_flutter/web3modal_flutter.dart';
import 'package:xmtp/xmtp.dart' as xmtp;

import '../Web3ModalService.dart';
import '../session/foreground_session.dart';

/// A page prompting the user to login.
///
/// The app navigates here automatically when the user session is uninitialized.
/// See [refreshListenable] and [redirect] in the app's [createRouter].
///
/// This first displays "Connect Wallet" which creates a new WalletConnect session.
/// Then it brings up a bottom-sheet modal that lists Rainbow and Metamask buttons
/// alongside a QR code that can be scanned to connect a wallet.
///
/// When the session has been successfully initialized
/// this page navigates back to the home screen.
class LoginPage extends HookWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    handleSessionConnect(BuildContext context,SessionConnect? args) async {
      try {
        var signer = w3mService.asSigner();
        await session.authorize(signer);
        context.goNamed('home');
      }
      catch(e){
        print('Errorf: $e');
      }
    }
    useEffect(() {
      w3mService.init(callback: (args) => handleSessionConnect(context, args));
      return () {
      };
    }, []);
    useListenable(w3mService);

    var service = w3mService.w3mService;
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              W3MConnectWalletButton(service: service),
              ElevatedButton(
                child: const Text('Create Random Wallet'),
                onPressed: () async {
                  try {
                    var signer =
                        EthPrivateKey.createRandom(Random.secure()).asSigner();
                    await session.authorize(signer);
                    context.goNamed('home');
                  } catch (e) {
                    print('Errorf: $e');
                  }
                },
              ),
              ElevatedButton(
                child: const Text('Start from Private Key'),
                onPressed: () async {
                  try {
                    var wallet =
                        EthPrivateKey.fromHex('your_private_key').asSigner();
                    await session.authorize(wallet);
                    context.goNamed('home');
                  } catch (e) {
                    print('Errorf: $e');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}


