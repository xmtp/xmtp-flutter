import 'package:fixnum/fixnum.dart';

/// This contains helpers for dealing with Int64 timestamps.
/// It handles converting between timestamps in these forms:
///  - integer milliseconds since epoch
///  - integer nanoseconds since epoch
///  - DateTime

/// This produces the current time in nanoseconds since the epoch.
/// NOTE: resolution is <= 1 microsecond
Int64 nowNs() => Int64(DateTime.now().microsecondsSinceEpoch) * 1000;

/// This produces the current time in milliseconds since the epoch.
Int64 nowMs() => Int64(DateTime.now().millisecondsSinceEpoch);

/// This marks the limit where we start treating a timestamp as nanoseconds.
/// Legacy payloads include a mix of milliseconds and nanosecond timestamps.
/// We use this threshold to guess which one it is.
const _nsThreshold = 1000000000000000000; // 1e18

/// This adds helpers to [Int64] to help deal with ambiguous timestamps.
extension DateTimeInt64 on Int64 {
  DateTime toDateTime() => this > _nsThreshold
      ? DateTime.fromMicrosecondsSinceEpoch(toInt() ~/ 1000)
      : DateTime.fromMillisecondsSinceEpoch(toInt());

  Int64 toMs() => this > _nsThreshold ? this ~/ 1000000 : this;

  Int64 toNs() => this > _nsThreshold ? this : this * 1000000;
}

/// This adds helpers to [DateTime] produce [Int64] timestamps.
extension Int64DateTime on DateTime {
  Int64 toMs64() => Int64(millisecondsSinceEpoch);

  Int64 toNs64() => Int64(microsecondsSinceEpoch) * 1000;
}
