import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Offline GPS geofencing for Antique: which municipality and barangay a
/// point is in.
///
/// Reads assets/geo/antique_barangays.geojson (18 municipalities, 590
/// barangays with PSGC codes; built by rice-pest-api/tools/build_antique_geojson.py
/// from faeldon/philippines-json-maps). It is bundled with the app, so
/// lookups work without signal. The API (app/geo.py) and the database
/// (palay_locate) use the same data and the same rules:
///
/// * The source maps are simplified one municipality at a time, so along
///   municipal borders neighbouring polygons overlap slightly or leave thin
///   gaps. Inside several polygons: the one the point is deepest inside.
///   Inside none but within [maxGapM] of one: that one, as [GeoStatus.nearest].
///   Farther: outside Antique.
/// * GPS accuracy decides how sure the answer is: worse than [maxAccuracyM]
///   is [GeoStatus.inaccurate]; closer to a boundary than the accuracy is
///   [GeoStatus.nearBoundary]. The app then suggests, but asks to confirm.
enum GeoStatus { inside, nearBoundary, nearest, inaccurate, outside, invalid }

class GeoPlace {
  final String psgc;
  final String barangay;
  final String municipality;
  final String municipalityPsgc;
  const GeoPlace(this.psgc, this.barangay, this.municipality, this.municipalityPsgc);

  @override
  String toString() => '$barangay, $municipality';
}

class GeoMatch {
  final GeoStatus status;
  final GeoPlace? place;

  /// Metres from the point to the barangay's nearest edge (inside matches).
  final double depthM;

  /// Metres from the point to the barangay (nearest matches; 0 when inside).
  final double distanceM;
  final double? accuracyM;

  /// Neighbouring barangays the GPS error could also put the person in.
  final List<GeoPlace> alternatives;

  const GeoMatch(this.status, this.place,
      {this.depthM = 0, this.distanceM = 0, this.accuracyM, this.alternatives = const []});

  bool get found => place != null;

  /// Sure enough to fill in without asking (the person can still change it).
  bool get confident => status == GeoStatus.inside;
}

class _Barangay {
  final GeoPlace place;
  final List<List<List<math.Point<double>>>> polygons; // polygon -> rings -> points
  final double minX, minY, maxX, maxY;
  _Barangay(this.place, this.polygons, this.minX, this.minY, this.maxX, this.maxY);

  bool nearBox(double x, double y, double margin) =>
      x >= minX - margin && x <= maxX + margin && y >= minY - margin && y <= maxY + margin;
}

class AntiqueGeofence {
  AntiqueGeofence._();
  static final AntiqueGeofence instance = AntiqueGeofence._();

  static const String asset = 'assets/geo/antique_barangays.geojson';
  static const double maxGapM = 300;
  static const double maxAccuracyM = 150;
  // Box around Antique incl. Caluya's islands, with a margin.
  static const double _minLng = 121.2, _minLat = 10.35, _maxLng = 122.4, _maxLat = 12.3;
  static const double _mPerDegLat = 110574.0;

  List<_Barangay>? _items;
  Future<void>? _loading;

  /// For tests: use this GeoJSON text instead of the bundled asset.
  @visibleForTesting
  void loadFromString(String geojson) => _items = _parse(geojson);

  /// Loads the bundled map once. A failed load can be retried later.
  Future<void> ensureLoaded() => _loading ??= _load().catchError((Object e) {
        _loading = null;
        throw e;
      });

  Future<void> _load() async {
    if (_items != null) return;
    // Bytes + utf8.decode instead of rootBundle.loadString: loadString hands
    // strings over 50 KB to a background isolate, which some environments
    // (widget tests, very old WebViews) never complete. The 256 KB decode
    // and parse take a few tens of milliseconds.
    final data = await rootBundle.load(asset);
    final text = utf8.decode(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    _items = _parse(text);
  }

  static List<_Barangay> _parse(String text) {
    final fc = jsonDecode(text) as Map<String, dynamic>;
    final out = <_Barangay>[];
    for (final f in (fc['features'] as List)) {
      final props = (f as Map)['properties'] as Map;
      final geom = f['geometry'] as Map;
      final raw = geom['type'] == 'Polygon' ? [geom['coordinates']] : geom['coordinates'] as List;
      var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
      final polys = <List<List<math.Point<double>>>>[];
      for (final poly in raw) {
        final rings = <List<math.Point<double>>>[];
        for (final ring in poly as List) {
          final pts = <math.Point<double>>[];
          for (final c in ring as List) {
            final x = (c[0] as num).toDouble(), y = (c[1] as num).toDouble();
            pts.add(math.Point(x, y));
          }
          rings.add(pts);
        }
        for (final p in rings.first) {
          minX = math.min(minX, p.x);
          minY = math.min(minY, p.y);
          maxX = math.max(maxX, p.x);
          maxY = math.max(maxY, p.y);
        }
        polys.add(rings);
      }
      out.add(_Barangay(
        GeoPlace('${props['psgc']}', '${props['barangay']}', '${props['municipality']}', '${props['municipality_psgc']}'),
        polys,
        minX,
        minY,
        maxX,
        maxY,
      ));
    }
    return out;
  }

  // ---------------------------------------------------------------- geometry

  static bool _inRing(double x, double y, List<math.Point<double>> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final xi = ring[i].x, yi = ring[i].y, xj = ring[j].x, yj = ring[j].y;
      if ((yi > y) != (yj > y) && x < (xj - xi) * (y - yi) / (yj - yi) + xi) inside = !inside;
    }
    return inside;
  }

