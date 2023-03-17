import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../session/foreground_session.dart';
import '../wallet.dart';

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
    useListenable(wallet);
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton(
                child: const Text('Connect Wallet'),
                onPressed: () async {
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (BuildContext context) => const _BottomQrModal(),
                  );
                  try {
                    if (!wallet.wc.connected) {
                      await wallet.connect();
                    }
                    if (wallet.wc.session.accounts.isEmpty) {
                      throw Exception('No accounts connected');
                    }
                    await session.authorize(wallet.asSigner());
                    // ignore: use_build_context_synchronously
                    context.goNamed('home');
                  } catch (err) {
                    Navigator.pop(context);
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

/// A sheet that slides up with buttons for the current [WalletConnect] session.
///
/// It shows buttons for Rainbow and Metamask wallets alongside a QR code.
class _BottomQrModal extends HookWidget {
  const _BottomQrModal({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    useListenable(wallet);
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Tap your wallet app to connect'),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _WalletIconButton(
                name: "Metamask",
                logoId: "5195e9db-94d8-4579-6f11-ef553be95100",
                makeUri: (uri) => "metamask://wc?uri=$uri",
              ),
              _WalletIconButton(
                name: "Rainbow",
                logoId: "7a33d7f1-3d12-4b5c-f3ee-5cd83cb1b500",
                makeUri: (uri) => "rainbow://wc?uri=$uri",
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('Or scan to connect your wallet'),
          IconButton(
            tooltip: "QR Code",
            padding: const EdgeInsets.all(0),
            icon: QrImage(
              data: wallet.displayUri,
              version: QrVersions.auto,
              // foregroundColor: Colors.deepPurple.shade900,
              size: 200.0,
            ),
            iconSize: 200,
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: wallet.displayUri)),
          ),
          const Text('Tap to copy to clipboard.'),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// Create your WalletConnect project at https://cloud.walletconnect.com/
const String _wcProjectId = "af3346694438a7a937ee3aee9968e8fa";

String _wcLogo(logoId, {size = "md"}) =>
    "https://explorer-api.walletconnect.com/v3/logo/$size/$logoId"
    "?projectId=$_wcProjectId";

/// A button displaying a WalletConnect wallet that can be tapped to connect.
///
/// Find the wallets at https://explorer.walletconnect.com/?type=wallet
/// See also https://docs.walletconnect.com/2.0/cloud/explorer#logos
class _WalletIconButton extends HookWidget {
  final String name;
  final String logoId;
  final String Function(String uri) makeUri;

  const _WalletIconButton({
    Key? key,
    required this.name,
    required this.logoId,
    required this.makeUri,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: name,
      iconSize: 100,
      onPressed: () => launchUrl(
        Uri.parse(makeUri(wallet.displayUri)),
        mode: LaunchMode.externalNonBrowserApplication,
      ),
      icon: Image.network(_wcLogo(logoId)),
    );
  }
}
