import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/auth_controller.dart';

/// What a tapped phone notification asks the app to open.
class NotificationTap {
  /// Record to open, or null for the notifications list.
  final int? scanId;

  /// 'queue' for a technician's new observation, 'profile' for account changes.
  final String? target;
  const NotificationTap({this.scanId, this.target});
}

/// Phone notifications (the pop-up at the top of the screen, with sound) for
/// news the app finds while it runs: a validation, a returned photo,
/// guidance, account changes, and for technicians new observations in their
/// queue. There is no push server, so the app checks every half minute while
/// it is open or in the background; news that arrives while it is closed pops
/// up the next time it is opened.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'palay_patrol_updates';
  static const String _channelName = 'Observation updates';
  static const int _maxSingle = 3;

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  bool _asked = false;

  /// The app listens to this and opens what a tapped notification points to.
  final ValueNotifier<NotificationTap?> taps = ValueNotifier<NotificationTap?>(null);

  Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          // Permission is asked after sign-in (see requestPermission).
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) => _onTap(r.payload),
      );
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Validations, returned photos, guidance and new observations to review.',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
        ),
      );
      _ready = true;
      // The app was opened by tapping a notification.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) _onTap(launch!.notificationResponse?.payload);
    } catch (e) {
      debugPrint('[Notify] init failed: $e');
    }
  }

  /// Android 13+ and iOS ask the person once.
  Future<void> requestPermission() async {
    if (!_ready || _asked) return;
    _asked = true;
    try {
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('[Notify] permission request failed: $e');
    }
  }

  void _onTap(String? payload) {
    if (payload == null || payload.isEmpty) {
      taps.value = const NotificationTap();
      return;
    }
    try {
      final m = jsonDecode(payload) as Map<String, dynamic>;
      taps.value = NotificationTap(scanId: (m['scan_id'] as num?)?.toInt(), target: m['target'] as String?);
    } catch (_) {
      taps.value = const NotificationTap();
    }
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: 'ic_notification',
          color: Color(0xFF1FA06B),
          category: AndroidNotificationCategory.message,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBadge: true),
      );

  // ---------------------------------------------------------------- what is new

  /// Shows the server notifications this phone hasn't announced yet.
  /// `items`: {id, scan_id, kind, title, body, read}, newest first. The first
  /// check for an account only remembers where it is (no flood of old news).
  /// [silent]: only remember them (the person is looking at the list).
  Future<void> announceServerItems(List<Map<String, dynamic>> items, {bool silent = false}) async {
    final email = AuthControllerImpl.instance.userEmail;
    if (email == null) return;
    final key = 'notified_up_to:$email';
    final prefs = await SharedPreferences.getInstance();
    final maxId = items.fold<int>(0, (m, n) => (n['id'] as num).toInt() > m ? (n['id'] as num).toInt() : m);
    final last = prefs.getInt(key);
    if (last == null || maxId < last) {
      await prefs.setInt(key, maxId);
      return;
    }
    final fresh = [
      for (final n in items)
        if ((n['id'] as num).toInt() > last && n['read'] != true) n,
    ];
    await prefs.setInt(key, maxId);
    if (fresh.isEmpty || silent) return;
    if (fresh.length > _maxSingle) {
      await _show(
        id: 900000,
        title: '${fresh.length} new updates',
        body: fresh.take(3).map((n) => n['title']).join(' · '),
      );
      return;
    }
    for (final n in fresh.reversed) {
      final scanId = (n['scan_id'] as num?)?.toInt();
      await _show(
        id: (n['id'] as num).toInt(),
        title: '${n['title'] ?? 'Palay Patrol'}',
        body: '${n['body'] ?? ''}',
        payload: jsonEncode({
          'scan_id': scanId,
          if (n['kind'] == 'account') 'target': 'profile',
        }),
      );
    }
  }

  /// Technicians: announces observations that just reached their queue.
  /// `ids`: every observation now waiting (pest + disease).
  Future<void> announceQueue(List<int> ids) async {
    final email = AuthControllerImpl.instance.userEmail;
    if (email == null) return;
    final key = 'queue_seen_up_to:$email';
    final prefs = await SharedPreferences.getInstance();
    final maxId = ids.fold<int>(0, (m, i) => i > m ? i : m);
    final last = prefs.getInt(key);
    if (last == null) {
      await prefs.setInt(key, maxId);
      return;
    }
    final fresh = ids.where((i) => i > last).toList();
    if (maxId > last) await prefs.setInt(key, maxId);
    if (fresh.isEmpty) return;
    await _show(
      id: 800000 + (fresh.reduce((a, b) => a > b ? a : b) % 100000),
      title: fresh.length == 1 ? 'New observation to validate' : '${fresh.length} new observations to validate',
      body: 'A farmer in your area sent a field observation. Open the queue to review it.',
      payload: jsonEncode({'target': 'queue', 'scan_id': fresh.length == 1 ? fresh.first : null}),
    );
  }

  Future<void> _show({required int id, required String title, required String body, String? payload}) async {
    if (!_ready) return;
    try {
      await _plugin.show(id: id, title: title, body: body, notificationDetails: _details, payload: payload);
    } catch (e) {
      debugPrint('[Notify] show failed: $e');
    }
  }

  /// Signing out: nothing from the previous account stays on screen.
  Future<void> clear() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
