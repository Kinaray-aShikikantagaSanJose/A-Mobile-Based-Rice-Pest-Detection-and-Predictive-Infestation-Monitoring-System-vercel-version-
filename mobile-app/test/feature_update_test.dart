// Offline geofencing (bundled GeoJSON), translations and the new record
// states. No network needed: everything here works without signal.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:myapp/l10n/app_language.dart';
import 'package:myapp/l10n/strings.dart';
import 'package:myapp/models/record.dart';
import 'package:myapp/services/antique_geofence.dart';
import 'package:myapp/utils/formatters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Antique geofence (offline, bundled asset)', () {
    final geo = AntiqueGeofence.instance;

    test('known barangays resolve from their interior points (PostGIS-verified)', () async {
      const cases = [
        (10.745770, 122.004750, '0600616024', 'Egaña', 'Sibalom'),
        (10.467860, 121.924822, '0600601001', 'Bayo Grande', 'Anini-y'),
        (12.018785, 121.383706, '0600605001', 'Alegria', 'Caluya'),
        (11.407715, 122.132829, '0600606001', 'Alojipan', 'Culasi'),
        (11.097925, 122.179931, '0600618001', 'Bakiang', 'Valderrama'),
        (10.7445, 121.9410, '0600613009', 'Barangay 7', 'San Jose de Buenavista'),
      ];
      for (final (lat, lng, psgc, barangay, municipality) in cases) {
        final m = await geo.locate(lat, lng, accuracyM: 10);
        expect(m.status, GeoStatus.inside, reason: barangay);
        expect(m.place!.psgc, psgc);
        expect(m.place!.barangay, barangay);
        expect(m.place!.municipality, municipality);
      }
    });

    test('outside Antique, bad coordinates, poor accuracy, near a boundary', () async {
      expect((await geo.locate(10.7202, 122.5621)).status, GeoStatus.outside); // Iloilo City
      expect((await geo.locate(11.0, 121.5)).status, GeoStatus.outside); // open sea
      expect((await geo.locate(0, 0)).status, GeoStatus.invalid);
      expect((await geo.locate(95, 200)).status, GeoStatus.invalid);
      final rough = await geo.locate(10.745770, 122.004750, accuracyM: 400);
      expect(rough.status, GeoStatus.inaccurate);
      expect(rough.place!.barangay, 'Egaña'); // best guess is still given
      final edge = await geo.locate(10.75627, 122.00475, accuracyM: 100);
      expect(edge.status, GeoStatus.nearBoundary);
      expect(edge.alternatives, isNotEmpty);
    });

    test('lists the official barangays and matches typed names', () async {
      expect((await geo.barangaysOf('Sibalom')).length, 76);
      expect((await geo.barangaysOf('San Jose')).length, 28); // old name works
      expect((await geo.match('Sibalom', 'egana'))?.psgc, '0600616024');
      expect((await geo.match('Sibalom', 'Brgy. Egaña'))?.psgc, '0600616024');
      expect(await geo.match('Sibalom', 'Not a barangay'), isNull);
      var total = 0;
      for (final m in const [
        'Anini-y', 'Barbaza', 'Belison', 'Bugasong', 'Caluya', 'Culasi', 'Hamtic', 'Laua-an', 'Libertad',
        'Pandan', 'Patnongon', 'San Jose de Buenavista', 'San Remigio', 'Sebaste', 'Sibalom', 'Tibiao',
        'Tobias Fornier', 'Valderrama',
      ]) {
        total += (await geo.barangaysOf(m)).length;
      }
      expect(total, 590);
    });
  });

  group('Translations', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppLanguage.instance.load();
      await AppLanguage.instance.pick(AppLang.en);
    });

    test('every translation has Filipino and Kinaray-a with the same placeholders', () {
      final ph = RegExp(r'\{\w+\}');
      List<String> names(String s) => [for (final m in ph.allMatches(s)) m.group(0)!]..sort();
      expect(kStrings.length, greaterThan(700));
      for (final e in kStrings.entries) {
        for (final lang in ['fil', 'krj']) {
          final v = e.value[lang];
          expect(v, isNotNull, reason: '${e.key} has no $lang');
          expect(v!.trim(), isNotEmpty, reason: '${e.key} $lang is empty');
          expect(names(v), names(e.key), reason: '${e.key} ($lang) placeholders differ');
        }
      }
    });

    test('tr falls back to English and fills placeholders', () async {
      expect(tr('Records'), 'Records');
      await AppLanguage.instance.pick(AppLang.krj);
      expect(tr('Records'), 'Mga rekord');
      expect(tr('No pests found'), 'Wara it nakita nga peste');
      expect(tr('{n} days ago', {'n': 3}), '3 ka adlaw run ang nakaagi');
      expect(tr('A sentence nobody translated'), 'A sentence nobody translated');
      await AppLanguage.instance.pick(AppLang.fil);
      expect(tr('Validated'), 'Na-validate');
      expect(formatRelativeDay(DateTime.now().toIso8601String()), 'Ngayon');
    });

    test('a picked language wins over the account language and is remembered', () async {
      await AppLanguage.instance.pick(AppLang.fil);
      AppLanguage.instance.adoptAccountLanguage('krj');
      expect(AppLanguage.instance.lang, AppLang.fil);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('appLanguage'), 'fil');
    });

    testWidgets('screens rebuild in the new language at once', (tester) async {
      await tester.pumpWidget(LanguageScope(
        child: MaterialApp(home: Builder(builder: (context) => Text(context.tr('Records')))),
      ));
      expect(find.text('Records'), findsOneWidget);
      await AppLanguage.instance.pick(AppLang.krj);
      await tester.pump();
      expect(find.text('Mga rekord'), findsOneWidget);
      await AppLanguage.instance.pick(AppLang.en);
    });
  });

  group('Records', () {
    test('a pest-free result is a closed record, not a waiting one', () {
      final r = Record(server: {
        'id': 7,
        'client_uuid': 'u7',
        'report_type': 'pest',
        'status': 'no_pests',
        'detection_result': 'no_pests_found',
        'image_deleted': true,
        'ai': {'status': 'done', 'result': 'no_pests_found', 'message': 'No pests were found in this photo.'},
      });
      expect(r.state, RecordState.noPests);
      expect(r.imageDeleted, isTrue);
      expect(r.ai!.noPests, isTrue);
      expect(r.title, 'No pests found');
      expect(recordStateLabel(r.state), 'No pests found');
    });

    test('uncertain results stay for technician validation', () {
      final r = Record(server: {
        'id': 8,
        'client_uuid': 'u8',
        'report_type': 'pest',
        'status': 'pending',
        'detection_result': 'uncertain',
        'ai': {'status': 'done', 'result': 'uncertain'},
      });
      expect(r.state, RecordState.forValidation);
      expect(r.ai!.noPests, isFalse);
    });
  });
}
