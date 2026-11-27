import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../controllers/auth_controller.dart';
import '../l10n/app_language.dart';
import '../models/record.dart';
import '../platform/local_files.dart';
import '../utils/formatters.dart';
import 'api_client.dart';
import 'local_store.dart';
import 'notification_service.dart';
import 'sync_policy.dart';
import '../utils/api_config.dart';

/// Result of submitting an observation.
class SubmitOutcome {
  final Record record;

  /// False = saved on the phone, waiting for signal.
  final bool uploaded;

  /// Set when the server refused it (e.g. invalid data); it stays on the phone.
  final String? error;

  const SubmitOutcome(this.record, {required this.uploaded, this.error});
}

class AppNotification {
  final int id;
  final int? scanId;
  final String kind, title, body, createdAt;
  final bool read;
  const AppNotification(this.id, this.scanId, this.kind, this.title, this.body, this.createdAt, this.read);
}

class LevelSuggestion {
  final String level;
  final List<String> reasons;
  final List<String> availableIndicators;

  /// The threshold for this pest and stage is not confirmed by an
  /// agriculturist yet.
  final bool provisional;

  /// English indicator (the value sent back) -> label in the app language.
  final Map<String, String> indicatorLabels;
  const LevelSuggestion(this.level, this.reasons, this.availableIndicators,
      {this.provisional = false, this.indicatorLabels = const {}});

  factory LevelSuggestion.fromJson(Map<String, dynamic> data) => LevelSuggestion(
        data['level'] as String? ?? '',
        [for (final r in data['reasons'] as List? ?? const []) '$r'],
        [for (final i in data['available_indicators'] as List? ?? const []) '$i'],
        provisional: data['provisional'] == true,
        indicatorLabels: {
          for (final e in (data['indicator_labels'] as Map? ?? const {}).entries) '${e.key}': '${e.value}',
        },
      );

  /// What to show for the English [indicator].
  String labelFor(String indicator) {
    final l = indicatorLabels[indicator];
    return l == null || l.trim().isEmpty ? tr(indicator) : l;
  }
}

/// An approved option in the treatment library (GET /dashboard/library).
class LibraryOption {
  final int id;
  final String pest, optionType, title, recommendation, status;
  const LibraryOption(this.id, this.pest, this.optionType, this.title, this.recommendation, this.status);

  factory LibraryOption.fromJson(Map<String, dynamic> j) => LibraryOption(
        (j['id'] as num?)?.toInt() ?? 0,
        j['pest'] as String? ?? '',
        j['option_type'] as String? ?? '',
        j['title'] as String? ?? '',
        j['recommendation'] as String? ?? '',
        j['status'] as String? ?? '',
      );
}

/// Approved options a reviewer may recommend for [pest].
List<LibraryOption> approvedOptionsFor(Iterable<LibraryOption> library, String? pest) => [
      for (final o in library)
        if (o.status == 'approved' && pest != null && o.pest == pest) o,
    ];

/// A screen's data and, when it came from the phone, when it was saved.
class Loaded<T> {
  final T data;

  /// Null = fresh from the server (or saved without a time).
  final DateTime? savedAt;
  final bool fromCache;
  const Loaded(this.data, {this.savedAt, this.fromCache = false});
}

/// Random v4 UUID; the server uses it to ignore retried uploads.
String newClientUuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// Local time with its UTC offset, e.g. 2026-09-27T14:05:00+08:00.
String nowWithOffset() {
  final now = DateTime.now();
  final off = now.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final hh = off.inHours.abs().toString().padLeft(2, '0');
  final mm = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
  final base = now.toIso8601String().split('.').first;
  return '$base$sign$hh:$mm';
}

class _PhotoMissing implements Exception {
  const _PhotoMissing();
  String get message => 'The photo is no longer on this phone. Discard this observation and take it again.';
}

class SyncService {
  SyncService._();

