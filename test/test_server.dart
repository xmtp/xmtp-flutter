import 'package:xmtp/src/common/api.dart';

/// This contains configuration for the test server.
/// It pulls from the environment so we can configure it for CI.

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
