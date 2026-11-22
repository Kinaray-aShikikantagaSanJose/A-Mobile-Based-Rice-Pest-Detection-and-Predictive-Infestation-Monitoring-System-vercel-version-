import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_language.dart';
import '../services/local_store.dart';
import '../services/notification_service.dart';

enum AppRole { farmer, technician, agriculturist }

/// The mobile app is for farmers and technicians; agriculturists work on the
/// web dashboard.
const String kAgriculturistOnWeb =
    'Agriculturist accounts use the Palay Patrol web dashboard. Sign in there with the same email and password.';

AppRole? appRoleFromName(String? name) {
  if (name == null) return null;
  for (final r in AppRole.values) {
    if (r.name == name.trim().toLowerCase()) return r;
  }
  return null;
}

/// Account status from the server. New accounts are 'approved' while the
/// backend's approval step is off; 'pending' only occurs when it is on, and
/// 'rejected' means an agriculturist deactivated the account.
enum AccountStatus { pending, approved, rejected }

AccountStatus accountStatusFromName(String? name) {
  switch ((name ?? '').trim().toLowerCase()) {
    case 'approved':
      return AccountStatus.approved;
    case 'rejected':
      return AccountStatus.rejected;
    default:
      return AccountStatus.pending;
  }
}

/// A signed-in account: tokens plus the profile the API returned.
class Session {
  final String accessToken;
  final String refreshToken;
  final String name;
  final String email;
  final AppRole role;
  final AccountStatus status;
  final String municipality;
  final String barangay;
  final String phone;

  /// Server account id (null in sessions saved by older versions).
  final int? id;

  /// Path of the profile picture on the API (e.g. /auth/avatar/12?v=ab12), or null.
  final String? avatarUrl;

  /// Barangays a technician covers ([] = the whole municipality).
  final List<String> coverage;

  /// Language saved on the account: en | fil | krj.
  final String preferredLanguage;

  /// Official PSGC codes of the saved municipality / barangay (null when the
  /// names couldn't be matched, or for accounts saved before codes existed).
  final String? municipalityPsgc;
  final String? barangayPsgc;

  /// 'gps' when the area was found from the phone's location, else 'manual'.
  final String locationSource;

  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.municipality = '',
    this.barangay = '',
    this.phone = '',
    this.id,
    this.avatarUrl,
    this.coverage = const [],
    this.preferredLanguage = 'en',
    this.municipalityPsgc,
    this.barangayPsgc,
    this.locationSource = 'manual',
  });

  /// Both municipality and barangay are saved: no GPS lookup is needed.
  bool get hasArea => municipality.isNotEmpty && barangay.isNotEmpty;

  /// From `/auth/login`, `/auth/refresh` (tokens + profile) or, with the
  /// current tokens, `/auth/me` (profile only).
  factory Session.fromJson(Map<String, dynamic> j, {String? accessToken, String? refreshToken}) {
    final email = (j['email'] as String? ?? '').trim().toLowerCase();
    final name = (j['full_name'] as String? ?? '').trim();
    return Session(
      accessToken: (j['access_token'] as String?) ?? accessToken ?? '',
      refreshToken: (j['refresh_token'] as String?) ?? refreshToken ?? '',
      name: name.isEmpty ? email : name,
      email: email,
      role: appRoleFromName(j['role'] as String?) ?? AppRole.farmer,
      status: accountStatusFromName(j['status'] as String?),
      municipality: (j['municipality'] as String? ?? '').trim(),
      barangay: (j['barangay'] as String? ?? '').trim(),
      phone: (j['phone'] as String? ?? '').trim(),
      id: (j['id'] as num?)?.toInt(),
      avatarUrl: _nonEmpty(j['avatar_url'] as String?),
      coverage: [for (final b in (j['coverage_barangays'] as List? ?? const [])) '$b'],
      preferredLanguage: AppLang.fromCode(j['preferred_language'] as String?)?.name ?? 'en',
      municipalityPsgc: _nonEmpty(j['municipality_psgc'] as String?),
      barangayPsgc: _nonEmpty(j['barangay_psgc'] as String?),
      locationSource: (j['location_source'] as String?) == 'gps' ? 'gps' : 'manual',
    );
  }

  static String? _nonEmpty(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();

  /// True when something shown on screen differs (name, picture, area, ...).
  bool sameProfileAs(Session o) =>
      name == o.name &&
      role == o.role &&
      status == o.status &&
      municipality == o.municipality &&
      barangay == o.barangay &&
      phone == o.phone &&
      id == o.id &&
      avatarUrl == o.avatarUrl &&
      coverage.join(',') == o.coverage.join(',') &&
      preferredLanguage == o.preferredLanguage &&
      barangayPsgc == o.barangayPsgc &&
      municipalityPsgc == o.municipalityPsgc &&
      locationSource == o.locationSource;

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'full_name': name,
        'email': email,
        'role': role.name,
        'status': status.name,
        'municipality': municipality,
        'barangay': barangay,
        'phone': phone,
        'id': id,
        'avatar_url': avatarUrl,
        'coverage_barangays': coverage,
        'preferred_language': preferredLanguage,
        'municipality_psgc': municipalityPsgc,
        'barangay_psgc': barangayPsgc,
        'location_source': locationSource,
      };
}

