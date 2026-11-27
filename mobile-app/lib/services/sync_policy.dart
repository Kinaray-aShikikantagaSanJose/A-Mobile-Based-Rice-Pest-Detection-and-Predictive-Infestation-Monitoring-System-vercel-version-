// Pure rules for sending queued work, kept apart from sqflite and HTTP so
// they can be unit-tested.

/// The automatic sync runs at least this often while the app is open.
const Duration kSyncInterval = Duration(minutes: 3);

/// First wait after a failed sync (no signal, server error).
const Duration kFirstBackoff = Duration(seconds: 30);

/// How long to wait before the next automatic try after [failures]
/// consecutive transient failures: 30 s, 1 min, 2 min, then the regular
/// 3-minute interval (never longer).
Duration backoffDelay(int failures) {
  if (failures <= 0) return Duration.zero;
  final seconds = kFirstBackoff.inSeconds * (1 << (failures - 1).clamp(0, 10));
  final capped = seconds > kSyncInterval.inSeconds ? kSyncInterval.inSeconds : seconds;
  return Duration(seconds: capped);
}

/// Whether an item waiting on the phone goes out in this run. Items the
/// server refused ([lastError] set, e.g. invalid data) are not re-sent by
/// the automatic sync, because they would be refused again on every run;
/// only an explicit "Try sending now" ([retryRefused]) sends them again.
bool shouldSend(String lastError, {required bool retryRefused}) => retryRefused || lastError.trim().isEmpty;

/// The items of [items] that go out in this run (see [shouldSend]).
List<T> itemsToSend<T>(Iterable<T> items, String Function(T) lastError, {required bool retryRefused}) =>
    [for (final i in items) if (shouldSend(lastError(i), retryRefused: retryRefused)) i];

/// Consecutive transient failures and when the next automatic run may start.
/// Explicit actions (pull to refresh, "Send now", connection back, app
/// resumed) run at once regardless; they still count toward the backoff.
class SyncBackoff {
  int _failures = 0;
  DateTime? _notBefore;

  int get failures => _failures;
  DateTime? get notBefore => _notBefore;

  /// An automatic run may start at [now].
  bool allows(DateTime now) => _notBefore == null || !now.isBefore(_notBefore!);

  /// A run failed for a reason that may pass (signal, server). Returns how
  /// long to wait before trying again automatically.
  Duration failed(DateTime now) {
    _failures++;
    final wait = backoffDelay(_failures);
    _notBefore = now.add(wait);
    return wait;
  }

  /// A run reached the server: back to the regular schedule.
  void succeeded() {
    _failures = 0;
    _notBefore = null;
  }
}
