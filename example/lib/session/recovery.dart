import 'dart:async';
import 'dart:math';

import 'package:retry/retry.dart';

/// Manager of recover attempts that enforces exponential backoff.
///
/// This allows attempts to recover to happen eventually,
/// but not too aggressively.
///
/// It tracks the number of recent attempts and uses that as the
/// exponent when delaying the next attempt.
///
/// All attempts are uniquely named and can be later cancelled by name.
class Recovery {
  final Map<String, Timer> _attempts = {};
  final RetryOptions _config = const RetryOptions();

  /// This is an expiring stack whose height is the number of recent attempts.
  /// See [_incrementRecentCount].
  final List<DateTime> _recentStack = [];

  /// Attempts the named recovery method after some backoff-dependent delay.
  ///
  /// The delay is calculated using exponential backoff where the number of
  /// streams that have recently attempted to recover is used as the exponent.
  ///
  /// The maximum delay is 30 seconds.
  /// See [RetryOptions] from https://pub.dev/packages/retry
  void attempt(String name, void Function() doRecovery) =>
      _attempts[name] ??= Timer(_config.delay(_incrementRecentCount()), () {
        _attempts.remove(name);
        doRecovery();
      });

  /// Cancel the named recovery attempt.
  void cancel(String name) => _attempts.remove(name)?.cancel();

  /// Reset the recovery system.
  void reset() {
    for (var timer in _attempts.values) {
      timer.cancel();
    }
    _attempts.clear();
    _recentStack.clear();
  }

  /// Add to the number of recent attempts and return the current count.
  ///
  /// This maintains the expiring count of recent attempts.
  /// "Recent" means during the last [maxDelay].
  ///
  /// The result will never exceed [maxAttempts].
  int _incrementRecentCount() {
    var now = DateTime.now();
    _recentStack
      ..insert(0, now)
      // Remove all not-recent attempts.
      ..removeWhere((t) => t.isBefore(now.subtract(_config.maxDelay)))
      // And also trim it to the maximum count.
      ..length = min(_recentStack.length, _config.maxAttempts);
    return _recentStack.length;
  }
}
