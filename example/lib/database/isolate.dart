import 'dart:io';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:drift/isolate.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// This connects to the database isolate.
/// If the isolate does not exist, this spawns it.
Future<DatabaseConnection> connectToDatabase(final String dbName) async {
  // First we check if the isolate already exists.
  var alreadyExists = IsolateNameServer.lookupPortByName(dbName);
  if (alreadyExists != null) {
    return DriftIsolate.fromConnectPort(alreadyExists).connect();
  }

  // Otherwise we need to spawn a new one.
  final token = RootIsolateToken.instance;
  var dbIsolate = await DriftIsolate.spawn(() => LazyDatabase(() async {
        BackgroundIsolateBinaryMessenger.ensureInitialized(token!);
        var dbFolder = await getApplicationDocumentsDirectory();
        var path = p.join(dbFolder.path, dbName);
        return NativeDatabase(File(path));
      }));

  // Save the spawned isolate so we can find it later.
  IsolateNameServer.registerPortWithName(
    dbIsolate.connectPort,
    dbName,
  );
  return dbIsolate.connect();
}