abstract class AuthController extends ChangeNotifier {
  Session? get session;
  bool get isLoggedIn => session != null;
  bool get isApproved => session?.status == AccountStatus.approved;
  AccountStatus? get status => session?.status;
  AppRole? get role => session?.role;
  String? get userName => session?.name;
  String? get userEmail => session?.email;

  /// True after the server ended the session (refresh token expired or the
  /// account was removed). Cleared on the next sign-in.
  bool get sessionExpired;

  /// Email of the last account, kept after sign-out to prefill the login form.
  String? get lastEmail;

  Future<void> initialize();
  Future<void> startSession(Session session);
  Future<void> updateSession(Session session);
  void logout();
  void expireSession();
}

class AuthControllerImpl extends AuthController {
  AuthControllerImpl._();
  static final AuthControllerImpl instance = AuthControllerImpl._();

  static const String _kSession = 'session';
  static const String _kLastEmail = 'lastEmail';
  static const String _kDataOwner = 'localDataOwner';
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  Session? _session;
  bool _sessionExpired = false;
  String? _lastEmail;

  /// Serializes storage writes so a quick login -> logout can't interleave.
  Future<void> _pending = Future.value();

  @override
  Session? get session => _session;
  @override
  bool get sessionExpired => _sessionExpired;
  @override
  String? get lastEmail => _lastEmail;

  @override
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastEmail = prefs.getString(_kLastEmail);
      final raw = await _secure.read(key: _kSession);
      if (raw != null) {
        final s = Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        // Farmers stay signed in: the refresh token renews the session, so
        // opening the app never asks for the password again. Agriculturist
        // sessions from older versions are not restored (web dashboard only).
        if (s.refreshToken.isNotEmpty && s.email.isNotEmpty && s.role != AppRole.agriculturist) {
          _session = s;
          AppLanguage.instance.adoptAccountLanguage(s.preferredLanguage);
        }
      }
    } catch (e) {
      debugPrint('Failed to restore session: $e');
    }
    notifyListeners();
  }

  @override
  Future<void> startSession(Session session) async {
    // Local observations belong to whoever captured them. When another
    // account signs in on this phone, clear them first, before the new
    // session exists: otherwise a sync could send them under the new account.
    try {
      final prefs = await SharedPreferences.getInstance();
      final owner = prefs.getString(_kDataOwner);
      if (owner != null && owner != session.email) await LocalStore.instance.clearAll();
      await prefs.setString(_kDataOwner, session.email);
    } catch (e) {
      debugPrint('Could not check the local data owner: $e');
    }
    _sessionExpired = false;
    _session = session;
    _lastEmail = session.email;
    // The account's language, unless one was picked on this phone.
    AppLanguage.instance.adoptAccountLanguage(session.preferredLanguage);
    notifyListeners();
    _enqueue(() async {
      await _secure.write(key: _kSession, value: jsonEncode(session.toJson()));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastEmail, session.email);
    });
  }

  /// New tokens or a fresh profile (approval, role, area, name or picture
  /// changed, e.g. by an agriculturist on the dashboard).
  @override
  Future<void> updateSession(Session session) async {
    if (_session == null) return;
    if (session.role == AppRole.agriculturist) {
      // The account became an agriculturist's: that role works on the web.
      _signOut(expired: false);
      return;
    }
    final changed = !session.sameProfileAs(_session!);
    _session = session;
    if (changed) notifyListeners();
    _enqueue(() => _secure.write(key: _kSession, value: jsonEncode(session.toJson())));
  }

  @override
  void logout() => _signOut(expired: false);

  @override
  void expireSession() {
    if (_session == null) return;
    _signOut(expired: true);
  }

  void _signOut({required bool expired}) {
    NotificationService.instance.clear();
    _session = null;
    _sessionExpired = expired;
    notifyListeners();
    _enqueue(() => _secure.delete(key: _kSession));
  }

  void _enqueue(Future<void> Function() task) {
    _pending = _pending.then((_) async {
      try {
        await task();
      } catch (e) {
        debugPrint('Failed to persist session: $e');
      }
    });
  }
}
