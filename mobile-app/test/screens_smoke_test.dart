// Renders the farmer-facing screens that don't need the server or local
// database, and fails on any layout exception (overflow, unbounded sizes).
//
// Set SCREENSHOT_DIR to also save PNGs (real fonts) for a visual check:
//   SCREENSHOT_DIR=C:\tmp\shots flutter test test/screens_smoke_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:myapp/main.dart' show buildAppTheme;
import 'package:myapp/models/record.dart';
import 'package:myapp/screens/f11a_registration.dart';
import 'package:myapp/screens/f12a_login.dart';
import 'package:myapp/screens/f14_waiting_approval.dart';
import 'package:myapp/screens/f20_home.dart';
import 'package:myapp/screens/f30_new_observation.dart';
import 'package:myapp/screens/f46_observation_submitted.dart';
import 'package:myapp/screens/f47_submission_done.dart';
import 'package:myapp/screens/main_shell.dart';
import 'package:myapp/services/local_store.dart';
import 'package:myapp/services/sync_service.dart';
import 'package:myapp/widgets/app_widgets.dart';

final String? _shotDir = Platform.environment['SCREENSHOT_DIR'];

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'] ?? '';
  final dir = Directory('$root/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final file = File('${dir.path}/$f');
      if (file.existsSync())
        loader.addFont(
          Future.value(ByteData.view(file.readAsBytesSync().buffer)),
        );
    }
    await loader.load();
  }

  for (final family in ['Roboto', 'DM Sans', 'Bricolage Grotesque']) {
    await load(family, [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
    ]);
  }
  await load('MaterialIcons', ['materialicons-regular.otf']);
}

void _mockPlugins() {
  SharedPreferences.setMockInitialValues({});
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/geolocator'),
    (call) async {
      switch (call.method) {
        case 'isLocationServiceEnabled':
          return true;
        case 'checkPermission':
        case 'requestPermission':
          return 3; // whileInUse
        case 'getCurrentPosition':
          return {
            'latitude': 10.7003,
            'longitude': 121.9905,
            'timestamp': 0,
            'accuracy': 5.0,
            'altitude': 0.0,
            'heading': 0.0,
            'speed': 0.0,
            'speed_accuracy': 0.0,
          };
        default:
          return null;
      }
    },
  );
  // Photos are saved under the app's documents folder (path_provider).
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => '${Directory.systemTemp.path}/palay_smoke_docs',
  );
  messenger.setMockStreamHandler(
    const EventChannel('flutter.baseflow.com/geolocator_service_updates'),
    MockStreamHandler.inline(onListen: (args, sink) {}),
  );
}

Future<void> _shot(WidgetTester tester, String name) async {
  if (_shotDir == null) return;
  await tester.runAsync(() async {
    final element = tester.element(find.byKey(const ValueKey('shot')));
    final boundary = element.renderObject! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_shotDir!).createSync(recursive: true);
    File(
      '${_shotDir!}/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget _app(Widget child) => RepaintBoundary(
  key: const ValueKey('shot'),
  child: MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: child,
  ),
);

String? _photo; // set by a test to make the fake camera return a photo

/// Stands in for the camera: shows "camera", or returns [photo] at once.
class _FakeCamera extends StatefulWidget {
  final String? photo;
  const _FakeCamera({this.photo});
  @override
  State<_FakeCamera> createState() => _FakeCameraState();
}

class _FakeCameraState extends State<_FakeCamera> {
  @override
  void initState() {
    super.initState();
    if (widget.photo != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.pop(widget.photo),
      );
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('camera'));
}

Widget _routerApp(String initial, Object? extra) {
  final router = GoRouter(
    initialLocation: initial,
    initialExtra: extra,
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const F20Home()),
      GoRoute(path: '/shell', builder: (_, _) => const MainShell()),
      GoRoute(
        path: '/observe',
        builder: (_, s) => F30NewObservation(
          args: (s.extra as ObserveArgs?) ?? const ObserveArgs(),
        ),
      ),
      GoRoute(
        path: '/observe/camera',
        builder: (_, _) => _FakeCamera(photo: _photo),
      ),
      GoRoute(
        path: '/records',
        builder: (_, _) => const Scaffold(body: Text('records')),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const Scaffold(body: Text('notifications')),
      ),
    ],
  );
  return RepaintBoundary(
    key: const ValueKey('shot'),
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
    ),
  );
}

Record _serverRecord(Map<String, dynamic> overrides) => Record(
  server: {
    'id': 7,
    'client_uuid': 'abc',
    'report_type': 'pest',
    'created_at': '2026-09-27T08:30:00+08:00',
    'crop_stage': 'Reproductive',
    'monitoring_method': 'Direct field observation',
    'status': 'pending',
    'ai': {
      'status': 'done',
      'pest': 'brown_planthopper',
      'confidence': 0.63,
      'count': 14,
      'countable': true,
      'message': '',
    },
    'treatments': <dynamic>[],
    ...overrides,
  },
);

