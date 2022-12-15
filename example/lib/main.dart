import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:web3dart/credentials.dart';

import 'router.dart';
import 'session.dart';

void main() async {
  // A real app would use an elsewhere connected account.
  // For this demo, we just generate a random wallet on launch.
  var wallet = EthPrivateKey.createRandom(Random.secure());
  await initSession(wallet);

  _monitorTotalUnreadBadge();
  runApp(const XmtpApp());
}

class XmtpApp extends HookWidget {
  const XmtpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'XMTP',
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      routerConfig: createRouter(),
    );
  }
}

/// Update the app badge when the number of unread messages changes.
void _monitorTotalUnreadBadge() {
  session.watchTotalNewMessageCount().listen((count) {
    if (count > 0) {
      FlutterAppBadger.updateBadgeCount(count);
    } else {
      FlutterAppBadger.removeBadge();
    }
  });
}
