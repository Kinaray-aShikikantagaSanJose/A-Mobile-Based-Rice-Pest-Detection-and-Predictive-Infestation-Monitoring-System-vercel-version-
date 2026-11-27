// Sign-out confirmation, one language control per screen, layouts at small
// and large sizes with large text, sync rules (refused items, backoff),
// guide parsing and the review-text rules. No server or database needed.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:myapp/l10n/app_language.dart';
import 'package:myapp/main.dart' show buildAppTheme;
import 'package:myapp/models/guide.dart';
import 'package:myapp/models/record.dart';
import 'package:myapp/screens/f12a_login.dart';
import 'package:myapp/screens/f15_profile.dart';
import 'package:myapp/screens/f20_home.dart';
import 'package:myapp/screens/f21_my_records.dart';
import 'package:myapp/screens/f27_guide.dart';
import 'package:myapp/screens/f30_new_observation.dart';
import 'package:myapp/screens/f61_review_observation.dart';
import 'package:myapp/screens/main_shell.dart';
import 'package:myapp/services/local_store.dart';
import 'package:myapp/services/sync_policy.dart';
import 'package:myapp/services/sync_service.dart';
import 'package:myapp/utils/formatters.dart';
import 'package:myapp/utils/review_rules.dart';
import 'package:myapp/widgets/app_widgets.dart';
import 'package:myapp/widgets/language_button.dart';

void _mockPlugins() {
  SharedPreferences.setMockInitialValues({});
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
    (call) async => null,
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/geolocator'),
    (call) async => switch (call.method) {
      'isLocationServiceEnabled' => true,
      'checkPermission' || 'requestPermission' => 3,
      'getCurrentPosition' => {
          'latitude': 10.7003,
          'longitude': 121.9905,
          'timestamp': 0,
          'accuracy': 5.0,
          'altitude': 0.0,
          'heading': 0.0,
          'speed': 0.0,
          'speed_accuracy': 0.0,
        },
      _ => null,
    },
  );
  messenger.setMockStreamHandler(
    const EventChannel('flutter.baseflow.com/geolocator_service_updates'),
    MockStreamHandler.inline(onListen: (args, sink) {}),
  );
}

Widget _app(Widget child, {double textScale = 1.0}) => LanguageScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    );

class _FakeCamera extends StatelessWidget {
  const _FakeCamera();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('camera'));
}

Widget _routerApp(String initial, {double textScale = 1.0}) {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const F20Home()),
      GoRoute(path: '/shell', builder: (_, _) => const MainShell()),
      GoRoute(path: '/records', builder: (_, _) => const F21MyRecords()),
      GoRoute(path: '/observe', builder: (_, s) => const F30NewObservation(args: ObserveArgs())),
      GoRoute(path: '/observe/camera', builder: (_, _) => const _FakeCamera()),
      GoRoute(path: '/notifications', builder: (_, _) => const Scaffold(body: Text('notifications'))),
    ],
  );
  return LanguageScope(
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      builder: (context, inner) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: inner!,
      ),
      routerConfig: router,
    ),
  );
}

/// The page's vertical list (not a text field's own scrollable).
final Finder _mainList =
    find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first;

