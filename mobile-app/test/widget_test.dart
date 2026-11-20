// Smoke tests for the Palay Patrol app shell: the app boots signed out and
// the login screen renders its form.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myapp/controllers/auth_controller.dart';
import 'package:myapp/main.dart';
import 'package:myapp/screens/f12a_login.dart';

/// In-memory AuthController for tests (no secure storage, no singleton).
class _FakeAuth extends AuthController {
  Session? _session;

  @override
  Session? get session => _session;

  @override
  bool sessionExpired = false;

  @override
  String? get lastEmail => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> startSession(Session session) async {
    _session = session;
    notifyListeners();
  }

  @override
  Future<void> updateSession(Session session) async => _session = session;

  @override
  void logout() {
    _session = null;
    notifyListeners();
  }

  @override
  void expireSession() {
    sessionExpired = true;
    logout();
  }
}

void main() {
  testWidgets('app boots without throwing', (WidgetTester tester) async {
    await tester.pumpWidget(MyApp(auth: _FakeAuth()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(Scaffold), findsWidgets);
  });

  testWidgets('login screen renders its form', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: F12aLogin()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(F12aLogin), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
