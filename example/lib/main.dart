import 'package:flutter/material.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import 'router.dart';
import 'session/foreground_session.dart';

void main() async {
  /// If they have saved credentials, initialize the session.
  /// If not they will be sent to the login page instead.
  await session.loadSaved();
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
  if (!session.initialized) {
    return;
  }
  session.watchTotalNewMessageCount().listen((count) {
    if (count > 0) {
      FlutterAppBadger.updateBadgeCount(count);
    } else {
      FlutterAppBadger.removeBadge();
    }
  });
}
