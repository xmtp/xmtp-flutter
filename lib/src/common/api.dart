import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:xmtp_proto/xmtp_proto.dart' as xmtp;

const sdkVersion = '1.1.0';
const clientVersion = "xmtp-flutter/$sdkVersion";
// TODO: consider generating these ^ during build.

/// The maximum number of requests permitted in a single batch call.
/// The conversation managers use this to automatically partition calls.
const maxQueryRequestsPerBatch = 50;

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

class Pagination {
  final DateTime? start;
  final DateTime? end;
  final int? limit;
  final xmtp.SortDirection? sort;

  Pagination(this.start, this.end, this.limit, this.sort);
}

extension QueryPaginator on xmtp.MessageApiClient {
  /// This is a helper for paginating through a full query.
  /// It yields all the envelopes in the query using the paging info
  /// from the prior response to fetch the next page.
  Stream<xmtp.Envelope> envelopes(xmtp.QueryRequest req) async* {
    xmtp.QueryResponse res;
    do {
      res = await query(req);
      for (var envelope in res.envelopes) {
        yield envelope;
      }
      req.pagingInfo.cursor = res.pagingInfo.cursor;
    } while (res.envelopes.isNotEmpty && res.pagingInfo.hasCursor());
  }

  /// This is a helper for paginating through a full batch of queries.
  /// It yields all the envelopes in the queries using the paging info
  /// from the prior responses to fetch the next page for the entire batch.
  /// Note: the caller is responsible for merging and sorting the results.
  Stream<xmtp.Envelope> batchEnvelopes(xmtp.BatchQueryRequest bReq) async* {
    do {
      var reqByTopic = {
        for (var req in bReq.requests) req.contentTopics.first: req
      };
      var bRes = await batchQuery(bReq);
      var requests = <xmtp.QueryRequest>[];
      for (var res in bRes.responses) {
        for (var envelope in res.envelopes) {
          yield envelope;
        }
        if (res.envelopes.isNotEmpty && res.pagingInfo.hasCursor()) {
          var req = reqByTopic[res.envelopes.first.contentTopic]!;
          req.pagingInfo.cursor = res.pagingInfo.cursor;
          requests.add(req);
        }
      }
      bReq.requests.clear();
      bReq.requests.addAll(requests);
    } while (bReq.requests.isNotEmpty);
  }
}

/// Creates a [Comparator] that implements the [sort] over [xmtp.Envelope].
Comparator<xmtp.Envelope> envelopeComparator(xmtp.SortDirection? sort) =>
    (e1, e2) => sort == xmtp.SortDirection.SORT_DIRECTION_ASCENDING
        ? e1.timestampNs.compareTo(e2.timestampNs)
        : e2.timestampNs.compareTo(e1.timestampNs);

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
    final clock = Stopwatch()..start();
    debugPrint('xmtp: #$reqN --> ${method.path}');
    if (isDebugLoggingTopics) {
      if (request is xmtp.PublishRequest) {
        for (var e in request.envelopes) {
          debugPrint('  topic: ${e.contentTopic}');
        }
      }
      if (request is xmtp.QueryRequest) {
        for (var topic in request.contentTopics.take(3)) {
          debugPrint('  topic: $topic');
        }
        var more = request.contentTopics.length - 3;
        if (more > 0) {
          debugPrint('         ... and $more more');
        }
        if (request.hasStartTimeNs()) {
          debugPrint('  start: ${request.startTimeNs}');
        }
        if (request.hasEndTimeNs()) {
          debugPrint('    end: ${request.startTimeNs}');
        }
        if (request.hasPagingInfo()) {
          if (request.pagingInfo.hasLimit()) {
            debugPrint('  limit: ${request.pagingInfo.limit}');
          }
          if (request.pagingInfo.hasDirection()) {
            debugPrint('    dir: ${request.pagingInfo.direction}');
          }
          if (request.pagingInfo.hasCursor()) {
            debugPrint(' cursor: ${request.pagingInfo.cursor.whichCursor()}');
          }
        }
      }
    }
    var res = invoker(method, request, options);
    res.then((_) => debugPrint(
        'xmtp: <-- #$reqN ${method.path} ${clock.elapsedMilliseconds} ms'));
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
        var topics = (req as xmtp.SubscribeRequest).contentTopics;
        debugPrint(' topic: ${topics.isEmpty ? "(none)" : topics.first}');
      });
    }
    return invoker(method, requests, options);
  }

  String _nextReqN() {
    final reqCount = _count++;
    return reqCount.toRadixString(36).padLeft(3, '0');
  }
}
