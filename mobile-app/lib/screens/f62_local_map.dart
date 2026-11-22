import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_router.dart';
import '../l10n/app_language.dart';
import '../services/api_client.dart';
import '../services/gps_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../widgets/app_widgets.dart';
import '../widgets/motion.dart';
import '../widgets/scan_map.dart';

/// One validated observation on the map (from /analytics/hotspots).
class _Point {
  final int id;
  final String pest;
  final String pestKey;
  final String? level;
  final String barangay;
  final String municipality;
  final double lat;
  final double lng;
  final String createdAt;
  final int? count;
  final String cropStage;

  _Point.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        pest = j['pest'] as String? ?? '',
        pestKey = j['pest_key'] as String? ?? '',
        level = j['level'] as String?,
        barangay = j['barangay'] as String? ?? '',
        municipality = j['municipality'] as String? ?? '',
        lat = (j['lat'] as num).toDouble(),
        lng = (j['lng'] as num).toDouble(),
        createdAt = j['created_at'] as String? ?? '',
        count = (j['count'] as num?)?.toInt(),
        cropStage = j['crop_stage'] as String? ?? '';

  String get place => [barangay, municipality].where((x) => x.isNotEmpty).join(', ');
}

/// One barangay's validated observations: centre, count, highest level.
class _Hotspot {
  final String barangay;
  final String municipality;
  final double lat;
  final double lng;
  final int records;
  final String level;
  final String latest;
  final List<String> pests;

  _Hotspot.fromJson(Map<String, dynamic> j)
      : barangay = j['barangay'] as String? ?? '',
        municipality = j['municipality'] as String? ?? '',
        lat = (j['lat'] as num).toDouble(),
        lng = (j['lng'] as num).toDouble(),
        records = (j['records'] as num?)?.toInt() ?? 0,
        level = j['level'] as String? ?? 'LOW',
        latest = j['latest'] as String? ?? '',
        pests = [for (final p in (j['pests'] as List? ?? const [])) '$p'];
}

const Map<String, String> _pestShort = {
  'brown_planthopper': 'BPH',
  'green_leafhopper': 'GLH',
  'rice_bug': 'Rice bug',
  'rice_stem_borer': 'Stem borer',
  'disease': 'Disease',
};

/// Great-circle distance in km.
double _km(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1), dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

String _distance(BuildContext context, double km) => km < 1
    ? context.tr('{n} m away', {'n': (km * 1000).round()})
    : context.tr('{n} km away', {'n': km.toStringAsFixed(km < 10 ? 1 : 0)});

/// Technicians: validated records near them (their coverage area), as pins
/// coloured by infestation level and one risk circle per barangay, or as a
/// heatmap of the same records. Also shows the directional spread per pest.
class F62LocalMap extends StatefulWidget {
  const F62LocalMap({super.key});

  @override
  State<F62LocalMap> createState() => _F62LocalMapState();
}

/// Arrow colours for the directional spread, one per pest (same as the dashboard).
const List<Color> _spreadColors = [Color(0xFF7C3AED), Color(0xFF0F766E), Color(0xFFBE185D), Color(0xFF1D4ED8)];

const String _heatNote = 'Intensity reflects reported cases, not total pest population.';
const String _spreadNote = 'Based on reported cases only. It shows observed movement, not a forecast.';

class _F62LocalMapState extends State<F62LocalMap> {
  static const _periods = [(30, '30 days'), (90, '3 months'), (365, '1 year')];

  int _days = 90;
  DateTimeRange? _range; // custom dates instead of [_days]
  String? _level; // null = all
  String? _pest; // pest name, null = all
  String? _stage; // crop stage, null = all
  bool _heat = false; // false = markers
  bool _weightByCases = false; // false = weighted by infestation level
  List<_Point>? _points;
  List<_Hotspot> _hotspots = const [];
  List<String> _pests = const [];
  Map<String, dynamic>? _spread;
  String? _area;
  String? _error;
  String? _savedAt; // set when showing the copy saved on the phone
  bool _loading = false;
  GpsResult _me = const GpsResult(GpsStatus.detecting);

  @override
  void initState() {
    super.initState();
    _load();
    _locate(ask: false);
  }

  Map<String, String> get _query => {
        'start': isoDate(_range?.start ?? DateTime.now().subtract(Duration(days: _days))),
        if (_range != null) 'end': isoDate(_range!.end),
        'pest': ?_pest,
        'crop_stage': ?_stage,
      };

