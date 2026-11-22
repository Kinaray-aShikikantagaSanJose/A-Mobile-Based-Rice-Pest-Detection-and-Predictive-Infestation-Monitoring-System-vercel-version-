import '../controllers/auth_controller.dart';
import '../l10n/app_language.dart';
import 'api_client.dart';

class AuthException implements Exception {
  final String message;

  /// HTTP status from the backend, or null for network/timeout failures.
  final int? statusCode;

  AuthException(this.message, {this.statusCode});

  /// The backend rejects logins for accounts that never finished email
  /// verification with 403 "Please verify your email before logging in."
  bool get needsVerification => statusCode == 403;

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    try {
      return await ApiClient.publicPost(path, body);
    } on ApiException catch (e) {
      throw AuthException(e.message, statusCode: e.statusCode);
    }
  }

  /// [role] is the role the person asks for. It is granted once the email is
  /// verified; if the backend's REQUIRE_ACCOUNT_APPROVAL is turned on, the
  /// account waits for an agriculturist to approve it first.
  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String password,
    required String phone,
    required String municipality,
    required String barangay,
    String role = 'farmer',
    String? barangayPsgc,
    String locationSource = 'manual',
  }) {
    return _post('/auth/register', {
      'full_name': fullName.trim(),
      'email': email.trim(),
      'password': password,
      'phone': phone.trim(),
      'municipality': municipality,
      'barangay': barangay.trim(),
      'role': role,
      // Official code of the barangay when picked from the list or found by GPS.
      'barangay_psgc': ?barangayPsgc,
      'location_source': locationSource,
      // The language chosen in the app, kept on the account.
      'preferred_language': AppLanguage.instance.code,
    });
  }

  /// Signs out: the server ends the session (best effort, works offline),
  /// then the phone forgets it.
  Future<void> signOut() async {
    await ApiClient.logout();
    AuthControllerImpl.instance.logout();
  }

  Future<Map<String, dynamic>> verifyOtp({required String email, required String code}) {
    return _post('/auth/verify-otp', {'email': email.trim(), 'code': code.trim()});
  }

  Future<Map<String, dynamic>> resendOtp({required String email}) {
    return _post('/auth/resend-otp', {'email': email.trim()});
  }

  /// Signs in and returns the session (the caller starts it). Pending and
  /// rejected accounts also get a session so the app can show their status.
  Future<Session> signIn({required String email, required String password}) async {
    final data = await _post('/auth/login', {'email': email.trim(), 'password': password});
    final session = Session.fromJson(data);
    if (session.accessToken.isEmpty || session.refreshToken.isEmpty) {
      throw AuthException('Sign-in failed: the server did not return a session. Please try again.');
    }
    return session;
  }
}