Future<void> _size(WidgetTester tester, Size logical) async {
  tester.view.physicalSize = logical * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

const Map<String, dynamic> _guideJson = {
  'language': 'fil',
  'translation_status': 'machine_assisted_unreviewed',
  'translation_note': 'Machine-assisted translation, not yet reviewed.',
  'model_note': 'The photo model knows four insects.',
  'confirm_note': 'A technician confirms every result.',
  'sections': {'model_detected': 'Nakikita ng model', 'observed_symptoms': 'Sinusuri ng tao'},
  'model_detected': [
    {
      'key': 'brown_planthopper',
      'name': 'Brown Planthopper',
      'name_en': 'Brown Planthopper',
      'signs': ['Small brown insects at the base of the plant'],
      'stages': ['Vegetative', 'Reproductive'],
      'stage_labels': ['Paglaki', 'Pagbubuntis'],
      'stage_note': 'Most common from tillering.',
      'model_label': 'BPH',
      'photo': null,
      'detected_by': 'model',
    },
  ],
  'observed_symptoms': [
    {
      'key': 'hopperburn',
      'pest': 'brown_planthopper',
      'pest_name': 'Brown Planthopper',
      'name': 'Hopperburn',
      'signs': 'Round patches of dried, yellow-brown plants.',
      'indicator': 'Hopperburn',
      'indicator_label': 'Hopperburn (patches)',
      'stages': ['Reproductive'],
      'stage_labels': ['Pagbubuntis'],
      'photo': null,
      'detected_by': 'people',
    },
  ],
  'glossary': [
    {'term': 'Hopperburn', 'term_en': 'Hopperburn', 'meaning': 'Plants dried out by planthoppers.'},
  ],
};

Record _pendingRecord() => Record(server: {
      'id': 41,
      'client_uuid': 'u41',
      'report_type': 'pest',
      'created_at': '2026-11-20T08:30:00+08:00',
      'crop_stage': 'Reproductive',
      'monitoring_method': 'Direct field observation',
      'status': 'pending',
      'queue': 'not_validated',
      'image_relevance': 'possibly_unrelated',
      'land_type': 'irrigated_lowland',
      'barangay': 'Egaña',
      'municipality': 'Sibalom',
      'submitter': {'name': 'Juan dela Cruz', 'phone': '0917 123 4567', 'role': 'farmer'},
      'ai': {
        'status': 'done',
        'pest': 'brown_planthopper',
        'confidence': 0.63,
        'count': 14,
        'countable': true,
        'message': '',
      },
      'treatments': <dynamic>[],
    });

const _suggestion = LevelSuggestion(
  'MEDIUM',
  ['Count 14: MEDIUM for Reproductive (MEDIUM from 10, HIGH from 20)'],
  ['Hopperburn', 'Wilting or lodging'],
  provisional: true,
  indicatorLabels: {'Hopperburn': 'Hopperburn (mga tuyong bahagi)', 'Wilting or lodging': 'Pagkalanta'},
);

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    _mockPlugins();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLanguage.instance.load();
    await AppLanguage.instance.pick(AppLang.en);
  });

  group('sign-out confirmation', () {
    Widget host(Future<void> Function() signOut, PendingCounts counts) => _app(
          Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => confirmAndSignOut(context, loadCounts: () async => counts, signOut: signOut),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

    testWidgets('shows what is not sent; cancel keeps the session', (tester) async {
      var signedOut = false;
      await tester.pumpWidget(host(() async => signedOut = true, const PendingCounts(2, 1)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsOneWidget);
      expect(find.text('Observations not sent'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Treatments not sent'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.textContaining('sign in again with the same account'), findsOneWidget);
      expect(find.textContaining('different account'), findsOneWidget);
      await tester.tap(find.text('Stay signed in'));
      await tester.pumpAndSettle();
      expect(signedOut, isFalse);
      expect(find.text('Sign out?'), findsNothing);
    });

    testWidgets('confirm signs out', (tester) async {
      var signedOut = false;
      await tester.pumpWidget(host(() async => signedOut = true, const PendingCounts(0, 0)));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Everything is sent'), findsOneWidget);
      expect(find.text('Observations not sent'), findsNothing);
      await tester.tap(find.widgetWithText(AppPrimaryButton, 'Sign out'));
      await tester.pumpAndSettle();
      expect(signedOut, isTrue);
    });
  });

  group('one language control per screen', () {
    testWidgets('Profile: only the Language card, no header button', (tester) async {
      await _size(tester, const Size(390, 844));
      await tester.pumpWidget(_app(const F15Profile()));
      await tester.pumpAndSettle();
      expect(find.byType(LanguageButton), findsNothing);
      expect(find.byKey(const ValueKey('change-language')), findsOneWidget);
    });

    testWidgets('Home: one language button (the hero)', (tester) async {
      await _size(tester, const Size(390, 844));
      await tester.pumpWidget(_routerApp('/home'));
      await tester.pumpAndSettle();
      expect(find.byType(LanguageButton), findsOneWidget);
    });
  });

  group('responsive smoke (fails on overflow)', () {
    const sizes = [Size(320, 568), Size(360, 800), Size(412, 915), Size(800, 1280)];
    const scales = [1.0, 1.3];

    for (final size in sizes) {
      for (final scale in scales) {
        final tag = '${size.width.toInt()}x${size.height.toInt()} @$scale';

        testWidgets('home, shell and records $tag', (tester) async {
          await _size(tester, size);
          await tester.pumpWidget(_routerApp('/home', textScale: scale));
          await tester.pumpAndSettle();
          expect(find.text('Scan your field for pests'), findsOneWidget);
          await tester.pumpWidget(_routerApp('/shell', textScale: scale));
          await tester.pumpAndSettle();
          await tester.pumpWidget(_routerApp('/records', textScale: scale));
          await tester.pumpAndSettle();
          expect(find.text('My Records'), findsOneWidget);
        });

        testWidgets('login $tag', (tester) async {
          await _size(tester, size);
          await tester.pumpWidget(_app(const F12aLogin(), textScale: scale));
          await tester.pumpAndSettle();
          expect(find.text('Welcome Back'), findsOneWidget);
        });

        testWidgets('guide $tag', (tester) async {
          await _size(tester, size);
          await tester.pumpWidget(_app(const F27Guide(preview: _guideJson), textScale: scale));
          await tester.pumpAndSettle();
          expect(find.text('Nakikita ng model'), findsOneWidget);
        });

        testWidgets('observation flow $tag', (tester) async {
          await _size(tester, size);
          await tester.pumpWidget(_routerApp('/observe', textScale: scale));
          await tester.pumpAndSettle();
          expect(find.text('camera'), findsOneWidget);
          tester.state<NavigatorState>(find.byType(Navigator).first).pop();
          await tester.pumpAndSettle();
          expect(find.text('Take a clear photo'), findsOneWidget);
        });

        testWidgets('review screen $tag', (tester) async {
          await _size(tester, size);
          await tester.pumpWidget(_app(
            F61ReviewObservation(scanId: 41, preview: _pendingRecord(), previewSuggestion: _suggestion),
            textScale: scale,
          ));
          // The photo keeps a progress indicator (no server here): pump, don't settle.
          await tester.pump(const Duration(seconds: 1));
          expect(find.byKey(const ValueKey('possibly-unrelated')), findsOneWidget);
          await tester.scrollUntilVisible(find.widgetWithText(ChoiceTile, 'Validate'), 300, scrollable: _mainList);
          await tester.ensureVisible(find.widgetWithText(ChoiceTile, 'Validate'));
          await tester.pump(const Duration(seconds: 1));
          await tester.tap(find.widgetWithText(ChoiceTile, 'Validate'));
          await tester.pump(const Duration(seconds: 1));
          await tester.scrollUntilVisible(find.byKey(const ValueKey('reviewer-note')), 300, scrollable: _mainList);
      await tester.ensureVisible(find.byKey(const ValueKey('reviewer-note')));
      await tester.pump(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 1));
        });
      }
    }
  });

  group('review screen', () {
    testWidgets('validate needs a reviewer note; translated indicators; provisional note', (tester) async {
      await _size(tester, const Size(390, 844));
      await tester.pumpWidget(_app(
        F61ReviewObservation(scanId: 41, preview: _pendingRecord(), previewSuggestion: _suggestion),
      ));
      await tester.pump(const Duration(seconds: 1));
      await tester.scrollUntilVisible(find.widgetWithText(ChoiceTile, 'Validate'), 300, scrollable: _mainList);
          await tester.ensureVisible(find.widgetWithText(ChoiceTile, 'Validate'));
          await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.widgetWithText(ChoiceTile, 'Validate'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Hopperburn (mga tuyong bahagi)'), findsOneWidget);
      expect(find.byKey(const ValueKey('provisional-thresholds')), findsOneWidget);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('reviewer-note')), 300, scrollable: _mainList);
      await tester.ensureVisible(find.byKey(const ValueKey('reviewer-note')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Add a reviewer note: what you checked and why you chose this level.'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('reviewer-note')), 'Counted hoppers at the base of ten hills.');
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Add a reviewer note: what you checked and why you chose this level.'), findsNothing);
    });
  });

  group('review rules (same as the server)', () {
    test('reviewer note', () {
      expect(reviewerNoteProblem(''), isNotNull);
      expect(reviewerNoteProblem('ok'), isNotNull);
      expect(reviewerNoteProblem('Checkedeverything'), isNotNull); // one word
      expect(reviewerNoteProblem('Counted ten hills'), isNull);
      expect(reviewerNoteProblem('Spray now please', guidance: ' spray  NOW please '), isNotNull);
      expect(reviewerNoteProblem('Counted ten hills', diagnosis: 'Brown planthopper'), isNull);
    });

    test('return and escalate reasons', () {
      expect(decisionReasonProblem('Blurry', escalate: false), isNotNull);
      expect(decisionReasonProblem('Too dark', escalate: false), isNull);
      expect(decisionReasonProblem('Odd damage', escalate: true), isNull);
      expect(decisionReasonProblem('Unusual', escalate: true), isNotNull);
      expect(decisionReasonProblem('Not sure', escalate: true), isNotNull); // too short
    });

    test('recommendations only from approved options for the confirmed pest', () {
      const lib = [
        LibraryOption(1, 'brown_planthopper', 'cultural', 'Drain the field', '', 'approved'),
        LibraryOption(2, 'brown_planthopper', 'chemical', 'Draft option', '', 'draft'),
        LibraryOption(3, 'rice_bug', 'cultural', 'Remove weeds', '', 'approved'),
      ];
      expect(approvedOptionsFor(lib, 'brown_planthopper').map((o) => o.id), [1]);
      expect(approvedOptionsFor(lib, null), isEmpty);
    });
  });

  group('sync rules', () {
    test('automatic sync skips items the server refused; "Try sending now" retries them', () {
      const ok = OutboxObservation(clientUuid: 'a', reportType: 'pest', imagePath: 'x', cropStage: 'Vegetative', createdAt: 't');
      const refused = OutboxObservation(
          clientUuid: 'b', reportType: 'pest', imagePath: 'x', cropStage: 'Vegetative', createdAt: 't', lastError: 'Bad data');
      final auto = itemsToSend([ok, refused], (o) => o.lastError, retryRefused: false);
      expect(auto.map((o) => o.clientUuid), ['a']);
      final manual = itemsToSend([ok, refused], (o) => o.lastError, retryRefused: true);
      expect(manual.map((o) => o.clientUuid), ['a', 'b']);
      expect(shouldSend('', retryRefused: false), isTrue);
      expect(shouldSend('Refused', retryRefused: false), isFalse);
    });

    test('backoff: 30 s, 1 min, 2 min, then capped at 3 min', () {
      expect(backoffDelay(0), Duration.zero);
      expect(backoffDelay(1), const Duration(seconds: 30));
      expect(backoffDelay(2), const Duration(minutes: 1));
      expect(backoffDelay(3), const Duration(minutes: 2));
      expect(backoffDelay(4), const Duration(minutes: 3));
      expect(backoffDelay(50), const Duration(minutes: 3));
    });

    test('SyncBackoff blocks automatic runs until the wait is over, resets on success', () {
      final b = SyncBackoff();
      final t0 = DateTime(2026, 11, 27, 8);
      expect(b.allows(t0), isTrue);
      expect(b.failed(t0), const Duration(seconds: 30));
      expect(b.allows(t0.add(const Duration(seconds: 10))), isFalse);
      expect(b.allows(t0.add(const Duration(seconds: 30))), isTrue);
      expect(b.failed(t0), const Duration(minutes: 1));
      b.succeeded();
      expect(b.failures, 0);
      expect(b.allows(t0), isTrue);
    });

    test('saved map keys are recognised for clearing on account change', () {
      expect(LocalStore.isSavedMapKey('local_map_90_pest=rice_bug'), isTrue);
      expect(LocalStore.isSavedMapKey('local_spread_window=7'), isTrue);
      expect(LocalStore.isSavedMapKey('appLanguage'), isFalse);
    });

    test('treatment outbox keeps the refusal reason', () {
      final t = OutboxTreatment.fromMap({
        'id': 1,
        'client_uuid': 't1',
        'scan_id': 9,
        'library_id': null,
        'label': 'Drain the field',
        'custom_text': '',
        'applied_at': '2026-11-20',
        'last_error': 'This record changed.',
      });
      expect(t.lastError, 'This record changed.');
      expect(t.toMap()['last_error'], 'This record changed.');
      // Rows saved before v14 have no column: no error.
      expect(OutboxTreatment.fromMap({'client_uuid': 't2', 'scan_id': 9, 'applied_at': '2026-11-20'}).lastError, '');
    });
  });

  group('guide parsing', () {
    test('new sections, stage labels, glossary and notes', () {
      final g = GuideContent.fromJson(_guideJson);
      expect(g.modelHeading, 'Nakikita ng model');
      expect(g.peopleHeading, 'Sinusuri ng tao');
      expect(g.modelDetected.single.stageLabels, ['Paglaki', 'Pagbubuntis']);
      expect(g.modelDetected.single.modelLabel, 'BPH');
      expect(g.modelDetected.single.detectedBy, 'model');
      expect(g.observedSymptoms.single.signs, ['Round patches of dried, yellow-brown plants.']);
      expect(g.observedSymptoms.single.indicatorLabel, 'Hopperburn (patches)');
      expect(g.observedSymptoms.single.detectedBy, 'people');
      expect(g.glossary.single.term, 'Hopperburn');
      expect(g.translationNote, isNotEmpty);
      expect(g.confirmNote, 'A technician confirms every result.');
    });

    test('older servers: falls back to pests / symptoms and translates stages', () {
      final g = GuideContent.fromJson({
        'model_note': 'Four insects.',
        'pests': [
          {'key': 'rice_bug', 'name': 'Rice Bug', 'signs': ['Long thin bug'], 'stages': ['Ripening']},
        ],
        'symptoms': [
          {'key': 'empty_grains', 'pest': 'rice_bug', 'name': 'Empty grains', 'signs': 'Grains stay empty.', 'stages': ['Ripening']},
        ],
      });
      expect(g.modelHeading, 'Detected by the photo model');
      expect(g.peopleHeading, 'Checked by people in the field');
      expect(g.modelDetected.single.name, 'Rice Bug');
      expect(g.modelDetected.single.stageLabels, ['Ripening']);
      expect(g.observedSymptoms.single.pest, 'rice_bug');
      expect(g.glossary, isEmpty);
      expect(g.translationNote, '');
    });

    testWidgets('renders two separate sections and a collapsible glossary', (tester) async {
      await _size(tester, const Size(390, 844));
      await tester.pumpWidget(_app(const F27Guide(preview: _guideJson)));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('guide-translation-note')), findsOneWidget);
      expect(find.byKey(const ValueKey('guide-model-section')), findsOneWidget);
      expect(find.byKey(const ValueKey('guide-people-section'), skipOffstage: false), findsOneWidget);
      expect(find.textContaining('Plants dried out by planthoppers.', findRichText: true), findsNothing);
      await tester.scrollUntilVisible(find.text('Glossary'), 300);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Glossary'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Plants dried out by planthoppers.', findRichText: true, skipOffstage: false),
          findsOneWidget);
    });
  });

  group('record model', () {
    test('new fields: queue, relevance, recommended options, history notes', () {
      final r = Record(server: {
        'id': 5,
        'client_uuid': 'u5',
        'report_type': 'pest',
        'status': 'validated',
        'queue': null,
        'image_relevance': 'relevant',
        'land_type_updated_by': 'Tech One',
        'land_type_updated_at': '2026-11-21T09:00:00+08:00',
        'recommended': [
          {
            'library_id': 3,
            'title': 'Drain the field',
            'option_type': 'cultural',
            'description': 'Drain for 3 days.',
            'source_reference': 'PhilRice',
            'still_approved': false,
            'recommended_by_role': 'technician',
            'recommended_by_name': 'Tech One',
            'created_at': '2026-11-21T09:00:00+08:00',
          },
        ],
        'recommendations': {
          'groups': {
            'cultural': [
              {'id': 3, 'title': 'Drain the field', 'description': '', 'source_reference': '', 'recommended': true},
            ],
          },
        },
        'history': [
          {'action': 'validate', 'reviewer': 'Tech One', 'reviewer_note': 'Counted ten hills', 'guidance': 'Drain'},
        ],
      });
      expect(r.queue, '');
      expect(r.possiblyUnrelated, isFalse);
      expect(r.landTypeUpdatedBy, 'Tech One');
      expect(r.recommended.single.stillApproved, isFalse);
      expect(r.recommended.single.libraryId, 3);
      expect(r.recommendations!.all.single.recommended, isTrue);
      expect(r.history.single.reviewerNote, 'Counted ten hills');
      expect(r.landTypeEditableByOwner, isFalse);
    });

    test('staff labels name the queues; farmers see friendly words', () {
      final pending = Record(server: const {'id': 1, 'report_type': 'pest', 'status': 'pending'});
      final escalated = Record(server: const {'id': 2, 'report_type': 'pest', 'status': 'escalated'});
      expect(recordStateLabel(pending.state, staff: true), 'Not Validated');
      expect(recordStateLabel(escalated.state, staff: true), 'To Be Validated (agriculturist)');
      expect(recordStateLabel(pending.state, staff: false), 'Waiting for review');
      expect(recordStateLabel(escalated.state, staff: false), 'With an agriculturist');
    });
  });
}
