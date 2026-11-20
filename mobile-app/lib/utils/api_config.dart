import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart'
    show ValueNotifier, kIsWeb, debugPrint;
import 'package:flutter/widgets.dart'
    show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Finds the FastAPI backend on whatever network the phone shares with the
/// server (Wi-Fi, Ethernet on the same router, either device's hotspot, USB
/// tethering, emulator) with no IP address to type.
///
/// How it works: re-check the last known address; otherwise broadcast a
/// discovery request on UDP [_discoveryPort] on every local network and use
/// the server that answers (works for any subnet size); if nothing answers
/// (broadcasts blocked), probe every host on the phone's /24 subnet(s). A
/// candidate only counts after it answers GET /openapi.json as our API.
///
/// For a deployed server (farmers on mobile data), build with a fixed address:
///   flutter build apk --dart-define=API_URL=https://your-api.example.com
/// Discovery is then skipped.
///
/// In a browser (Flutter web) there are no sockets: discovery never runs and
/// only the fixed API_URL (or http://localhost:8000 for local development)
/// is checked, over plain HTTP requests.
class ApiConfig {
  ApiConfig._();

  static const int _backendPort = 8000;
  // Must match DISCOVERY_PORT in rice-pest-api (app/discovery.py).
  static const int _discoveryPort = int.fromEnvironment(
    'DISCOVERY_PORT',
    defaultValue: 8001,
  );
  static const String _discoveryRequest = 'PALAY_PATROL_DISCOVER_V1';
  static const Duration _broadcastWait = Duration(milliseconds: 2500);
  static const String _prefsKey = 'apiBaseUrl';
  static const Duration _connectTimeout = Duration(milliseconds: 600);
  static const Duration _verifyTimeout = Duration(milliseconds: 1500);
  static const Duration _recheckAfter = Duration(seconds: 30);
  // After a failed discovery, don't rescan the whole subnet again for a
  // moment (several screens refresh statuses on open).
  static const Duration _retryAfterFailure = Duration(seconds: 10);

  // Cellular / virtual interfaces are never where a laptop lives.
  static const List<String> _skipInterfaces = [
    'rmnet',
    'ccmni',
    'pdp',
    'tun',
    'dummy',
  ];

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
      // address; LAN discovery needs sockets, which browsers don't have.
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

  static Future<String?> _discover() async {
    final prefixes = await _localPrefixes();
    return await _broadcastDiscover(prefixes) ?? await _scanSubnets(prefixes);
  }

  /// First three octets of each usable IPv4 address on this phone.
  static Future<Set<String>> _localPrefixes() async {
    final prefixes = <String>{};
    for (final iface in await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    )) {
      if (_skipInterfaces.any(iface.name.toLowerCase().contains)) continue;
      for (final a in iface.addresses) {
        if (a.isLoopback || a.isLinkLocal) continue;
        final p = a.address.split('.');
        prefixes.add('${p[0]}.${p[1]}.${p[2]}');
      }
    }
    return prefixes;
  }

  /// Asks every network the phone is on "where is the Palay Patrol server?"
  /// and returns the first answering host that proves to be our API.
  static Future<String?> _broadcastDiscover(Set<String> prefixes) async {
    RawDatagramSocket? socket;
    final result = Completer<String?>();
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      // The general broadcast can leave by mobile data only; the per-network
      // ones reach Wi-Fi, Ethernet, hotspot and tethering clients (whether the
      // network is a /24 or wider).
      final targets = <InternetAddress>{
        InternetAddress('255.255.255.255'),
        for (final prefix in prefixes) ...[
          InternetAddress('$prefix.255'),
          InternetAddress('${prefix.substring(0, prefix.lastIndexOf('.'))}.255.255'),
        ],
      };
      final checked = <String>{};
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final dg = socket?.receive();
        if (dg == null) return;
        final url = _parseReply(dg);
        if (url == null || !checked.add(url)) return;
        _confirm(url).then((ok) {
          if (ok != null && !result.isCompleted) result.complete(ok);
        });
      });
      final request = utf8.encode(_discoveryRequest);
      for (final delay in const [0, 400, 1000]) {
        if (result.isCompleted) break;
        await Future<void>.delayed(Duration(milliseconds: delay));
        for (final target in targets) {
          try {
            socket.send(request, target, _discoveryPort);
          } catch (_) {
            // No route to that network right now.
          }
        }
      }
      return await result.future.timeout(_broadcastWait, onTimeout: () => null);
    } catch (e) {
      debugPrint('[API] broadcast discovery failed: $e');
      return null;
    } finally {
      socket?.close();
    }
  }

  static String? _parseReply(Datagram dg) {
    try {
      final data = jsonDecode(utf8.decode(dg.data));
      if (data is! Map || data['service'] != 'palay-patrol') return null;
      final port = (data['port'] as num?)?.toInt() ?? _backendPort;
      final scheme = data['scheme'] == 'http' ? 'http' : 'https';
      return '$scheme://${dg.address.address}:$port';
    } catch (_) {
      return null;
    }
  }

  /// HTTPS first; plain HTTP unless [_requireHttps].
  static Future<String?> _confirm(String url) async {
    final uri = Uri.parse(url);
    final secure = uri.replace(scheme: 'https').toString();
    if (await _isBackend(secure)) return secure;
    if (_requireHttps) return null;
    final plain = uri.replace(scheme: 'http').toString();
    return await _isBackend(plain) ? plain : null;
  }

  static Future<String?> _scanSubnets(Set<String> prefixes) async {
    final hosts = <String>{'10.0.2.2', '127.0.0.1'};
    for (final prefix in prefixes) {
      for (var i = 1; i < 255; i++) {
        hosts.add('$prefix.$i');
      }
    }

    final result = Completer<String?>();
    var pending = hosts.length;
    for (final host in hosts) {
      _probeHost(host).then((url) {
        if (url != null && !result.isCompleted) {
          result.complete(url);
        }
        if (--pending == 0 && !result.isCompleted) result.complete(null);
      });
    }
    return result.future;
  }

  /// Fast TCP check first (cheap for the ~250 dead hosts), then confirm it
  /// is really our FastAPI server and not some other service on port 8000.
  static Future<String?> _probeHost(String host) async {
    try {
      final socket = await Socket.connect(
        host,
        _backendPort,
        timeout: _connectTimeout,
      );
      socket.destroy();
    } catch (_) {
      return null;
    }
    return _confirm('https://$host:$_backendPort');
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
