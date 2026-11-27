import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../controllers/auth_controller.dart';
import '../l10n/app_language.dart';
import '../platform/local_files.dart';
import '../utils/api_config.dart';

class ApiException implements Exception {
  final String message;

  /// HTTP status, or null when the server couldn't be reached.
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  bool get isOffline => statusCode == null;

  @override
  String toString() => message;
}

/// Talks to the FastAPI backend. Keeps the session alive: the access token is
/// renewed shortly before it expires (and once more if the server still says
/// 401), so a farmer is only asked to sign in again if the phone stayed
/// unused for longer than the refresh token lasts (90 days).
class ApiClient {
  ApiClient._();

  static const Duration timeout = Duration(seconds: 15);
  static const Duration uploadTimeout = Duration(seconds: 90);
  static const String serverNotFound =
      "Can't find the Palay Patrol server. Connect this device to the same "
      'Wi-Fi, Ethernet, or hotspot network as the server.';
  static Future<Session>? _refreshing;

  static AuthControllerImpl get _auth => AuthControllerImpl.instance;
  static String get baseUrl => ApiConfig.baseUrl;

  // ---------------------------------------------------------------- public (no session)

  static Future<Map<String, dynamic>> publicPost(String path, Map<String, dynamic> body) async {
    await _reach();
    final http.Response res;
    try {
      res = await http
          .post(Uri.parse('$baseUrl$path'), headers: {'Content-Type': 'application/json', ...clientHeaders},
              body: jsonEncode(body))
          .timeout(timeout);
    } catch (e) {
      throw _offline(e);
    }
    final data = _decode(res);
    if (data is Map<String, dynamic>) return data;
    throw ApiException('Unexpected server response (HTTP ${res.statusCode}).', statusCode: res.statusCode);
  }

  // ---------------------------------------------------------------- signed in

