    import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'controllers/auth_controller.dart';
import 'models/record.dart';
import 'screens/f01_onboarding.dart';
import 'screens/f10_splash_welcome.dart';
import 'screens/f11a_registration.dart';
import 'screens/f11b_otp_verification.dart';
import 'screens/f12a_login.dart';
import 'screens/f14_waiting_approval.dart';
import 'screens/f15_profile.dart';
import 'screens/f21_my_records.dart';
import 'screens/f24_record_detail.dart';
import 'screens/f25_notifications.dart';
import 'screens/f26_treatments.dart';
import 'screens/f27_guide.dart';
import 'screens/f30_new_observation.dart';
import 'screens/f31_camera_ui.dart';
import 'screens/f46_observation_submitted.dart';
import 'screens/f47_submission_done.dart';
import 'screens/f61_review_observation.dart';
import 'screens/f62_local_map.dart';
import 'screens/main_shell.dart';
import 'services/sync_service.dart';
import 'widgets/shell_scope.dart';

/// Fade + short horizontal slide for the observation flow and pushed screens.
Page<void> _flowPage(Widget child, {String? name}) {
  return CustomTransitionPage<void>(
    name: name,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class AppRouter {
  AppRouter(this.auth);

  final AuthController auth;

  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const register = '/register';
  static const otp = '/otp-verification';
  static const login = '/login';
  static const waiting = '/waiting-approval';

  /// The tab shell (Home, Records, … and the Scan button).
  static const home = '/home';
  static const observe = '/observe';
  static const camera = '/observe/camera';
  static const submitted = '/observe/submitted';
  static const done = '/done';
  static const records = '/records';
  static const record = '/record';
  static const notifications = '/notifications';
  static const treatments = '/treatments';
  static const guide = '/guide';
  static const profile = '/profile';

  /// Technicians: the queue is a tab; this path opens it.
  static const queue = '/queue';
  static const review = '/review';
  static const map = '/map';

  static const Set<String> _public = {splash, onboarding, login, register, otp};

  /// Everyone starts on the Home tab of the shell.
  static String homeFor(AppRole? role) => home;

  late final GoRouter router = GoRouter(
    initialLocation: splash,
    refreshListenable: auth,
    routes: [
      GoRoute(path: splash, builder: (_, _) => const F10SplashWelcome()),
      GoRoute(path: onboarding, builder: (_, _) => const F01OnboardingScreen()),
      GoRoute(path: register, builder: (_, _) => const F11aRegistration()),
      GoRoute(
        path: otp,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is Map<String, dynamic>) {
            return F11bOtpVerification(
              contact: extra['email'] as String? ?? '',
              fullName: extra['fullName'] as String? ?? '',
              password: extra['password'] as String? ?? '',
            );
          }
          return F11bOtpVerification(contact: extra is String ? extra : '');
        },
      ),
      GoRoute(path: login, builder: (_, _) => const F12aLogin()),
      GoRoute(path: waiting, builder: (_, _) => const F14WaitingApproval()),
      GoRoute(
        path: home,
        builder: (_, state) => MainShell(initialTab: state.uri.queryParameters['tab']),
      ),
      GoRoute(path: queue, redirect: (_, _) => '$home?tab=${AppTab.queue}'),
      GoRoute(
        path: observe,
        pageBuilder: (context, state) => _flowPage(
          F30NewObservation(args: state.extra is ObserveArgs ? state.extra as ObserveArgs : const ObserveArgs()),
          name: observe,
        ),
      ),
      GoRoute(path: camera, pageBuilder: (_, _) => _flowPage(const F31CameraUi(), name: camera)),
      GoRoute(
        path: submitted,
        // The outcome (or the upload still running) arrives as `extra`; after
        // a process restart it's gone, so show the records list instead.
        redirect: (_, state) => state.extra is SubmitOutcome || state.extra is PendingSubmission ? null : records,
        pageBuilder: (context, state) => _flowPage(
          state.extra is PendingSubmission
              ? F46ObservationSubmitted(pending: state.extra as PendingSubmission)
              : F46ObservationSubmitted(outcome: state.extra as SubmitOutcome),
          name: submitted,
        ),
      ),
      GoRoute(
        path: done,
        redirect: (_, state) => state.extra is DoneArgs ? null : home,
        pageBuilder: (context, state) => _flowPage(F47SubmissionDone(args: state.extra as DoneArgs), name: done),
      ),
      GoRoute(path: records, pageBuilder: (_, _) => _flowPage(const F21MyRecords(), name: records)),
      GoRoute(
        path: record,
        redirect: (_, state) => state.extra is Record || state.extra is int ? null : records,
        pageBuilder: (context, state) => _flowPage(
          F24RecordDetail(
            initial: state.extra is Record ? state.extra as Record : null,
            serverId: state.extra is int ? state.extra as int : (state.extra as Record?)?.id,
          ),
          name: record,
        ),
      ),
      GoRoute(
        path: notifications,
        pageBuilder: (_, _) => _flowPage(const F25Notifications(), name: notifications),
      ),
      GoRoute(path: treatments, pageBuilder: (_, _) => _flowPage(const F26Treatments(), name: treatments)),
      GoRoute(path: guide, pageBuilder: (_, _) => _flowPage(const F27Guide(), name: guide)),
      GoRoute(path: profile, pageBuilder: (_, _) => _flowPage(const F15Profile(), name: profile)),
      GoRoute(path: map, pageBuilder: (_, _) => _flowPage(const F62LocalMap(), name: map)),
      GoRoute(
        path: '$review/:id',
        pageBuilder: (context, state) => _flowPage(
          F61ReviewObservation(scanId: int.tryParse(state.pathParameters['id'] ?? '') ?? 0),
          name: review,
        ),
      ),
    ],
    redirect: (context, state) {
      final String path = state.matchedLocation;
      if (!auth.isLoggedIn) return _public.contains(path) ? null : login;
      // Follows the account status from the server. Approval is off on the
      // backend for now (no approving OPA account yet), so new accounts
      // arrive 'approved'; only a deactivated or, if approval is turned
      // back on, a pending account lands on the waiting screen.
      if (!auth.isApproved) return path == waiting ? null : waiting;
      if (path == waiting || _public.contains(path)) return home;
      // Validation and the local map are technician tools.
      final technicianOnly = path.startsWith('$review/') || path == map;
      if (technicianOnly && auth.role != AppRole.technician) return home;
      return null;
    },
  );
}