  /// Discards an observation that could not be sent (the farmer's choice).
  static Future<void> discard(String clientUuid) async {
    await LocalStore.instance.removeObservation(clientUuid);
    revision.value++;
  }

  /// Server notifications not yet read + follow-ups that are due.
  static final ValueNotifier<int> badge = ValueNotifier<int>(0);

  /// Bumped whenever records change, so open screens can reload.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Technicians: observations waiting in their validation queue (pest + disease).
  static final ValueNotifier<int> queueCount = ValueNotifier<int>(0);
  static final Map<String, int> _queueSizes = {};

  static int _unread = 0;
  static Future<void>? _inFlight;

  /// Waits between automatic runs after failures (see sync_policy.dart).
  static final SyncBackoff backoff = SyncBackoff();
  static Timer? _retryTimer;

  /// Uploads in progress, by client_uuid: a sync and a submit of the same
  /// observation share one request instead of sending it twice.
  static final Map<String, Future<Record>> _uploads = {};

  /// Bumped when an upload saves a record, so a sync that fetched the list
  /// before that doesn't overwrite it with an older copy.
  static int _saves = 0;

  static bool _transient(ApiException e) => e.isOffline || e.statusCode == 401 || (e.statusCode ?? 0) >= 500;

  static bool get _canSync {
    final auth = AuthControllerImpl.instance;
    return auth.isLoggedIn && auth.isApproved;
  }

  // ---------------------------------------------------------------- observations

  static Map<String, String> _fields(OutboxObservation o) => {
        'client_uuid': o.clientUuid,
        'report_type': o.reportType,
        'crop_stage': o.cropStage,
        'created_at': o.createdAt,
        if (o.lat != null && o.lng != null) 'lat': o.lat!.toString(),
        if (o.lat != null && o.lng != null) 'lng': o.lng!.toString(),
        'monitoring_method': o.method,
        'trap_type': o.trapType,
        'target_pest': o.targetPest,
        'target_sex': o.targetSex,
        'notes': o.notes,
        'land_type': o.landType,
        if (o.elevationM != null) 'elevation_m': o.elevationM!.toString(),
        if (o.lat != null && o.gpsAccuracyM != null) 'gps_accuracy': o.gpsAccuracyM!.toStringAsFixed(1),
        if (o.followUpOf != null) 'follow_up_of': '${o.followUpOf}',
        if (o.resubmissionOf != null) 'resubmission_of': '${o.resubmissionOf}',
      };

  static Future<Record> _upload(OutboxObservation o) =>
      _uploads[o.clientUuid] ??= _doUpload(o).whenComplete(() => _uploads.remove(o.clientUuid));

  static Future<Record> _doUpload(OutboxObservation o) async {
    if (!await localFileExists(o.imagePath)) {
      throw const _PhotoMissing();
    }
    final data = await ApiClient.upload('/sync/scans', _fields(o), o.imagePath) as Map<String, dynamic>;
    await LocalStore.instance.saveRecord(data);
    _saves++;
    return Record(server: data, localPhoto: o.imagePath);
  }

  /// Saves the observation on the phone first, then tries to send it now.
  /// Offline, it stays in the outbox and goes out automatically later.
  static Future<SubmitOutcome> submit(OutboxObservation o) async {
    await LocalStore.instance.addObservation(o);
    revision.value++;
    try {
      final rec = await _upload(o);
      revision.value++;
      // A follow-up changes the treated record ("How is the field now?" is
      // answered): refresh the cache so the prompt goes away.
      if (o.followUpOf != null) unawaited(syncAll());
      return SubmitOutcome(rec, uploaded: true);
    } on ApiException catch (e) {
      if (_transient(e)) {
        return SubmitOutcome(Record(pending: o, localPhoto: o.imagePath), uploaded: false);
      }
      await LocalStore.instance.setObservationError(o.clientUuid, e.message);
      return SubmitOutcome(Record(pending: o, localPhoto: o.imagePath), uploaded: false, error: e.message);
    } on _PhotoMissing catch (e) {
      await LocalStore.instance.setObservationError(o.clientUuid, e.message);
      return SubmitOutcome(Record(pending: o, localPhoto: o.imagePath), uploaded: false, error: e.message);
    } catch (e) {
      // Unexpected (e.g. storage): it stays in the outbox and is retried.
      debugPrint('[Sync] submit failed: $e');
      return SubmitOutcome(Record(pending: o, localPhoto: o.imagePath), uploaded: false);
    }
  }