  String get _cacheKey {
    final q = _query..remove('start');
    final from = _range == null ? '$_days' : isoDate(_range!.start);
    return 'local_map_${from}_${q.entries.map((e) => '${e.key}=${e.value}').join('&')}';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final key = _cacheKey;
    try {
      final data = await ApiClient.get('/analytics/hotspots', query: _query) as Map<String, dynamic>;
      _apply(data);
      if (mounted) setState(() => _savedAt = null);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, jsonEncode({'saved_at': DateTime.now().toIso8601String(), 'data': data}));
      } catch (_) {}
    } on ApiException catch (e) {
      final cached = e.isOffline ? await _readCache(key) : null;
      if (!mounted) return;
      if (cached != null) {
        _apply(cached.$2);
        setState(() {
          _savedAt = cached.$1;
          _error = null;
        });
      } else {
        setState(() => _error = e.isOffline ? 'No signal, and no saved map for this period yet.' : e.message);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    await _loadSpread();
  }

  /// Week-to-week movement of each pest's validated cases (ending on the
  /// custom end date, or today).
  Future<void> _loadSpread() async {
    final query = {
      if (_range != null) 'end': isoDate(_range!.end),
      'pest': ?_pest,
      'crop_stage': ?_stage,
      'window': '7',
    };
    final key = 'local_spread_${query.entries.map((e) => '${e.key}=${e.value}').join('&')}';
    try {
      final data = await ApiClient.get('/analytics/spread', query: query) as Map<String, dynamic>;
      if (mounted) setState(() => _spread = data);
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, jsonEncode({'saved_at': DateTime.now().toIso8601String(), 'data': data}));
      } catch (_) {}
    } catch (_) {
      final cached = await _readCache(key);
      if (mounted) setState(() => _spread = cached?.$2);
    }
  }

  Future<(String, Map<String, dynamic>)?> _readCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return (j['saved_at'] as String, j['data'] as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  void _apply(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      _area = data['area'] as String?;
      _points = [
        for (final p in (data['points'] as List? ?? const []))
          if ((p as Map)['lat'] != null && p['lng'] != null) _Point.fromJson(p.cast<String, dynamic>()),
      ];
      _hotspots = [
        for (final h in (data['hotspots'] as List? ?? const [])) _Hotspot.fromJson((h as Map).cast<String, dynamic>()),
      ];
      final facets = data['facets'] as Map? ?? const {};
      _pests = [for (final p in (facets['pests'] as List? ?? const [])) '$p'];
      _error = null;
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _range ?? DateTimeRange(start: now.subtract(Duration(days: _days)), end: now),
      helpText: context.tr('Show records from'),
    );
    if (picked == null || !mounted) return;
    setState(() => _range = picked);
    _load();
  }

  Future<void> _locate({required bool ask}) async {
    final r = await GpsService.getCurrentPosition(requestPermission: ask);
    if (mounted) setState(() => _me = r);
    if (ask && !r.hasFix && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
            SnackBar(content: Text(context.tr('Could not find your location. Turn on location and try again.'))));
    }
  }

  double? _distanceTo(double lat, double lng) => _me.hasFix ? _km(_me.lat!, _me.lng!, lat, lng) : null;

  static const Map<String, double> _levelWeight = {'LOW': 1 / 3, 'MEDIUM': 2 / 3, 'HIGH': 1};

  List<Map<String, dynamic>> get _spreadItems =>
      [for (final p in (_spread?['pests'] as List? ?? const [])) (p as Map).cast<String, dynamic>()];

  @override
  Widget build(BuildContext context) {
    final points = (_points ?? const <_Point>[]).where((p) => _level == null || p.level == _level).toList();
    final hotspots = _hotspots.where((h) => _level == null || h.level == _level).toList();
    if (_me.hasFix) {
      hotspots.sort((a, b) => _distanceTo(a.lat, a.lng)!.compareTo(_distanceTo(b.lat, b.lng)!));
    }
    final spread = _spreadItems;
    final arrows = <ScanArrow>[
      for (final (i, s) in spread.indexed)
        if (s['status'] == 'moved' && s['from'] is Map && s['to'] is Map)
          ScanArrow(
            fromLat: ((s['from'] as Map)['lat'] as num).toDouble(),
            fromLng: ((s['from'] as Map)['lng'] as num).toDouble(),
            toLat: ((s['to'] as Map)['lat'] as num).toDouble(),
            toLng: ((s['to'] as Map)['lng'] as num).toDouble(),
            bearing: (s['bearing'] as num?)?.toDouble() ?? 0,
            color: _spreadColors[i % _spreadColors.length],
          ),
    ];
    final area = _area == null || _area!.isEmpty ? context.tr('No coverage area set on your account') : _area!;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              title: context.tr('Local map'),
              subtitle: area,
              actions: [
                AppCircleButton(
                  icon: Icons.my_location_rounded,
                  tooltip: context.tr('Show where I am'),
                  color: _me.hasFix ? AppColors.sky : null,
                  onTap: () => _locate(ask: true),
                ),
              ],
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, AppSpacing.xs, AppSpacing.hPad, AppSpacing.xl),
                  children: [
                    _Filters(
                      periods: _periods,
                      days: _range == null ? _days : null,
                      range: _range,
                      level: _level,
                      pests: _pests,
                      pest: _pest,
                      stage: _stage,
                      onDays: (d) {
                        setState(() {
                          _days = d;
                          _range = null;
                        });
                        _load();
                      },
                      onCustomRange: _pickRange,
                      onLevel: (l) => setState(() => _level = l),
                      onPest: (p) {
                        setState(() => _pest = p);
                        _load();
                      },
                      onStage: (s) {
                        setState(() => _stage = s);
                        _load();
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<bool>(
                            segments: [
                              ButtonSegment(
                                  value: false, label: Text(context.tr('Markers')), icon: const Icon(Icons.place_outlined)),
                              ButtonSegment(
                                  value: true, label: Text(context.tr('Heatmap')), icon: const Icon(Icons.blur_on_rounded)),
                            ],
                            selected: {_heat},
                            showSelectedIcon: false,
                            onSelectionChanged: (v) => setState(() => _heat = v.first),
                          ),
                        ),
                      ],
                    ),
                    if (_heat) ...[
                      const SizedBox(height: AppSpacing.sm),
                      SegmentedButton<bool>(
                        segments: [
                          ButtonSegment(value: false, label: Text(context.tr('By level'))),
                          ButtonSegment(value: true, label: Text(context.tr('By number of cases'))),
                        ],
                        selected: {_weightByCases},
                        showSelectedIcon: false,
                        onSelectionChanged: (v) => setState(() => _weightByCases = v.first),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    if (_savedAt != null) ...[
                      InfoBanner(
                        icon: Icons.cloud_off_rounded,
                        color: AppColors.textSecondary,
                        message: context.tr('No signal. Showing the map saved {date}.', {'date': formatDateTime(_savedAt)}),
                        actionLabel: context.tr('Retry'),
                        busy: _loading,
                        onAction: _load,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    if (_error != null && _points == null)
                      AppEmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: context.tr('Can\'t load the map'),
                        message: context.tr(_error!),
                        actionLabel: context.tr('Try again'),
                        onAction: _load,
                      )
                    else ...[
                      Stack(
                        children: [
                          ScanMap(
                            markers: [
                              if (!_heat)
                                for (final p in points)
                                  ScanMarker(
                                    lat: p.lat,
                                    lng: p.lng,
                                    severity: p.level ?? '',
                                    tag: points.length <= 15 && _pestShort[p.pestKey] != null
                                        ? context.tr(_pestShort[p.pestKey]!)
                                        : null,
                                  ),
                              if (_me.hasFix) ScanMarker(lat: _me.lat!, lng: _me.lng!, isUser: true),
                            ],
                            zones: [
                              if (!_heat)
                                for (final h in hotspots)
                                  ScanZone(
                                    lat: h.lat,
                                    lng: h.lng,
                                    radiusMeters: (220 + 70 * h.records).clamp(220, 900).toDouble(),
                                    risk: h.level,
                                  ),
                            ],
                            heatPoints: [
                              if (_heat)
                                for (final p in points)
                                  ScanHeatPoint(
                                    lat: p.lat,
                                    lng: p.lng,
                                    weight: _weightByCases ? 1 : (_levelWeight[p.level] ?? _levelWeight['LOW']!),
                                  ),
                            ],
                            heatMax: _weightByCases ? 3 : 1.5,
                            arrows: arrows,
                            height: 330,
                            zoom: 14,
                            interactive: true,
                            emptyMessage:
                                _points == null ? null : context.tr('No validated records with a location in this period.'),
                          ),
                          if (_heat)
                            Positioned(
                              left: 8,
                              right: 8,
                              bottom: 14,
                              child: IgnorePointer(
                                child: Align(
                                  alignment: Alignment.bottomLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: AppColors.surface.withValues(alpha: 0.92),
                                      borderRadius: BorderRadius.circular(AppRadius.sm),
                                    ),
                                    child: Text(context.tr(_heatNote),
                                        style: const TextStyle(
                                            fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                  ),
                                ),
                              ),
                            ),
                          if (_loading)
                            const Positioned(
                              top: 10,
                              right: 10,
                              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_heat)
                        _HeatLegend(byCases: _weightByCases)
                      else
                        const Wrap(
                          spacing: AppSpacing.md,
                          runSpacing: 4,
                          children: [
                            _Dot(color: AppColors.primary, label: 'Low'),
                            _Dot(color: AppColors.orange, label: 'Medium'),
                            _Dot(color: AppColors.danger, label: 'High'),
                            _Dot(color: AppColors.sky, label: 'You'),
                          ],
                        ),
                      const SizedBox(height: AppSpacing.lg),
                      _Totals(points: points, hotspots: hotspots, loaded: _points != null),
                      const SizedBox(height: AppSpacing.xl),
                      AppSectionHeader(title: context.tr('Directional spread')),
                      const SizedBox(height: AppSpacing.md),
                      _SpreadCard(spread: _spread, items: spread),
                      if (hotspots.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xl),
                        AppSectionHeader(title: _me.hasFix ? context.tr('Hotspots nearest to you') : context.tr('Hotspots')),
                        const SizedBox(height: AppSpacing.md),
                        for (final (i, h) in hotspots.take(8).indexed) ...[
                          FadeSlideIn(index: i, child: _HotspotCard(hotspot: h, distanceKm: _distanceTo(h.lat, h.lng))),
                          const SizedBox(height: AppSpacing.md),
                        ],
                      ],
                      if (points.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        AppSectionHeader(title: context.tr('Latest validated records')),
                        const SizedBox(height: AppSpacing.md),
                        AppCard(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                          child: Column(
                            children: [
                              for (final (i, p) in points.take(10).indexed) ...[
                                if (i > 0) const Divider(height: 1),
                                _PointRow(point: p, distanceKm: _distanceTo(p.lat, p.lng)),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Low-to-high colour scale of the heatmap.
class _HeatLegend extends StatelessWidget {
  final bool byCases;
  const _HeatLegend({required this.byCases});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(byCases ? context.tr('Number of validated cases') : context.tr('Weighted by infestation level'),
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(context.tr('Low'), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    gradient: LinearGradient(
                      colors: [for (final (_, c) in kHeatStops) c],
                      stops: [for (final (t, _) in kHeatStops) t],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(context.tr('High'), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
        ],
      );
}

/// Where each pest's validated cases moved between the last two weeks.
class _SpreadCard extends StatelessWidget {
  final Map<String, dynamic>? spread;
  final List<Map<String, dynamic>> items;
  const _SpreadCard({required this.spread, required this.items});

  @override
  Widget build(BuildContext context) {
    final s = spread;
    final windows = [for (final w in (s?['windows'] as List? ?? const [])) (w as Map).cast<String, dynamic>()];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (windows.length == 2)
            Text(
              '${windows[0]['name']}: ${windows[0]['label']} · ${windows[1]['name']}: ${windows[1]['label']}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
            ),
          if (s == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(context.tr('Open the map with signal to see the direction.'), style: const TextStyle(fontSize: 14)),
            )
          else if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text('${s['not_enough_message'] ?? context.tr('Not enough data to show direction.')}',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            ),
          for (final (i, it) in items.indexed) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: it['status'] == 'moved'
                      ? Transform.rotate(
                          angle: ((it['bearing'] as num?)?.toDouble() ?? 0) * math.pi / 180,
                          child: Icon(Icons.navigation_rounded, color: _spreadColors[i % _spreadColors.length]),
                        )
                      : const Icon(Icons.remove_rounded, color: AppColors.textMuted),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${it['pest']}${it['direction'] != null ? ' · ${it['direction']}' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      Text('${it['message']}', style: const TextStyle(fontSize: 13.5, height: 1.35)),
                      Text('${it['detail']}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.35)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(context.tr(_spreadNote), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4)),
        ],
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  final List<(int, String)> periods;
  final int? days; // null = custom dates
  final DateTimeRange? range;
  final String? level;
  final List<String> pests;
  final String? pest;
  final String? stage;
  final ValueChanged<int> onDays;
  final VoidCallback onCustomRange;
  final ValueChanged<String?> onLevel;
  final ValueChanged<String?> onPest;
  final ValueChanged<String?> onStage;

  const _Filters({
    required this.periods,
    required this.days,
    required this.range,
    required this.level,
    required this.pests,
    required this.pest,
    required this.stage,
    required this.onDays,
    required this.onCustomRange,
    required this.onLevel,
    required this.onPest,
    required this.onStage,
  });

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool selected, VoidCallback onTap, {Color? color}) => Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child: ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) => onTap(),
            showCheckmark: false,
            selectedColor: color ?? AppColors.primaryDark,
            labelStyle: TextStyle(
              fontFamily: AppFonts.body,
              color: selected ? AppColors.surface : AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
            avatar: color == null
                ? null
                : Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.surface : color,
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
        );
    Widget row(List<Widget> chips) => SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: chips));
    final r = range;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row([
          for (final (d, label) in periods) chip(context.tr(label), days == d, () => onDays(d)),
          chip(
              r == null
                  ? context.tr('Custom dates')
                  : '${formatShortDate(isoDate(r.start))} - ${formatShortDate(isoDate(r.end))}',
              r != null,
              onCustomRange),
        ]),
        const SizedBox(height: 4),
        row([
          chip(context.tr('All pests'), pest == null, () => onPest(null)),
          for (final p in {...pests, ?pest}) chip(p, pest == p, () => onPest(p)),
        ]),
        const SizedBox(height: 4),
        row([
          chip(context.tr('All stages'), stage == null, () => onStage(null)),
          for (final s in kCropStages) chip(context.tr(s), stage == s, () => onStage(s)),
        ]),
        const SizedBox(height: 4),
        row([
          chip(context.tr('All levels'), level == null, () => onLevel(null)),
          chip(context.tr('Low'), level == 'LOW', () => onLevel('LOW'), color: AppColors.primary),
          chip(context.tr('Medium'), level == 'MEDIUM', () => onLevel('MEDIUM'), color: AppColors.orange),
          chip(context.tr('High'), level == 'HIGH', () => onLevel('HIGH'), color: AppColors.danger),
        ]),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  final List<_Point> points;
  final List<_Hotspot> hotspots;
  final bool loaded;
  const _Totals({required this.points, required this.hotspots, required this.loaded});

  @override
  Widget build(BuildContext context) {
    final high = hotspots.where((h) => h.level == 'HIGH').length;
    final pests = <String, int>{};
    for (final p in points) {
      pests[p.pest] = (pests[p.pest] ?? 0) + 1;
    }
    final top = pests.entries.isEmpty ? null : (pests.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
    Widget tile(String label, Widget value, IconData icon, Color color) => Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconTile(icon: icon, color: color, size: 32),
                const SizedBox(height: AppSpacing.sm),
                value,
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
              ],
            ),
          ),
        );
    const numStyle = TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w800);
    return Row(
      children: [
        tile(context.tr('Validated'),
            loaded ? CountUp(value: points.length, style: numStyle) : const Text('–', style: numStyle),
            Icons.verified_rounded, AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        tile(context.tr('High hotspots'),
            loaded ? CountUp(value: high, style: numStyle) : const Text('–', style: numStyle),
            Icons.local_fire_department_rounded, AppColors.danger),
        const SizedBox(width: AppSpacing.sm),
        tile(
          context.tr('Most reported'),
          Text(top ?? '–', maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, height: 1.7)),
          Icons.bug_report_rounded,
          AppColors.orange,
        ),
      ],
    );
  }
}

class _HotspotCard extends StatelessWidget {
  final _Hotspot hotspot;
  final double? distanceKm;
  const _HotspotCard({required this.hotspot, required this.distanceKm});

  @override
  Widget build(BuildContext context) {
    final h = hotspot;
    final color = levelColor(h.level);
    return AppCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 5, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    IconTile(icon: Icons.location_on_rounded, color: color, size: 42),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h.barangay, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                          Text(
                            [h.municipality, if (distanceKm != null) _distance(context, distanceKm!)].join(' · '),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${plural(h.records, 'record')} · ${h.pests.join(', ')}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppChip(label: levelLabel(h.level), color: color),
                        const SizedBox(height: 4),
                        Text(formatRelativeDay(h.latest), style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PointRow extends StatelessWidget {
  final _Point point;
  final double? distanceKm;
  const _PointRow({required this.point, required this.distanceKm});

  @override
  Widget build(BuildContext context) {
    final p = point;
    return InkWell(
      onTap: () => context.push(AppRouter.record, extra: p.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: levelColor(p.level), shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.count == null ? p.pest : '${p.pest} · ${plural(p.count!, 'insect')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  Text(
                    [p.place, formatRelativeDay(p.createdAt), if (distanceKm != null) _distance(context, distanceKm!)]
                        .where((x) => x.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (p.level != null) AppChip(label: levelLabel(p.level), color: levelColor(p.level)),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final String label;
  const _Dot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(context.tr(label), style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      );
}