  static Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  static Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body);

  /// Profile requests work for accounts still waiting for approval too.
  static Future<dynamic> put(String path, [Object? body]) => _send('PUT', path, body: body, allowUnapproved: true);

  static Future<dynamic> patch(String path, [Object? body]) => _send('PATCH', path, body: body);

  static Future<dynamic> delete(String path, {Map<String, String>? query}) =>
      _send('DELETE', path, query: query, allowUnapproved: true);

  /// Downloads an authenticated image and refreshes an expired access token once.
  static Future<Uint8List> downloadImage(String path) async {
    await _reach();
    for (var attempt = 0; attempt < 2; attempt++) {
      final http.Response res;
      try {
        res = await http
            .get(Uri.parse('$baseUrl$path'), headers: await authHeaders())
            .timeout(timeout);
      } catch (e) {
        throw _offline(e);
      }
      if (res.statusCode == 401 && attempt == 0) {
        await _refresh();
        continue;
      }
      if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
      throw ApiException(_message(res), statusCode: res.statusCode);
    }
    throw const ApiException('Your session ended. Please sign in again.', statusCode: 401);
  }

  /// Multipart upload of one photo (a local path; on the web also a `blob:`
  /// URL) plus form fields. [filename] defaults to the path's base name.
  static Future<dynamic> upload(String path, Map<String, String> fields, String photoPath,
      {String? filename}) async {
    await _reach();
    for (var attempt = 0; attempt < 2; attempt++) {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$path'))
        ..headers.addAll(await authHeaders())
        ..fields.addAll(fields)
        ..files.add(await localMultipartFile('image', photoPath, filename: filename));
      final http.Response res;
      try {
        res = await http.Response.fromStream(await request.send().timeout(uploadTimeout));
      } catch (e) {
        throw _offline(e);
      }
      if (res.statusCode == 401 && attempt == 0) {
        await _refresh();
        continue;
      }
      return _decode(res);
    }
  }

  /// Which app sent the request (shown in the dashboard's activity log) and
  /// the language chosen in the app, so server texts (guide, level reasons,
  /// messages) come back in that language.
  static Map<String, String> get clientHeaders => {
        'X-Palay-Client': kIsWeb ? 'web' : 'mobile',
        'X-Palay-Language': AppLanguage.instance.code,
      };

  /// Headers for requests the app builds itself (e.g. Image.network).
  static Future<Map<String, String>> authHeaders() async =>
      {'Authorization': 'Bearer ${await _freshAccessToken()}', ...clientHeaders};

  /// Ends the session on the server so its tokens stop working (sign-out).
  /// Best effort: never throws and gives up quickly without signal.
  static Future<void> logout() async {
    final s = _auth.session;
    if (s == null) return;
    try {
      await http
          .post(Uri.parse('$baseUrl/auth/logout'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${s.accessToken}',
                ...clientHeaders,
              },
              body: jsonEncode({'refresh_token': s.refreshToken}))
          .timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('[API] logout not sent: $e');
    }
  }

  /// Current headers without waiting (may hold a token that is about to expire).
  static Map<String, String> get currentHeaders =>
      {'Authorization': 'Bearer ${_auth.session?.accessToken ?? ''}'};

  static String imageUrl(int scanId) => '$baseUrl/sync/scans/$scanId/image';

  /// Full URL of a profile picture path from the API (`avatar_url`).
  static String? avatarUrl(String? path) => path == null ? null : '$baseUrl$path';

  /// Saves the profile the API returned (after an edit or a new picture).
  static Future<Session?> applyProfile(Object? data) async {
    final s = _auth.session;
    if (s == null || data is! Map<String, dynamic>) return null;
    final updated = Session.fromJson(data,
        accessToken: _auth.session?.accessToken ?? s.accessToken,
        refreshToken: _auth.session?.refreshToken ?? s.refreshToken);
    await _auth.updateSession(updated);
    return updated;
  }

  /// Re-reads the profile (approval status, role, area) from `/auth/me`.
  static Future<Session?> refreshProfile() async {
    final s = _auth.session;
    if (s == null) return null;
    return applyProfile(await _send('GET', '/auth/me', allowUnapproved: true));
  }

  // ---------------------------------------------------------------- internals

  static Future<void> _reach() async {
    try {
      await ApiConfig.ensureReachable().timeout(timeout);
    } on TimeoutException {
      debugPrint('[API] discovery timed out; using $baseUrl');
    }
    // Nothing answered on this network: report offline now (screens then
    // show what is saved on the phone) instead of waiting out the timeout.
    if (ApiConfig.notFound) throw const ApiException(serverNotFound);
  }

  static Future<dynamic> _send(String method, String path,
      {Map<String, String>? query, Object? body, bool allowUnapproved = false}) async {
    await _reach();
    var uri = Uri.parse('$baseUrl$path');
    if (query != null && query.isNotEmpty) uri = uri.replace(queryParameters: query);
    for (var attempt = 0; attempt < 2; attempt++) {
      final headers = {...await authHeaders(), if (body != null) 'Content-Type': 'application/json'};
      final http.Response res;
      try {
        final encoded = body == null ? null : jsonEncode(body);
        res = await switch (method) {
          'GET' => http.get(uri, headers: headers),
          'PUT' => http.put(uri, headers: headers, body: encoded),
          'PATCH' => http.patch(uri, headers: headers, body: encoded),
          'DELETE' => http.delete(uri, headers: headers),
          _ => http.post(uri, headers: headers, body: encoded),
        }
            .timeout(timeout);
      } catch (e) {
        throw _offline(e);
      }
      if (res.statusCode == 401 && attempt == 0) {
        await _refresh();
        continue;
      }
      if (res.statusCode == 403 && !allowUnapproved && _isApprovalMessage(res)) {
        // Approval was withdrawn (or never given): update the status so the
        // router shows the waiting screen.
        unawaited(refreshProfile().catchError((_) => null));
      }
      return _decode(res);
    }
  }

  static bool _isApprovalMessage(http.Response res) {
    final msg = _message(res).toLowerCase();
    return msg.contains('approval') || msg.contains('not approved');
  }

  static Future<String> _freshAccessToken() async {
    final s = _auth.session;
    if (s == null) throw const ApiException('Please sign in again.', statusCode: 401);
    if (!_expiresSoon(s.accessToken)) return s.accessToken;
    return (await _refresh()).accessToken;
  }

  static bool _expiresSoon(String jwt) {
    try {
      final part = jwt.split('.')[1];
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part))));
      final exp = DateTime.fromMillisecondsSinceEpoch((payload['exp'] as num).toInt() * 1000);
      return exp.difference(DateTime.now()) < const Duration(minutes: 2);
    } catch (_) {
      return true;
    }
  }

  /// One refresh at a time; concurrent callers share it.
  static Future<Session> _refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  static Future<Session> _doRefresh() async {
    final s = _auth.session;
    if (s == null) throw const ApiException('Please sign in again.', statusCode: 401);
    final http.Response res;
    try {
      res = await http
          .post(Uri.parse('$baseUrl/auth/refresh'), headers: {'Content-Type': 'application/json', ...clientHeaders},
              body: jsonEncode({'refresh_token': s.refreshToken}))
          .timeout(timeout);
    } catch (e) {
      throw _offline(e);
    }
    if (res.statusCode == 401) {
      _auth.expireSession();
      throw const ApiException('Your session ended. Please sign in again.', statusCode: 401);
    }
    final data = _decode(res) as Map<String, dynamic>;
    final updated = Session.fromJson(data);
    await _auth.updateSession(updated);
    return updated;
  }

  static ApiException _offline(Object e) {
    ApiConfig.invalidate();
    if (e is TimeoutException) {
      return const ApiException('The server took too long to answer. Check your signal and try again.');
    }
    return const ApiException('No connection to the server right now.');
  }

  static dynamic _decode(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      try {
        return jsonDecode(res.body);
      } catch (_) {
        throw ApiException('Unexpected server response (HTTP ${res.statusCode}).', statusCode: res.statusCode);
      }
    }
    throw ApiException(_message(res), statusCode: res.statusCode);
  }

  /// FastAPI sends `detail` as a string, or as a list of `{msg}` for 422s.
  static String _message(http.Response res) {
    try {
      final data = jsonDecode(res.body);
      if (data is Map) {
        final detail = data['detail'];
        if (detail is String && detail.trim().isNotEmpty) return detail.trim();
        if (detail is List && detail.isNotEmpty && detail.first is Map) {
          final msg = ((detail.first as Map)['msg'] as String? ?? '').replaceFirst('Value error, ', '').trim();
          if (msg.isNotEmpty) return '${msg[0].toUpperCase()}${msg.substring(1)}';
        }
      }
    } catch (_) {}
    if (res.statusCode == 429) return 'Too many attempts. Please wait a moment and try again.';
    if (res.statusCode >= 500) return 'The server had a problem (HTTP ${res.statusCode}). Please try again later.';
    return 'Request failed (HTTP ${res.statusCode}).';
  }
}