  /// Uploads everything waiting, then refreshes records and the badge.
  /// Concurrent callers share one run. Never throws.
  ///
  /// Automatic runs wait out the backoff after failures and skip items the
  /// server refused. [force] (the person pulled to refresh, the connection
  /// came back, the app was resumed) runs now; [retryRefused] ("Send now",
  /// "Try sending now") also sends refused items once more.
  static Future<void> syncAll({bool force = false, bool retryRefused = false}) {
    if (_inFlight != null) return _inFlight!;
    if (!force && !retryRefused && !backoff.allows(DateTime.now())) return Future.value();
    return _inFlight = _syncAll(retryRefused: retryRefused).whenComplete(() => _inFlight = null);
  }

  static Future<void> _syncAll({bool retryRefused = false}) async {
    if (!_canSync) return;
    var transient = false;
    try {
      // One item failing never blocks the others; only no signal or a
      // signed-out session stops the run.
      final observations = itemsToSend(await LocalStore.instance.pendingObservations(), (o) => o.lastError,
          retryRefused: retryRefused);
      for (final o in observations) {
        try {
          await _upload(o);
        } on ApiException catch (e) {
          if (e.isOffline || e.statusCode == 401) {
            transient = true;
            return;
          }
          if ((e.statusCode ?? 0) >= 500) {
            debugPrint('[Sync] server error for ${o.clientUuid}: ${e.message}');
            transient = true;
            continue; // try again next time
          }
          await LocalStore.instance.setObservationError(o.clientUuid, e.message);
        } on _PhotoMissing catch (e) {
          await LocalStore.instance.setObservationError(o.clientUuid, e.message);
        } catch (e) {
          debugPrint('[Sync] upload of ${o.clientUuid} failed: $e');
        }
      }
      final treatments = itemsToSend(await LocalStore.instance.pendingTreatments(), (t) => t.lastError,
          retryRefused: retryRefused);
      for (final t in treatments) {
        try {
          await _sendTreatment(t);
        } on ApiException catch (e) {
          if (e.isOffline || e.statusCode == 401) {
            transient = true;
            return;
          }
          if ((e.statusCode ?? 0) >= 500) {
            transient = true;
            continue;
          }
          // Refused (e.g. the record changed): keep it on the phone with the
          // reason, shown on its record, instead of dropping it silently.
          debugPrint('[Sync] treatment refused: ${e.message}');
          await LocalStore.instance.setTreatmentError(t.clientUuid, e.message);
        } catch (e) {
          debugPrint('[Sync] treatment ${t.clientUuid} failed: $e');
        }
      }
      // Name, picture, area or coverage may have been changed on the dashboard.
      try {
        await ApiClient.refreshProfile();
      } on ApiException catch (e) {
        if (e.isOffline) {
          transient = true;
          return;
        }
      }
      final seen = _saves;
      final mine = [for (final r in await ApiClient.get('/sync/scans/mine') as List) r as Map<String, dynamic>];
      if (_saves == seen) {
        await LocalStore.instance.replaceRecords(mine);
      } else {
        // An upload finished meanwhile: don't drop it from the cache.
        for (final r in mine) {
          await LocalStore.instance.saveRecord(r);
        }
      }
      await refreshBadge();
      await _prefetchPhotos(mine);
    } on ApiException catch (e) {
      debugPrint('[Sync] stopped: ${e.message}');
      if (_transient(e)) transient = true;
    } catch (e) {
      debugPrint('[Sync] failed: $e');
    } finally {
      _afterRun(transient: transient);
      revision.value++;
      await _updateBadge();
    }
  }

