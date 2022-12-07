import 'package:xmtp/src/common/api.dart';

/// This contains configuration for the test server.
/// It pulls from the environment so we can configure it for CI.
///  e.g. flutter test --dart-define=TEST_SERVER_ENABLED=true

const testServerHost = String.fromEnvironment(
  "TEST_SERVER_HOST",
  defaultValue: "127.0.0.1",
);

const testServerPort = int.fromEnvironment(
  "TEST_SERVER_PORT",
  defaultValue: 5556,
);

const testServerIsSecure = bool.fromEnvironment(
  "TEST_SERVER_IS_SECURE",
  defaultValue: false,
);

const testServerEnabled = bool.fromEnvironment(
  "TEST_SERVER_ENABLED",
  defaultValue: false,
);

/// Use this as the `skip: ` value on a test to skip the test
/// when the test server is not enabled.
/// Using this (instead of just `!testServerEnabled`) will print
/// the note explaining why it was skipped.
const skipUnlessTestServerEnabled =
    !testServerEnabled ? "This test depends on the test server" : false;

/// This creates an [Api] configured to talk to the test server.
Api createTestServerApi() {
  if (!testServerEnabled) {
    throw StateError("XMTP server tests are not enabled.");
  }
  return Api.create(
    host: testServerHost,
    port: testServerPort,
    isSecure: testServerIsSecure,
  );
}