  static bool _covers(_Barangay b, double x, double y) {
    for (final poly in b.polygons) {
      if (_inRing(x, y, poly.first) && !poly.skip(1).any((h) => _inRing(x, y, h))) return true;
    }
    return false;
  }

  /// Metres from the point to the nearest edge (local flat projection).
  static double _edgeDistance(_Barangay b, double lng, double lat) {
    final kx = 111320.0 * math.cos(lat * math.pi / 180);
    var best = double.infinity;
    for (final poly in b.polygons) {
      for (final ring in poly) {
        for (var i = 0; i + 1 < ring.length; i++) {
          final ax = (ring[i].x - lng) * kx, ay = (ring[i].y - lat) * _mPerDegLat;
          final bx = (ring[i + 1].x - lng) * kx, by = (ring[i + 1].y - lat) * _mPerDegLat;
          final dx = bx - ax, dy = by - ay;
          final seg = dx * dx + dy * dy;
          final t = seg == 0 ? 0.0 : (-(ax * dx + ay * dy) / seg).clamp(0.0, 1.0);
          final px = ax + t * dx, py = ay + t * dy;
          final d = px * px + py * py;
          if (d < best) best = d;
        }
      }
    }
    return math.sqrt(best);
  }

  // ---------------------------------------------------------------- lookups

  /// Where the GPS point is. Never throws for bad input (status invalid).
  Future<GeoMatch> locate(double lat, double lng, {double? accuracyM}) async {
    if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180 || (lat == 0 && lng == 0)) {
      return GeoMatch(GeoStatus.invalid, null, accuracyM: accuracyM);
    }
    if (lng < _minLng || lng > _maxLng || lat < _minLat || lat > _maxLat) {
      return GeoMatch(GeoStatus.outside, null, accuracyM: accuracyM);
    }
    await ensureLoaded();
    final items = _items!;
    final inside = [for (final b in items) if (b.nearBox(lng, lat, 0) && _covers(b, lng, lat)) b];
    if (inside.isNotEmpty) {
      final ranked = [for (final b in inside) (_edgeDistance(b, lng, lat), b)]
        ..sort((a, c) => a.$1 != c.$1 ? c.$1.compareTo(a.$1) : a.$2.place.psgc.compareTo(c.$2.place.psgc));
      final (depth, best) = ranked.first;
      final margin = math.max(accuracyM ?? 0, 25.0);
      final near = [
        for (final b in items)
          if (!identical(b, best) &&
              b.nearBox(lng, lat, margin / 90000) &&
              (_covers(b, lng, lat) || _edgeDistance(b, lng, lat) <= margin))
            b.place,
      ];
      final GeoStatus status;
      if (accuracyM != null && accuracyM > maxAccuracyM) {
        status = GeoStatus.inaccurate;
      } else if (accuracyM != null && depth < accuracyM && near.isNotEmpty) {
        status = GeoStatus.nearBoundary;
      } else {
        status = GeoStatus.inside;
      }
      return GeoMatch(status, best.place,
          depthM: depth, accuracyM: accuracyM, alternatives: near.take(4).toList());
    }
    const margin = maxGapM / 90000;
    final near = [
      for (final b in items)
        if (b.nearBox(lng, lat, margin)) (_edgeDistance(b, lng, lat), b),
    ].where((t) => t.$1 <= maxGapM).toList()
      ..sort((a, c) => a.$1 != c.$1 ? a.$1.compareTo(c.$1) : a.$2.place.psgc.compareTo(c.$2.place.psgc));
    if (near.isNotEmpty) {
      final status = accuracyM != null && accuracyM > maxAccuracyM ? GeoStatus.inaccurate : GeoStatus.nearest;
      return GeoMatch(status, near.first.$2.place,
          distanceM: near.first.$1,
          accuracyM: accuracyM,
          alternatives: [for (final t in near.skip(1).take(3)) t.$2.place]);
    }
    return GeoMatch(GeoStatus.outside, null, accuracyM: accuracyM);
  }

  /// The barangays of [municipality] (official names, A-Z) for pickers.
  Future<List<GeoPlace>> barangaysOf(String municipality) async {
    await ensureLoaded();
    final m = _municipalityKey(municipality);
    if (m == null) return const [];
    return [for (final b in _items!) if (norm(b.place.municipality) == m) b.place]
      ..sort((a, c) => a.barangay.compareTo(c.barangay));
  }

  /// The official barangay for names a person typed (accents, case, "Brgy."
  /// and punctuation ignored), or null.
  Future<GeoPlace?> match(String municipality, String barangay) async {
    await ensureLoaded();
    final m = _municipalityKey(municipality);
    final b = norm(barangay);
    if (m == null || b.isEmpty) return null;
    for (final item in _items!) {
      if (norm(item.place.municipality) == m && norm(item.place.barangay) == b) return item.place;
    }
    return null;
  }

  String? _municipalityKey(String name) {
    final n = norm(name);
    if (n.isEmpty) return null;
    if (n == 'san jose') return norm('San Jose de Buenavista');
    if (n == 'dao') return norm('Tobias Fornier');
    return n;
  }

  static const Map<String, String> _accents = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n',
  };

  /// "Egaña" == "egana", "Brgy. Laua-an" == "laua an".
  static String norm(String name) {
    var s = name.toLowerCase();
    _accents.forEach((k, v) => s = s.replaceAll(k, v));
    s = s.replaceAll(RegExp(r'\b(brgy|bgy|barangay)\b\.?'), ' ');
    return s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
  }
}