  /// After a failed run, tries again on its own after 30 s, 1 min, 2 min,
  /// ... (at most the regular 3-minute interval); a run that reached the
  /// server resets that.
  static void _afterRun({required bool transient}) {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!transient) {
      backoff.succeeded();
      return;
    }
    final wait = backoff.failed(DateTime.now());
    if (_canSync) _retryTimer = Timer(wait, () => syncAll());
  }

  /// Stops a scheduled retry (signed out).
  static void cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    backoff.succeeded();
  }

  /// "Try sending now" on one observation the server refused or that is
  /// still waiting: sends it once more and returns the server's answer, if any.
  static Future<SubmitOutcome> retryObservation(OutboxObservation o) async {
    try {
      final rec = await _upload(o);
      revision.value++;
      return SubmitOutcome(rec, uploaded: true);
    } on ApiException catch (e) {
      if (_transient(e)) return SubmitOutcome(Record(pending: o, localPhoto: o.imagePath), uploaded: false);
      await LocalStore.instance.setObservationError(o.clientUuid, e.message);
      revision.value++;
      return SubmitOutcome(Record(pending: o, localPhoto: o.imagePath), uploaded: false, error: e.message);
    } on _PhotoMissing catch (e) {
      await LocalStore.instance.setObservationError(o.clientUuid, e.message);
      revision.value++;
      return SubmitOutcome(Record(pending: o, localPhoto: o.imagePath), uploaded: false, error: e.message);
    }
  }

  /// Sends a refused treatment once more (the person asked). Returns the
  /// server's reason if it is refused again, '' if it went out, null if
  /// there is no signal.
  static Future<String?> retryTreatment(String clientUuid) async {
    final all = await LocalStore.instance.pendingTreatments();
    final t = all.where((x) => x.clientUuid == clientUuid).firstOrNull;
    if (t == null) return '';
    try {
      await _sendTreatment(t);
      return '';
    } on ApiException catch (e) {
      if (_transient(e)) return null;
      await LocalStore.instance.setTreatmentError(clientUuid, e.message);
      return e.message;
    } finally {
      revision.value++;
      await _updateBadge();
    }
  }

  /// Drops a treatment the server refused (the person's choice).
  static Future<void> discardTreatment(String clientUuid) async {
    await LocalStore.instance.removeTreatment(clientUuid);
    revision.value++;
    await _updateBadge();
  }

  /// Photos per sync run, so a phone with many records catches up gradually.
  static const int _prefetchLimit = 30;

  /// Saves the photo of each record on the phone (same files the photo
  /// widgets use), so records keep their pictures without signal.
  static Future<void> _prefetchPhotos(List<Map<String, dynamic>> records) async {
    final store = LocalStore.instance;
    var fetched = 0;
    for (final r in records) {
      if (fetched >= _prefetchLimit) return;
      final id = (r['id'] as num?)?.toInt();
      if (id == null) continue;
      final uuid = r['client_uuid'] as String? ?? 'server_$id';
      if (await store.localPhoto(uuid) != null) continue;
      try {
        await store.cacheServerPhoto(uuid, id, await ApiClient.downloadImage('/sync/scans/$id/image'));
        fetched++;
      } on ApiException catch (e) {
        if (e.isOffline || e.statusCode == 401) return;
        // e.g. 404: this record has no photo on the server.
      } catch (e) {
        debugPrint('[Sync] photo $id not saved: $e');
        return; // storage problem: try again next sync
      }
    }
  }

  /// My Records: what's still on the phone first, then the server's copies.
  static Future<List<Record>> records() async {
    final store = LocalStore.instance;
    final out = <Record>[];
    for (final o in (await store.pendingObservations()).reversed) {
      out.add(Record(pending: o, localPhoto: o.imagePath));
    }
    for (final r in await store.cachedRecords()) {
      out.add(Record(server: r, localPhoto: await store.localPhoto(r['client_uuid'] as String?)));
    }
    return out;
  }

  /// A record with its recommendations (and history for staff). Falls back
  /// to the cached copy when offline. A record deleted on the server (410)
  /// is dropped from the phone too.
  static Future<Record?> record(int serverId) async {
    final store = LocalStore.instance;
    try {
      final data = await ApiClient.get('/sync/scans/$serverId') as Map<String, dynamic>;
      await _keepRecord(data);
      return Record(server: data, localPhoto: await store.localPhoto(data['client_uuid'] as String?));
    } on ApiException catch (e) {
      if (e.statusCode == 410) {
        await store.removeRecord(serverId);
        revision.value++;
        rethrow;
      }
      if (!e.isOffline) rethrow;
      final cached = await cachedRecord(serverId);
      if (cached == null) rethrow;
      return cached.data;
    }
  }

  static String _recordKey(int id) => 'record_$id';

  /// Keeps the server's copy on the phone: the user's own records in My
  /// Records, others (opened by staff) in the cache, so they open offline.
  static Future<void> _keepRecord(Map<String, dynamic> data) async {
    final id = (data['id'] as num?)?.toInt();
    if (data['is_mine'] == true) {
      await LocalStore.instance.saveRecord(data);
    } else if (id != null) {
      await LocalStore.instance.putCache(_recordKey(id), data);
    }
  }

  /// The copy of a record saved on this phone (own records, or ones staff
  /// opened before), or null. No network.
  static Future<Loaded<Record>?> cachedRecord(int serverId) async {
    final store = LocalStore.instance;
    final own = await store.cachedRecord(serverId);
    if (own != null) {
      return Loaded(Record(server: own, localPhoto: await store.localPhoto(own['client_uuid'] as String?)),
          fromCache: true);
    }
    final entry = await store.getCacheEntry(_recordKey(serverId));
    final data = entry?.data;
    if (data is! Map<String, dynamic>) return null;
    return Loaded(Record(server: data, localPhoto: await store.localPhoto(data['client_uuid'] as String?)),
        savedAt: entry!.savedAt, fromCache: true);
  }

  /// Corrects the land type of a record (online only). The server checks
  /// who may (the submitter before review, technicians in their coverage).
  static Future<Record> changeLandType(int scanId, String landType, {String reason = ''}) async {
    final data = await ApiClient.patch('/sync/scans/$scanId/land-type', {
      'land_type': landType,
      if (reason.trim().isNotEmpty) 'reason': reason.trim(),
    }) as Map<String, dynamic>;
    await _keepRecord(data);
    revision.value++;
    return Record(server: data, localPhoto: await LocalStore.instance.localPhoto(data['client_uuid'] as String?));
  }

  /// Treatments logged on the phone for a record that haven't gone out yet.
  static Future<List<TreatmentInfo>> pendingTreatmentsFor(int scanId) async => [
        for (final (id, t) in await pendingTreatments())
          if (id == scanId) t,
      ];

  /// Every treatment still on the phone, with the server id of its record.
  static Future<List<(int, TreatmentInfo)>> pendingTreatments() async => [
        for (final t in await LocalStore.instance.pendingTreatments())
          (
            t.scanId,
            TreatmentInfo(
              clientUuid: t.clientUuid,
              treatment: t.label,
              optionType: t.libraryId == null ? 'own' : '',
              appliedAt: t.appliedAt,
              pending: true,
              error: t.lastError,
            ),
          ),
      ];

  static Future<void> _sendTreatment(OutboxTreatment t) async {
    Future<Object?> post(int? libraryId, String customText) => ApiClient.post('/sync/scans/${t.scanId}/treatments', {
          'client_uuid': t.clientUuid,
          'library_id': libraryId,
          'custom_text': customText,
          'applied_at': t.appliedAt,
        });
    Object? data;
    try {
      data = await post(t.libraryId, t.customText);
    } on ApiException catch (e) {
      // The option was picked from the cached list but has since left the
      // approved list: record what the farmer applied in their own words.
      if (t.libraryId == null || e.statusCode != 400 || t.label.trim().isEmpty) rethrow;
      data = await post(null, t.label);
    }
    await LocalStore.instance.saveRecord(data as Map<String, dynamic>);
  }

  /// "I applied a treatment". Saved on the phone first; returns true if it
  /// also reached the server now.
  static Future<bool> logTreatment({
    required int scanId,
    int? libraryId,
    required String label,
    String customText = '',
    required DateTime appliedAt,
  }) async {
    final t = OutboxTreatment(
      clientUuid: newClientUuid(),
      scanId: scanId,
      libraryId: libraryId,
      label: label,
      customText: customText,
      appliedAt: isoDate(appliedAt),
    );
    await LocalStore.instance.addTreatment(t);
    try {
      await _sendTreatment(t);
      return true;
    } on ApiException catch (e) {
      if (_transient(e)) return false;
      // Refused (shown to the farmer): don't keep retrying it in the background.
      await LocalStore.instance.removeTreatment(t.clientUuid);
      rethrow;
    } finally {
      revision.value++;
      await _updateBadge();
    }
  }

  // ---------------------------------------------------------------- notifications

  /// The server's notifications; the last copy saved on the phone when offline.
  static Future<List<AppNotification>> notifications() async {
    try {
      return await fetchNotifications();
    } on ApiException catch (e) {
      final cached = await cachedNotifications();
      if (!e.isOffline || cached == null) rethrow;
      return cached.data;
    }
  }

  /// The server's notifications (throws without signal), saved on the phone.
  static Future<List<AppNotification>> fetchNotifications() async {
    final data = await ApiClient.get('/sync/notifications') as Map<String, dynamic>;
    await LocalStore.instance.putCache('notifications', data);
    _unread = (data['unread'] as num?)?.toInt() ?? 0;
    await _updateBadge();
    // On screen already: no phone pop-up for these.
    await NotificationService.instance.announceServerItems(_items(data), silent: true);
    return _parseNotifications(data);
  }

  /// The notifications saved on the phone, or null. No network.
  static Future<Loaded<List<AppNotification>>?> cachedNotifications() async {
    final entry = await LocalStore.instance.getCacheEntry('notifications');
    final data = entry?.data;
    if (data is! Map<String, dynamic>) return null;
    return Loaded(_parseNotifications(data), savedAt: entry!.savedAt, fromCache: true);
  }

  static List<AppNotification> _parseNotifications(Map<String, dynamic> data) {
    return [
      for (final n in (data['items'] as List? ?? const []))
        AppNotification(
          (n['id'] as num).toInt(),
          (n['scan_id'] as num?)?.toInt(),
          n['kind'] as String? ?? '',
          n['title'] as String? ?? '',
          n['body'] as String? ?? '',
          n['created_at'] as String? ?? '',
          n['read'] == true,
        ),
    ];
  }

  static Future<void> markRead({List<int> ids = const [], bool all = false}) async {
    await ApiClient.post('/sync/notifications/read', {'ids': ids, 'all': all});
    await refreshBadge();
  }

  static Future<void> refreshBadge() async {
    if (!_canSync) return;
    try {
      final data = await ApiClient.get('/sync/notifications') as Map<String, dynamic>;
      _unread = (data['unread'] as num?)?.toInt() ?? 0;
      // New since the last check: pop up on the phone, with sound.
      await NotificationService.instance.announceServerItems(_items(data));
      _followDeletions(_items(data));
    } catch (_) {
      // offline: keep the last count
    }
    await _updateBadge();
  }

  /// Highest "record deleted" notice handled in this app session.
  static int _lastDeletionNotice = 0;

  /// A technician or agriculturist deleted one of this person's records:
  /// refresh the list now (within the 30-second news check) instead of
  /// waiting for the next full sync, so the record disappears everywhere.
  static void _followDeletions(List<Map<String, dynamic>> items) {
    var newest = _lastDeletionNotice;
    for (final n in items) {
      final id = (n['id'] as num?)?.toInt() ?? 0;
      if (n['kind'] == 'record_deleted' && id > newest) newest = id;
    }
    if (newest > _lastDeletionNotice) {
      _lastDeletionNotice = newest;
      unawaited(syncAll());
    }
  }

  static List<Map<String, dynamic>> _items(Map<String, dynamic> data) =>
      [for (final n in (data['items'] as List? ?? const [])) n as Map<String, dynamic>];

  static Future<void>? _checking;

  /// Quick check for news (every half minute while the app runs): server
  /// notifications, and for technicians new observations in their queue.
  static Future<void> checkNews() => _checking ??= _checkNews().whenComplete(() => _checking = null);

  static Future<void> _checkNews() async {
    if (!_canSync) return;
    await refreshBadge();
    if (AuthControllerImpl.instance.role != AppRole.technician) return;
    try {
      final lists = await Future.wait([queue('pest'), queue('disease')]);
      await NotificationService.instance.announceQueue([
        for (final list in lists)
          for (final r in list)
            if (r.id != null) r.id!,
      ]);
    } catch (_) {
      // offline: try again next time
    }
  }

  /// Treatments whose "How is the field now?" check is due, with their record.
  static Future<List<(Record, TreatmentInfo)>> dueFollowUps() async {
    final cached = await LocalStore.instance.cachedRecords();
    // Answered already: a follow-up waiting to be sent, or one sent whose
    // treated record hasn't been refreshed yet.
    final pendingFollowUps = {
      for (final o in await LocalStore.instance.pendingObservations())
        if (o.followUpOf != null) o.followUpOf,
      for (final r in cached)
        if (r['follow_up_of'] is num) (r['follow_up_of'] as num).toInt(),
    };
    final out = <(Record, TreatmentInfo)>[];
    for (final r in cached) {
      final rec = Record(server: r);
      for (final t in rec.treatments) {
        if (t.followUpIsDue && !pendingFollowUps.contains(t.id)) out.add((rec, t));
      }
    }
    return out;
  }

  static Future<void> _updateBadge() async {
    try {
      badge.value = _unread + (await dueFollowUps()).length;
    } catch (_) {}
  }

  // ---------------------------------------------------------------- technician / agriculturist

  /// Technicians: the "Not Validated" queue (pending observations in their
  /// area, initial review), oldest first. Escalated cases ("To Be
  /// Validated") are for agriculturists on the dashboard.
  /// Offline, the last list saved on the phone (reviewing still needs signal).
  static Future<List<Record>> queue(String kind) async {
    try {
      return await fetchQueue(kind);
    } on ApiException catch (e) {
      final cached = await cachedQueue(kind);
      if (!e.isOffline || cached == null) rethrow;
      return cached.data;
    }
  }

  /// The queue from the server (throws without signal), saved on the phone.
  static Future<List<Record>> fetchQueue(String kind) async {
    final isTech = AuthControllerImpl.instance.role == AppRole.technician;
    final data = await ApiClient.get('/sync/queue', query: {
      'kind': kind,
      if (isTech) 'queue': 'not_validated',
    }) as List;
    await LocalStore.instance.putCache('queue_$kind', data);
    return _queueRecords(kind, data);
  }

  /// The queue saved on the phone, or null. No network.
  static Future<Loaded<List<Record>>?> cachedQueue(String kind) async {
    final entry = await LocalStore.instance.getCacheEntry('queue_$kind');
    final data = entry?.data;
    if (data is! List) return null;
    return Loaded(_queueRecords(kind, data), savedAt: entry!.savedAt, fromCache: true);
  }

  static List<Record> _queueRecords(String kind, List data) {
    _queueSizes[kind] = data.length;
    queueCount.value = _queueSizes.values.fold(0, (a, b) => a + b);
    return [for (final r in data) Record(server: r as Map<String, dynamic>)];
  }

  /// Technicians (their area) and agriculturists: deletes an observation on
  /// the server (with its photo, treatments and history) and on this phone.
  /// The owner's app drops it on its next check. Throws ApiException (e.g.
  /// 403 for farmers, offline: deleting needs signal).
  static Future<void> deleteRecord(int scanId, {String reason = ''}) async {
    await ApiClient.delete('/sync/scans/$scanId', query: {if (reason.trim().isNotEmpty) 'reason': reason.trim()});
    await LocalStore.instance.removeRecord(scanId);
    for (final kind in ['pest', 'disease']) {
      final cached = await LocalStore.instance.getCache('queue_$kind');
      if (cached is List) {
        await LocalStore.instance.putCache('queue_$kind', [
          for (final r in cached)
            if (!(r is Map && r['id'] == scanId)) r,
        ]);
      }
    }
    revision.value++;
    unawaited(checkNews());
  }

  static Future<Record> review(int scanId, Map<String, dynamic> body) async {
    final data = await ApiClient.post('/sync/scans/$scanId/review', body) as Map<String, dynamic>;
    await _keepRecord(data);
    revision.value++;
    return Record(server: data);
  }

  /// The treatment library (approved entries for technicians), saved on the
  /// phone; the saved copy when offline.
  static Future<List<LibraryOption>> library() async {
    Object? data;
    try {
      data = await ApiClient.get('/dashboard/library');
      await LocalStore.instance.putCache('library', data);
    } on ApiException catch (e) {
      data = await LocalStore.instance.getCache('library');
      if (!e.isOffline || data is! List) rethrow;
    }
    return [
      for (final o in (data as List? ?? const []))
        if (o is Map) LibraryOption.fromJson(o.cast<String, dynamic>()),
    ];
  }

  static Future<LevelSuggestion> suggestLevel({
    required String pest,
    required String cropStage,
    int? count,
    List<String> indicators = const [],
  }) async {
    final data = await ApiClient.get('/sync/level-suggestion', query: {
      'pest': pest,
      'crop_stage': cropStage,
      if (count != null) 'count': '$count',
      'indicators': indicators.join('|'),
    }) as Map<String, dynamic>;
    return LevelSuggestion.fromJson(data);
  }
}

