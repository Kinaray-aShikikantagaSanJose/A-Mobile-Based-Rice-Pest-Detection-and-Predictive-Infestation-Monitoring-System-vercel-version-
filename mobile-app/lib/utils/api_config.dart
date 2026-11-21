import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ValueNotifier, kIsWeb, debugPrint;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_api_discovery.dart' as local_discovery;

/// Finds the FastAPI backend on whatever network the phone shares with the
/// server (Wi-Fi, Ethernet on the same router, either device's hotspot, USB
/// tethering, emulator) with no IP address to type.
///
/// Native apps re-check the last known address, then use UDP broadcast and a
/// bounded subnet probe. These socket operations live behind a conditional
/// import so Flutter web never imports dart:io.
///
/// For a deployed server (farmers on mobile data), build with a fixed address:
///   flutter build apk --dart-define=API_URL=https://your-api.example.com
/// Discovery is then skipped.
///
/// In a browser (Flutter web) there are no sockets: discovery never runs and
/// only the fixed API_URL (or http://localhost:8000 for local development)
/// is checked, over browser HTTP requests.
class ApiConfig {
  ApiConfig._();

  static const int _backendPort = 8000;
  static const String _prefsKey = 'apiBaseUrl';
  static const Duration _verifyTimeout = Duration(milliseconds: 1500);
  static const Duration _recheckAfter = Duration(seconds: 30);
  // After a failed discovery, don't rescan the whole subnet again for a
  // moment (several screens refresh statuses on open).
  static const Duration _retryAfterFailure = Duration(seconds: 10);

  static const String _fixedUrl = String.fromEnvironment('API_URL');
  // HTTPS is off for now: the local server runs plain HTTP. Build with
  // --dart-define=API_REQUIRE_HTTPS=true once it serves HTTPS again.
  static const bool _requireHttps = bool.fromEnvironment('API_REQUIRE_HTTPS');
  static bool get _hasFixedUrl => _fixedUrl.trim().isNotEmpty;

