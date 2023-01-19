import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

const sdkVersion = '0.0.1';
const clientVersion = "xmtp-flutter/$sdkVersion";
// TODO: consider generating these ^ during build.

/// This is an instance of the [xmtp.MessageApiClient] with some
/// metadata helpers (e.g. for setting the authorization token).
class Api {
  final xmtp.MessageApiClient client;
  final grpc.ClientChannel _channel;
  final _MetadataManager _metadata;

  Api._(this._channel, this.client, this._metadata);

  factory Api.create({
    String host = 'dev.xmtp.network',
    int port = 5556,
    bool isSecure = true,
    bool debugLogRequests = kDebugMode,
    String appVersion = "dev/0.0.0-development",
  }) {
    var channel = grpc.ClientChannel(
      host,
      port: port,
      options: grpc.ChannelOptions(
        credentials: isSecure
            ? const grpc.ChannelCredentials.secure()
            : const grpc.ChannelCredentials.insecure(),
        userAgent: clientVersion,
      ),
    );

    return Api.createAdvanced(
      channel,
      options: grpc.CallOptions(
        timeout: const Duration(minutes: 5),
        // TODO: consider supporting compression
        // compression: const grpc.GzipCodec(),
      ),
      interceptors: debugLogRequests ? [_DebugLogInterceptor()] : [],
      appVersion: appVersion,
    );
  }

  factory Api.createAdvanced(
    grpc.ClientChannel channel, {
    grpc.CallOptions? options,
    Iterable<grpc.ClientInterceptor>? interceptors,
    String appVersion = "",
  }) {
    var metadata = _MetadataManager();
    options = grpc.CallOptions(
      providers: [metadata.provideCallMetadata],
    ).mergedWith(options);
    var client = xmtp.MessageApiClient(
      channel,
      options: options,
      interceptors: interceptors,
    );
    metadata.appVersion = appVersion;
    return Api._(channel, client, metadata);
  }

  void clearAuthTokenProvider() {
    _metadata.authTokenProvider = null;
  }

  void setAuthTokenProvider(FutureOr<String> Function() authTokenProvider) {
    _metadata.authTokenProvider = authTokenProvider;
  }

  Future<void> terminate() async {
    return _channel.terminate();
  }
}

/// This controls the metadata that is attached to every API request.
class _MetadataManager {
  FutureOr<String> Function()? authTokenProvider;
  String appVersion = "";

  /// This adheres to the [grpc.MetadataProvider] interface
  /// to provide custom metadata on each call.
  Future<void> provideCallMetadata(
      Map<String, String> metadata, String uri) async {
    metadata['x-client-version'] = clientVersion;
    if (appVersion.isNotEmpty) {
      metadata['x-app-version'] = appVersion;
    }
    var authToken = authTokenProvider == null ? "" : await authTokenProvider!();
    if (authToken.isNotEmpty) {
      metadata['authorization'] = 'Bearer $authToken';
    }
  }
}

/// If true, then the API debug logger includes the topic names
/// requested by each API call.
/// Note: this has no effect if the debug logger is not enabled.
/// See `debugLogRequests` above.
bool isDebugLoggingTopics = kDebugMode;

/// This logs all API requests.
/// See `debugLogRequests` above.
class _DebugLogInterceptor extends grpc.ClientInterceptor {
  int _count = 1;

  @override
  grpc.ResponseFuture<R> interceptUnary<Q, R>(
    grpc.ClientMethod<Q, R> method,
    Q request,
    grpc.CallOptions options,
    grpc.ClientUnaryInvoker<Q, R> invoker,
  ) {
    final reqN = _nextReqN();
    debugPrint('xmtp: #$reqN --> ${method.path}');
    if (isDebugLoggingTopics) {
      if (request is xmtp.PublishRequest) {
        for (var e in request.envelopes) {
          debugPrint(' topic: ${e.contentTopic}');
        }
      }
      if (request is xmtp.QueryRequest) {
        for (var topic in request.contentTopics) {
          debugPrint(' topic: $topic');
        }
      }
    }
    var res = invoker(method, request, options);
    res.then((_) => debugPrint('xmtp: <-- #$reqN ${method.path}'));
    return res;
  }

  @override
  grpc.ResponseStream<R> interceptStreaming<Q, R>(
    grpc.ClientMethod<Q, R> method,
    Stream<Q> requests,
    grpc.CallOptions options,
    grpc.ClientStreamingInvoker<Q, R> invoker,
  ) {
    final reqN = _nextReqN();
    debugPrint('xmtp: #$reqN <-> ${method.path}');
    if (isDebugLoggingTopics) {
      requests.single.then((req) {
        debugPrint(
            ' topic: ${(req as xmtp.SubscribeRequest).contentTopics.first}');
      });
    }
    return invoker(method, requests, options);
  }

  String _nextReqN() {
    final reqCount = _count++;
    return reqCount.toRadixString(36).padLeft(3, '0');
  }
}