/// Lets the screen's network timeouts (15 s) run out before the test ends,
/// so no timer is left pending (the requests fail fast without a server).
Future<void> _settleTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 30));
  await tester.pumpAndSettle();
}

/// The camera hands back the photo; the photo step then asks to confirm it
/// ("Use this photo") before moving on.
Future<void> _acceptPhoto(WidgetTester tester) async {
  // Saving the photo is real file I/O, which only completes outside the
  // test's fake clock.
  bool onPhotoStep() =>
      find.text('Open the camera').evaluate().isNotEmpty || find.text('Take it again').evaluate().isNotEmpty;
  for (var i = 0; i < 20 && onPhotoStep() && find.text('Use this photo').evaluate().isEmpty; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
  }
  final use = find.text('Use this photo');
  if (use.evaluate().isNotEmpty) {
    await tester.ensureVisible(use);
    await tester.tap(use);
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockPlugins();
    await _loadFonts();
  });

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'home: static header, scrollable content and no notification bell',
    (tester) async {
      await phone(tester);
      SyncService.badge.value = 3;
      await tester.pumpWidget(_routerApp('/home', null));
      await tester.pumpAndSettle();
      final headerTop = tester.getTopLeft(find.text('Welcome')).dy;
      expect(find.text('Scan your field for pests'), findsOneWidget);
      expect(find.text('Start pest scan'), findsOneWidget);
      expect(find.text('Report disease'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_rounded), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Scan history'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Welcome')).dy, headerTop);
      await _shot(tester, 'f20_home');
      // "Report disease" opens the flow with the report type already chosen.
      await tester.tap(find.text('Report disease'));
      await tester.pumpAndSettle();
      expect(find.text('camera'), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      expect(find.text('Disease report'), findsOneWidget);
      expect(
        find.text('Step 1 of 6'),
        findsOneWidget,
      ); // photo, location, land type, stage, notes, submit
    },
  );

  testWidgets('shell: farmer tabs with the scan button in the middle', (
    tester,
  ) async {
    await phone(tester);
    SyncService.badge.value = 0;
    await tester.pumpWidget(_routerApp('/shell', null));
    await tester.pumpAndSettle();
    for (final label in ['Home', 'Records', 'Scan', 'Treatments', 'Alerts']) {
      expect(find.text(label), findsOneWidget);
    }
    await _shot(tester, 'shell_home');
    await tester.tap(find.text('Records'));
    await tester.pumpAndSettle();
    expect(find.text('My Records'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsOneWidget);
    await tester.tap(find.text('Treatments'));
    await tester.pumpAndSettle();
    expect(find.text('No treatments yet'), findsOneWidget);
    await _shot(tester, 'shell_treatments');
    // The scan button starts a new observation.
    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('camera'), findsOneWidget);
  });

  testWidgets('login: photo header and the form', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(const F12aLogin()));
    await tester.pumpAndSettle();
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    await _shot(tester, 'f12a_login');
  });

  testWidgets('done screen: shows the outcome and leads back', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        F47SubmissionDone(
          args: DoneArgs(
            workingTitle: 'Sending your decision…',
            workingMessage: 'This takes a moment.',
            work: Future.value(
              const DoneResult.success(
                'Validated',
                'The farmer has been notified.',
              ),
            ),
            nextLabel: 'Next in queue',
            nextTab: 'queue',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Validated'), findsOneWidget);
    expect(find.text('Next in queue'), findsOneWidget);
    expect(find.text('Back to dashboard'), findsOneWidget);
    await _shot(tester, 'f47_done');
  });

  testWidgets('done screen: a failure offers to go back and try again', (
    tester,
  ) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        F47SubmissionDone(
          args: DoneArgs(
            workingTitle: 'Saving…',
            workingMessage: '',
            work: Future.value(
              const DoneResult.failure(
                'Not sent',
                'No connection to the server right now.',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Not sent'), findsOneWidget);
    expect(find.text('Go back and try again'), findsOneWidget);
  });

  testWidgets(
    'registration: farmer or technician only, then the account form',
    (tester) async {
      await phone(tester);
      await tester.pumpWidget(_app(const F11aRegistration()));
      await tester.pumpAndSettle();
      expect(find.text('Select Your Role'), findsOneWidget);
      expect(find.text("I'm a Farmer"), findsOneWidget);
      expect(find.text('Agricultural Technician'), findsOneWidget);
      expect(
        find.text('Agriculturist / OPA'),
        findsNothing,
      ); // web dashboard only
      await _shot(tester, 'f11a_1_role');
      await tester.tap(find.text('Agricultural Technician'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Registering as an Agricultural Technician'),
        findsOneWidget,
      );
      expect(find.text('Mobile number'), findsOneWidget);
      expect(find.text('Barangay'), findsOneWidget);
      await _shot(tester, 'f11a_2_account');
      // Back returns to the role step.
      await tester.tap(find.byTooltip('Back to role selection'));
      await tester.pumpAndSettle();
      expect(find.text('Select Your Role'), findsOneWidget);
    },
  );

  testWidgets('waiting for approval', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(const F14WaitingApproval()));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for approval'), findsOneWidget);
    await _shot(tester, 'f14_waiting');
  });

  Future<void> writePng() async {
    // A real 1x1 PNG so Image.file can decode it.
    await File('${Directory.systemTemp.path}/obs_test.png').writeAsBytes(const [
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      0,
      0,
      13,
      73,
      72,
      68,
      82,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      1,
      8,
      6,
      0,
      0,
      0,
      31,
      21,
      196,
      137,
      0,
      0,
      0,
      13,
      73,
      68,
      65,
      84,
      120,
      156,
      99,
      248,
      207,
      192,
      240,
      31,
      0,
      5,
      0,
      1,
      255,
      137,
      153,
      61,
      29,
      0,
      0,
      0,
      0,
      73,
      69,
      78,
      68,
      174,
      66,
      96,
      130,
    ]);
  }

  testWidgets('observation flow: starts with the camera', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_routerApp('/observe', const ObserveArgs()));
    await tester.pumpAndSettle();
    // Step 1 is the photo: the camera opens straight away.
    expect(find.text('camera'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.text('Take a clear photo'), findsOneWidget);
    expect(find.text('Step 1 of 8'), findsOneWidget);
    await _shot(tester, 'f30_1_photo');
  });

  testWidgets(
    'observation flow: photo, location, land type, stage, report type, method, notes, submit',
    (tester) async {
      await phone(tester);
      await tester.runAsync(writePng);
      _photo = '${Directory.systemTemp.path}/obs_test.png';
      addTearDown(() => _photo = null);

      await tester.pumpWidget(_routerApp('/observe', const ObserveArgs()));
      await tester.pumpAndSettle();
      await _acceptPhoto(tester);
      // Camera returned the photo -> step 2, location found (mocked GPS).
      expect(find.text('Is this your field?'), findsOneWidget);
      expect(find.text('Step 2 of 8'), findsOneWidget);
      await _shot(tester, 'f30_2_location');
      await tester.tap(find.text('Yes, this is my field'));
      await tester.pumpAndSettle();
      expect(find.text('What kind of land is this field?'), findsOneWidget);
      expect(find.text('Step 3 of 8'), findsOneWidget);
      await _shot(tester, 'f30_3_land');
      await tester.tap(find.textContaining('Irrigated lowland'));
      await tester.pumpAndSettle();
      expect(find.text('What stage is the rice?'), findsOneWidget);
      await _shot(tester, 'f30_3_stage');
      await tester.tap(find.text('Reproductive'));
      await tester.pumpAndSettle();
      expect(find.text('What are you reporting?'), findsOneWidget);
      expect(find.text('Step 5 of 8'), findsOneWidget);
      await _shot(tester, 'f30_4_type');
      await tester.tap(find.text('Pest report'));
      await tester.pumpAndSettle();
      expect(find.text('How did you check?'), findsOneWidget);
      await tester.tap(find.text('Trap-based'));
      await tester.pumpAndSettle();
      expect(find.text('Trap or lure type'), findsOneWidget);
      await _shot(tester, 'f30_5_method_trap');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Anything to add?'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget); // notes optional for pests
      await _shot(tester, 'f30_6_notes');
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('Ready to send?'), findsOneWidget);
      expect(find.text('Step 8 of 8'), findsOneWidget);
      expect(find.text('Irrigated lowland'), findsOneWidget);
      expect(find.textContaining('Trap-based'), findsOneWidget);
      await _shot(tester, 'f30_7_review');

      // "Change" on the summary edits one answer and comes back. Switching to a
      // disease report asks for the description it requires first.
      final changeReport = find.text('Change').at(4);
      await tester.ensureVisible(changeReport);
      await tester.tap(changeReport);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disease report'));
      await tester.pumpAndSettle();
      expect(find.text('Describe what you see'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'Brown spots with yellow edges',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Ready to send?'), findsOneWidget);
      expect(find.text('Disease report'), findsOneWidget);
      expect(find.textContaining('Trap-based'), findsNothing);
      await _settleTimers(tester);
    },
  );

  testWidgets('observation flow: disease needs notes, no method step', (
    tester,
  ) async {
    await phone(tester);
    await tester.runAsync(writePng);
    _photo = '${Directory.systemTemp.path}/obs_test.png';
    addTearDown(() => _photo = null);
    await tester.pumpWidget(_routerApp('/observe', const ObserveArgs()));
    await tester.pumpAndSettle();
    await _acceptPhoto(tester);
    await tester.tap(find.text('Yes, this is my field'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Rainfed lowland'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vegetative'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disease report'));
    await tester.pumpAndSettle();
    expect(
      find.text('Describe what you see'),
      findsOneWidget,
    ); // straight to notes
    expect(find.text('Step 6 of 7'), findsOneWidget);
    final btn = tester.widget<AppPrimaryButton>(
      find.widgetWithText(AppPrimaryButton, 'Continue'),
    );
    expect(btn.onPressed, isNull); // required for disease reports
    await tester.enterText(
      find.byType(TextField),
      'Brown spots with yellow edges on leaves',
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AppPrimaryButton>(
            find.widgetWithText(AppPrimaryButton, 'Continue'),
          )
          .onPressed,
      isNotNull,
    );
    await _shot(tester, 'f30_disease_notes');
    await _settleTimers(tester);
  });

  testWidgets('observation flow: retake of a returned observation', (
    tester,
  ) async {
    await phone(tester);
    await tester.runAsync(writePng);
    _photo = '${Directory.systemTemp.path}/obs_test.png';
    addTearDown(() => _photo = null);
    final returned = _serverRecord({
      'status': 'returned',
      'return_reason': 'Photo too blurry',
      'lat': 10.72,
      'lng': 122.03,
      'notes': 'Many hoppers at the base',
      'land_type': 'irrigated_lowland',
    });
    await tester.pumpWidget(
      _routerApp('/observe', ObserveArgs(retakeOf: returned)),
    );
    await tester.pumpAndSettle();
    await _acceptPhoto(tester);
    // New photo -> straight to the summary with the original's details.
    expect(find.text('Retake photo'), findsOneWidget);
    expect(find.text('Ready to send?'), findsOneWidget);
    expect(find.textContaining('Photo too blurry'), findsOneWidget);
    expect(find.text('Reproductive'), findsOneWidget);
    expect(find.text('Many hoppers at the base'), findsOneWidget);
    expect(find.text('Field confirmed on the map'), findsOneWidget);
    expect(find.text('Irrigated lowland'), findsOneWidget);
    expect(find.text('Pest report'), findsOneWidget);
    await _shot(tester, 'f30_retake_review');
    await _settleTimers(tester);
  });

  testWidgets('result: online pest with AI', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      _app(
        F46ObservationSubmitted(
          outcome: SubmitOutcome(_serverRecord({}), uploaded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Waiting for review'), findsOneWidget);
    expect(find.text('Brown Planthopper'), findsOneWidget);
    expect(find.text('14 insects counted'), findsOneWidget);
    await _shot(tester, 'f46_online_pest');
  });

  testWidgets('result: not countable', (tester) async {
    await phone(tester);
    final rec = _serverRecord({
      'ai': {
        'status': 'done',
        'pest': 'rice_bug',
        'confidence': 0.41,
        'count': null,
        'countable': false,
        'message':
            'The insects are too close together or unclear to count reliably.',
      },
    });
    await tester.pumpWidget(
      _app(
        F46ObservationSubmitted(outcome: SubmitOutcome(rec, uploaded: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Not counted'), findsOneWidget);
    await _shot(tester, 'f46_not_countable');
  });

  testWidgets('result: offline', (tester) async {
    await phone(tester);
    const o = OutboxObservation(
      clientUuid: 'x',
      reportType: 'pest',
      imagePath: '/nonexistent.jpg',
      cropStage: 'Vegetative',
      createdAt: '2026-09-27T08:30:00+08:00',
    );
    await tester.pumpWidget(
      _app(
        const F46ObservationSubmitted(
          outcome: SubmitOutcome(Record(pending: o), uploaded: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved on your phone'), findsOneWidget);
    expect(find.text('Waiting for signal'), findsOneWidget);
    await _shot(tester, 'f46_offline');
  });

  testWidgets('result: disease report', (tester) async {
    await phone(tester);
    final rec = _serverRecord({'report_type': 'disease', 'ai': null});
    await tester.pumpWidget(
      _app(
        F46ObservationSubmitted(outcome: SubmitOutcome(rec, uploaded: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Sent for review by an agricultural technician'),
      findsOneWidget,
    );
    await _shot(tester, 'f46_disease');
  });
}