  static String _baseUrl = _hasFixedUrl
      ? _fixedUrl.trim().replaceAll(RegExp(r'/+$'), '')
      : kIsWeb
          ? 'http://localhost:$_backendPort'
          : 'http://10.0.2.2:$_backendPort';
  static DateTime? _lastVerified;
  static DateTime? _lastFailed;
  static Future<void>? _inFlight;
  static Timer? _monitor;
  static final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  /// Periodically discovers a local backend even when no screen is making
  /// requests, and checks again immediately when the app resumes.
  static void startMonitoring() {
    if (_monitor != null) return;
    if (kIsWeb) {
      // Check the configured server now (the sign-in screen shows the
      // result), whenever the tab comes back, and every re-check window.
      WidgetsBinding.instance.addObserver(_ApiLifecycleObserver());
      unawaited(ensureReachable());
      _monitor = Timer.periodic(_recheckAfter, (_) {
        unawaited(ensureReachable());
      });
      return;
    }
    if (_hasFixedUrl) return;
    WidgetsBinding.instance.addObserver(_ApiLifecycleObserver());
    unawaited(ensureReachable());
    _monitor = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(ensureReachable());
    });
  }

  static void _refreshOnResume() {
    _lastVerified = null;
    _lastFailed = null;
    unawaited(ensureReachable());
  }

  /// Last resolved URL. Call [ensureReachable] first to refresh it.
  static String get baseUrl => _baseUrl;

  /// Forces the next [ensureReachable] to re-check (call after a network error).
  static void invalidate() {
    _lastVerified = null;
    connected.value = false;
  }

  /// True when the backend answered within the last re-check window.
  static bool get isReachable {
    final last = _lastVerified;
    return last != null && DateTime.now().difference(last) < _recheckAfter;
  }

  /// True when this build looks for a local backend (no fixed API_URL).
  /// True when a local backend was looked for and none answered, so a
  /// request would only wait for its timeout.
  static bool get notFound => !_hasFixedUrl && !kIsWeb && !isReachable;

  /// Resolves the backend (bounded by [timeout]) and reports whether it is
  /// reachable right now. Used to route captures to the offline or online
  /// path. Never throws.
  static Future<bool> checkReachable({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    try {
      await ensureReachable().timeout(timeout);
    } catch (_) {
      return isReachable;
    }
    return isReachable;
  }

  /// Makes sure [baseUrl] points at a live backend. Cheap when recently
  /// verified; otherwise re-checks the cached URL, then scans the network.
  /// Never throws.
  static Future<void> ensureReachable() {
    final last = _lastVerified;
    if (last != null && DateTime.now().difference(last) < _recheckAfter) {
      return Future.value();
    }
    final failed = _lastFailed;
    if (failed != null &&
        DateTime.now().difference(failed) < _retryAfterFailure) {
      return Future.value();
    }
    return _inFlight ??= _resolve().whenComplete(() => _inFlight = null);
  }

  static Future<void> _resolve() async {
    if (_hasFixedUrl) {
      // A fixed (deployed) address: only check that it answers.
      // A hosted server may take a while to wake up.
      if (!Uri.parse(_baseUrl).isScheme('https')) {
        _lastFailed = DateTime.now();
        connected.value = false;
        debugPrint('[API] API_URL must use HTTPS.');
        return;
      }
      if (await _isBackend(_baseUrl, timeout: const Duration(seconds: 20))) {
        _lastVerified = DateTime.now();
        _lastFailed = null;
        connected.value = true;
      } else {
        _lastFailed = DateTime.now();
        connected.value = false;
      }
      return;
    }
    if (kIsWeb) {
      // Browser without API_URL (local development): only the default
      // address; LAN discovery needs sockets, which browsers do not expose.
      if (await _isBackend(_baseUrl)) {
        _lastVerified = DateTime.now();
        _lastFailed = null;
        connected.value = true;
      } else {
        _lastFailed = DateTime.now();
        connected.value = false;
      }
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_prefsKey);
      if (cached != null) {
        final uri = Uri.tryParse(cached);
        final secure = uri?.replace(scheme: 'https').toString();
        if (secure != null && await _isBackend(secure)) {
          _baseUrl = secure;
          await prefs.setString(_prefsKey, secure);
          _lastVerified = DateTime.now();
          _lastFailed = null;
          connected.value = true;
          return;
        }
        if (!_requireHttps && await _isBackend(cached)) {
          _baseUrl = cached;
          _lastVerified = DateTime.now();
          _lastFailed = null;
          connected.value = true;
          return;
        }
      }
      final found = await _discover();
      if (found != null) {
        _baseUrl = found;
        _lastVerified = DateTime.now();
        _lastFailed = null;
        connected.value = true;
        await prefs.setString(_prefsKey, found);
        debugPrint('[API] backend found at $found');
      } else {
        _lastFailed = DateTime.now();
        connected.value = false;
        debugPrint('[API] backend not found on this network');
      }
    } catch (e) {
      _lastFailed = DateTime.now();
      connected.value = false;
      debugPrint('[API] discovery failed: $e');
    }
  }

  static Future<String?> _discover() {
    return local_discovery.discoverLocalApi(
      isBackend: (base) => _isBackend(base),
      requireHttps: _requireHttps,
    );
  }

  /// Only our API counts: another FastAPI project on the same Wi-Fi (e.g. a
  /// classmate's) would also answer /openapi.json, and passwords go to it.
  static const String _apiTitle = 'Crop Protection API';

  static Future<bool> _isBackend(
    String base, {
    Duration timeout = _verifyTimeout,
  }) async {
    try {
      final res = await http
          .get(Uri.parse('$base/openapi.json'))
          .timeout(timeout);
      if (res.statusCode != 200) return false;
      final info = (jsonDecode(res.body) as Map<String, dynamic>)['info'];
      return info is Map && info['title'] == _apiTitle;
    } catch (_) {
      return false;
    }
  }
}

class _ApiLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ApiConfig._refreshOnResume();
  }
}
