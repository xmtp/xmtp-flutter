import 'dart:convert';
import 'dart:ffi';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/open.dart';

/// Tell sqlite3 where find the SQLCipher plugin.
///
/// See https://drift.simonbinder.eu/docs/other-engines/encryption/#encrypted-version-of-a-nativedatabase
configureSqlCipherLibraries() {
  WidgetsFlutterBinding.ensureInitialized();
  open
    ..overrideFor(
      OperatingSystem.iOS,
      () => DynamicLibrary.process(),
    )
    ..overrideFor(
      OperatingSystem.android,
      () => DynamicLibrary.open('libsqlcipher.so'),
    );
}

/// Configure the [database] to use the encryption [key].
///
/// Throws if the [key] is wrong or the database does not
/// have the SQLCipher plugin.
configureSqlCipherDatabase(CommonDatabase database, String key) {
  // First make sure the database supports encryption.
  final result = database.select('pragma cipher_version');
  if (result.isEmpty) {
    throw UnsupportedError('missing SQLCipher plugin');
  }
  // Then set the encryption key.
  database.execute("pragma key = '$key'");

  // Finally, make sure it worked (this throws if the key was wrong).
  database.execute('select count(*) from sqlite_master');
}

final _rand = Random.secure();

/// Get or create the database encryption key.
///
/// When it doesn't already exist a random new one is generated.
///
/// The key is stored in the platform's application preferences:
/// `NSUserDefaults` (on iOS) or `SharedPreferences` (on Android).
Future<String> getOrCreateEncryptionKey() async {
  var prefs = await SharedPreferences.getInstance();
  if (prefs.containsKey('db.encryption.key')) {
    return prefs.getString('db.encryption.key')!;
  }
  var bytes = List.generate(32, (_) => _rand.nextInt(256));
  var key = base64.encode(bytes).replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  await prefs.setString('db.encryption.key', key);
  return key;
}