/// Sends queued work whenever the app is open: on start, on resume, and
/// every few minutes. No background service (farmers open the app to check).
class AutoSync with WidgetsBindingObserver {
  AutoSync._();
  static final AutoSync instance = AutoSync._();

  static const Duration _interval = kSyncInterval;

  /// Notifications are checked more often than the full sync.
  static const Duration _newsInterval = Duration(seconds: 30);
  Timer? _timer;
  Timer? _newsTimer;
  bool _started = false;
  bool _wasConnected = false;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _wasConnected = false;
    ApiConfig.connected.addListener(_onConnectionChanged);
    _onConnectionChanged();
    _timer = Timer.periodic(_interval, (_) => SyncService.syncAll());
    _newsTimer = Timer.periodic(_newsInterval, (_) => SyncService.checkNews());
    SyncService.syncAll(force: true);
  }

  // Connection back or app resumed: send at once, whatever the backoff.
  void _onConnectionChanged() {
    final connected = ApiConfig.connected.value;
    if (connected && !_wasConnected) {
      SyncService.syncAll(force: true);
      SyncService.checkNews();
    }
    _wasConnected = connected;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SyncService.syncAll(force: true);
      SyncService.checkNews();
    }
  }

  void stop() {
    _timer?.cancel();
    _newsTimer?.cancel();
    SyncService.cancelRetry();
    ApiConfig.connected.removeListener(_onConnectionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }
}
