import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' hide Path; // hide latlong2's Path so CustomPaint uses dart:ui Path
import '../theme.dart';
import '../utils/formatters.dart';
import 'motion.dart';

/// True for a usable GPS fix. Captures saved without a fix are stored at
/// (0, 0) and must not be drawn in the Gulf of Guinea.
bool _hasLocation(double lat, double lng) =>
    lat.isFinite &&
    lng.isFinite &&
    lat.abs() <= 90 &&
    lng.abs() <= 180 &&
    !(lat == 0 && lng == 0);

/// A map point with an optional tag label (e.g. "12 pests").
class ScanMarker {
  final double lat;
  final double lng;
  final String? tag;

  /// 'LOW' | 'MEDIUM' | 'HIGH' | '' colours the pin like [SeverityChip].
  /// Null keeps the default red pin.
  final String? severity;

  /// The phone's own position: drawn as a blue dot instead of a pin.
  final bool isUser;

  const ScanMarker({required this.lat, required this.lng, this.tag, this.severity, this.isUser = false});

  bool get hasLocation => _hasLocation(lat, lng);

  Color get pinColor => severity == null ? AppColors.danger : levelColor(severity);
}

/// A risk zone circle (official hotspot visualization): center, radius in
/// meters, and risk class ('LOW' | 'MEDIUM' | 'HIGH').
class ScanZone {
  final double lat;
  final double lng;
  final double radiusMeters;
  final String risk;
  const ScanZone({
    required this.lat,
    required this.lng,
    required this.radiusMeters,
    required this.risk,
  });

  bool get hasLocation => _hasLocation(lat, lng);

  String get _risk => risk.trim().toUpperCase();

  Color get borderColor => _risk == 'HIGH'
      ? AppColors.danger
      : (_risk == 'MEDIUM' ? AppColors.orange : AppColors.primary);

  Color get fillColor => borderColor.withValues(alpha: _risk == 'HIGH' || _risk == 'MEDIUM' ? 0.35 : 0.3);
}

/// One validated record on the heatmap. [weight] is its intensity
/// (e.g. 1/3, 2/3, 1 for LOW, MEDIUM, HIGH, or 1 per case).
class ScanHeatPoint {
  final double lat;
  final double lng;
  final double weight;
  const ScanHeatPoint({required this.lat, required this.lng, this.weight = 1});

  bool get hasLocation => _hasLocation(lat, lng);
}

/// Directional spread: from one window's centre of cases to the next.
class ScanArrow {
  final double fromLat, fromLng, toLat, toLng;

  /// Degrees clockwise from north.
  final double bearing;
  final Color color;
  const ScanArrow({
    required this.fromLat,
    required this.fromLng,
    required this.toLat,
    required this.toLng,
    required this.bearing,
    required this.color,
  });
}

/// Heatmap colours, low to high (same stops as the web dashboard).
const List<(double, Color)> kHeatStops = [
  (0.2, Color(0xFF2C7BB6)),
  (0.4, Color(0xFF00A6CA)),
  (0.6, Color(0xFF90EB9D)),
  (0.8, Color(0xFFF9D057)),
  (1.0, Color(0xFFD7191C)),
];

/// Terrain basemap (OpenTopoMap) when online; a labeled local terrain
/// preview with the same pins when offline, so maps never go blank.
///
/// The camera fits every located marker (and zone centre) and re-fits when
/// they change. Markers at (0, 0) (no GPS fix) are skipped. When nothing can
/// be drawn and [emptyMessage] is set, it is shown over the map.
class ScanMap extends StatefulWidget {
  final List<ScanMarker> markers;
  final List<ScanZone> zones;
  final double height;

  /// Zoom for a single marker, and the closest zoom used when fitting
  /// several markers.
  final double zoom;
  final bool interactive;

  /// Overlay text shown when there is no located marker or zone.
  final String? emptyMessage;

  /// Heatmap of validated records (drawn under the markers).
  final List<ScanHeatPoint> heatPoints;

  /// Combined weight at which the heat reaches the top colour.
  final double heatMax;

  /// Directional spread arrows.
  final List<ScanArrow> arrows;

  const ScanMap({
    super.key,
    required this.markers,
    this.heatPoints = const [],
    this.heatMax = 1.5,
    this.arrows = const [],
    this.zones = const [],
    this.height = 200,
    this.zoom = 14,
    this.interactive = false,
    this.emptyMessage,
  });

  @override
  ScanMapState createState() => ScanMapState();
}

class ScanMapState extends State<ScanMap> {
  static const String _probeUrl = 'https://tile.opentopomap.org/12/3418/1634.png';

  /// Philippines overview used when there is nothing to show.
  static const LatLng _fallbackCenter = LatLng(12.8797, 121.7740);
  static const double _fallbackZoom = 5;

  static const double _markerWidth = 140;
  static const double _markerHeight = 60;

  final MapController _controller = MapController();
  bool _mapReady = false;
  bool? _online; // null = still checking

  @override
  void initState() {
    super.initState();
    _probe();
  }

  @override
  void didUpdateWidget(covariant ScanMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_signature(_pointsOf(oldWidget)) != _signature(_points) || oldWidget.zoom != widget.zoom) {
      // Moving the camera notifies the map, so wait until this build is done.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fitCamera();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    try {
      final res = await http.head(Uri.parse(_probeUrl)).timeout(const Duration(seconds: 3));
      if (!mounted) return;
      setState(() => _online = res.statusCode < 500);
    } catch (_) {
      if (!mounted) return;
      setState(() => _online = false);
    }
  }

  List<ScanMarker> get _located => widget.markers.where((m) => m.hasLocation).toList();

  List<ScanZone> get _locatedZones => widget.zones.where((z) => z.hasLocation).toList();

  List<LatLng> get _points => _pointsOf(widget);

  static List<LatLng> _pointsOf(ScanMap w) => [
        for (final m in w.markers)
          if (m.hasLocation) LatLng(m.lat, m.lng),
        for (final z in w.zones)
          if (z.hasLocation) LatLng(z.lat, z.lng),
        for (final h in w.heatPoints)
          if (h.hasLocation) LatLng(h.lat, h.lng),
        for (final a in w.arrows) ...[LatLng(a.fromLat, a.fromLng), LatLng(a.toLat, a.toLng)],
      ];

  List<ScanHeatPoint> get _locatedHeat => widget.heatPoints.where((h) => h.hasLocation).toList();

  static String _signature(List<LatLng> pts) =>
      pts.map((p) => '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}').join('|');

  static bool _singleSpot(List<LatLng> pts) =>
      pts.every((p) => p.latitude == pts.first.latitude && p.longitude == pts.first.longitude);

  EdgeInsets get _fitPadding => EdgeInsets.fromLTRB(
        40,
        math.min(_markerHeight + 8, widget.height * 0.35),
        40,
        math.min(24, widget.height * 0.1),
      );

  void _fitCamera() {
    if (!_mapReady) return;
    final pts = _points;
    try {
      if (pts.isEmpty) {
        _controller.move(_fallbackCenter, _fallbackZoom);
      } else if (_singleSpot(pts)) {
        _controller.move(pts.first, widget.zoom);
      } else {
        _controller.fitCamera(
          CameraFit.coordinates(coordinates: pts, padding: _fitPadding, maxZoom: widget.zoom),
        );
      }
    } catch (e) {
      debugPrint('[MAP] camera fit skipped: $e');
    }
  }

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Stable, unique keys so markers that stay (e.g. when a filter changes)
  /// keep their state and only newly shown ones pop in.
  static List<Key> _markerKeys(List<ScanMarker> markers) {
    final seen = <String, int>{};
    return [
      for (final m in markers)
        () {
          final String id = '${m.lat},${m.lng},${m.severity},${m.tag}';
          final int n = seen[id] = (seen[id] ?? 0) + 1;
          return ValueKey<String>('$id#$n');
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final bool showEmpty = widget.emptyMessage != null &&
        _located.isEmpty &&
        _locatedZones.isEmpty &&
        _locatedHeat.isEmpty &&
        widget.arrows.isEmpty;
    final Widget base;
    if (_online == true) {
      base = KeyedSubtree(key: const ValueKey('online'), child: _onlineMap());
    } else if (_online == false) {
      base = KeyedSubtree(key: const ValueKey('offline'), child: _offlineView());
    } else {
      base = const _MapPlaceholder(key: ValueKey('probe'));
    }
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Shimmering placeholder while the tile server is probed, then a
            // cross-fade to the terrain map or the offline preview.
            AnimatedSwitcher(
              duration: _reduceMotion ? Duration.zero : AppMotion.medium,
              switchInCurve: AppMotion.curve,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (current, previous) =>
                  Stack(fit: StackFit.expand, children: [...previous, ?current]),
              child: base,
            ),
            if (showEmpty)
              FadeSlideIn(
                key: ValueKey<String>(widget.emptyMessage!),
                offset: 6,
                child: _emptyOverlay(widget.emptyMessage!),
              ),
            Positioned(
              top: AppSpacing.sm,
              left: AppSpacing.sm,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  // Hidden until the probe says which basemap is showing.
                  opacity: _online == null ? 0 : 1,
                  duration: _reduceMotion ? Duration.zero : AppMotion.medium,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryDark.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      _online == true ? 'TERRAIN' : 'OFFLINE PREVIEW',
                      style: const TextStyle(
                        color: AppColors.surface,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_online == true)
              Positioned(
                right: AppSpacing.xs,
                bottom: 2,
                child: IgnorePointer(
                  child: Text(
                    '© OpenStreetMap · OpenTopoMap',
                    style: TextStyle(
                      color: AppColors.primaryDark.withValues(alpha: 0.7),
                      fontSize: 8,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _emptyOverlay(String message) {
    return IgnorePointer(
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.lg),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  message,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.35),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _onlineMap() {
    final pts = _points;
    final bool fit = pts.isNotEmpty && !_singleSpot(pts);
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        backgroundColor: AppColors.border,
        initialCenter: pts.isEmpty ? _fallbackCenter : pts.first,
        initialZoom: pts.isEmpty ? _fallbackZoom : widget.zoom,
        initialCameraFit: fit
            ? CameraFit.coordinates(coordinates: pts, padding: _fitPadding, maxZoom: widget.zoom)
            : null,
        onMapReady: () {
          _mapReady = true;
          // Markers may have changed between creating the map and it
          // becoming ready; fitting again is a no-op otherwise.
          _fitCamera();
        },
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.pinchZoom |
                  InteractiveFlag.pinchMove |
                  InteractiveFlag.drag |
                  InteractiveFlag.doubleTapZoom
              : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'capstone.ricepest',
          maxZoom: 17,
        ),
        if (_locatedZones.isNotEmpty)
          // Zones fade in and settle to their full radius.
          _Reveal(
            reduceMotion: _reduceMotion,
            builder: (t) => CircleLayer(
              circles: [
                for (final z in _locatedZones)
                  CircleMarker(
                    point: LatLng(z.lat, z.lng),
                    radius: z.radiusMeters * (0.75 + 0.25 * t),
                    useRadiusInMeter: true,
                    color: z.fillColor.withValues(alpha: z.fillColor.a * t),
                    borderColor: z.borderColor.withValues(alpha: t),
                    borderStrokeWidth: 1.5,
                  ),
              ],
            ),
          ),
        if (_locatedHeat.isNotEmpty) _HeatLayer(points: _locatedHeat, max: widget.heatMax),
        if (widget.arrows.isNotEmpty) ...[
          PolylineLayer(
            polylines: [
              for (final a in widget.arrows)
                Polyline(
                  points: [LatLng(a.fromLat, a.fromLng), LatLng(a.toLat, a.toLng)],
                  color: a.color,
                  strokeWidth: 4,
                  borderColor: AppColors.surface,
                  borderStrokeWidth: 1.5,
                  pattern: StrokePattern.dashed(segments: const [10, 7]),
                ),
            ],
          ),
          MarkerLayer(
            markers: [
              for (final a in widget.arrows)
                Marker(
                  point: LatLng(a.toLat, a.toLng),
                  width: 28,
                  height: 28,
                  child: _ArrowHead(bearing: a.bearing, color: a.color),
                ),
            ],
          ),
        ],
        MarkerLayer(
          markers: () {
            final located = _located;
            final keys = _markerKeys(located);
            return [
              for (int i = 0; i < located.length; i++)
                Marker(
                  key: keys[i],
                  point: LatLng(located[i].lat, located[i].lng),
                  width: _markerWidth,
                  height: _markerHeight,
                  // Whole widget sits above the point so the pin tip marks it.
                  alignment: Alignment.topCenter,
                  child: _PopIn(index: i, child: _markerChild(located[i])),
                ),
            ];
          }(),
        ),
      ],
    );
  }

  Widget _offlineView() {
    final ms = _located;
    final zs = _locatedZones;
    final pts = _points;
    double centerLat = _fallbackCenter.latitude;
    double centerLng = _fallbackCenter.longitude;
    // Half the visible extent, in degrees.
    double span = 0.03;
    if (pts.isNotEmpty) {
      final lats = pts.map((p) => p.latitude);
      final lngs = pts.map((p) => p.longitude);
      final minLat = lats.reduce(math.min), maxLat = lats.reduce(math.max);
      final minLng = lngs.reduce(math.min), maxLng = lngs.reduce(math.max);
      centerLat = (minLat + maxLat) / 2;
      centerLng = (minLng + maxLng) / 2;
      span = math.max(span, math.max(maxLat - minLat, maxLng - minLng) / 2 * 1.4);
    }
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        double x(double lng) => ((lng - centerLng) / span) * w / 2 + w / 2;
        double y(double lat) => ((centerLat - lat) / span) * h / 2 + h / 2;
        final keys = _markerKeys(ms);
        final heat = _locatedHeat;
        return Stack(
          fit: StackFit.expand,
          children: [
            const CustomPaint(painter: _TerrainPainter()),
            if (heat.isNotEmpty)
              CustomPaint(
                painter: _HeatPainter(
                  [for (final h in heat) Offset(x(h.lng), y(h.lat))],
                  [for (final h in heat) h.weight],
                  max: widget.heatMax,
                ),
              ),
            for (final a in widget.arrows)
              CustomPaint(
                painter: _ArrowPainter(Offset(x(a.fromLng), y(a.fromLat)), Offset(x(a.toLng), y(a.toLat)), a.color),
              ),
            for (final z in zs)
              Builder(builder: (context) {
                // Approximate meters→degrees for the local ellipse.
                final degLat = z.radiusMeters / 111320.0;
                final degLng = z.radiusMeters / (111320.0 * math.cos(z.lat * math.pi / 180));
                final wPx = (degLng / span) * w;
                final hPx = (degLat / span) * h;
                return Positioned(
                  left: (x(z.lng) - wPx / 2).clamp(-wPx, w),
                  top: (y(z.lat) - hPx / 2).clamp(-hPx, h),
                  width: wPx,
                  height: hPx,
                  child: _Reveal(
                    reduceMotion: _reduceMotion,
                    builder: (t) => Opacity(
                      opacity: t,
                      child: Transform.scale(
                        scale: 0.75 + 0.25 * t,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: z.fillColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: z.borderColor, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            for (int i = 0; i < ms.length; i++)
              Positioned(
                key: keys[i],
                left: (x(ms[i].lng) - _markerWidth / 2).clamp(0.0, math.max(0.0, w - _markerWidth)),
                top: (y(ms[i].lat) - _markerHeight + 2).clamp(0.0, math.max(0.0, h - _markerHeight)),
                width: _markerWidth,
                height: _markerHeight,
                child: _PopIn(index: i, child: _markerChild(ms[i])),
              ),
          ],
        );
      },
    );
  }

  Widget _markerChild(ScanMarker m) {
    if (m.isUser) {
      // Centred low in the marker box so the dot sits on the point.
      return Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: AppColors.sky,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.surface, width: 3),
            boxShadow: [BoxShadow(color: AppColors.sky.withValues(alpha: 0.45), blurRadius: 10, spreadRadius: 4)],
          ),
        ),
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (m.tag != null && m.tag!.trim().isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryDark,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              m.tag!.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // The marker box is fixed-size; cap growth so the pin stays put.
              textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
              style: const TextStyle(
                color: AppColors.surface,
                fontSize: 9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        Icon(Icons.location_on, size: 30, color: m.pinColor),
      ],
    );
  }
}

/// Shimmering map-shaped placeholder shown while the tile server is probed.
class _MapPlaceholder extends StatelessWidget {
  const _MapPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ColoredBox(
        color: AppColors.border.withValues(alpha: 0.75),
        child: Center(
          child: Icon(
            Icons.map_outlined,
            size: 32,
            color: AppColors.surface.withValues(alpha: 0.8),
          ),
        ),
      ),
    );
  }
}

/// Runs [builder] with a 0 → 1 value once, when first built (zone circles).
class _Reveal extends StatelessWidget {
  final bool reduceMotion;
  final Widget Function(double t) builder;

  const _Reveal({required this.reduceMotion, required this.builder});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
      duration: reduceMotion ? Duration.zero : AppMotion.countUp,
      curve: AppMotion.curve,
      builder: (context, t, _) => builder(t.clamp(0.0, 1.0)),
    );
  }
}

/// Pin that pops up from its tip (slight overshoot) when first shown,
/// staggered by [index]. The delay lives in the curve, so no timers.
class _PopIn extends StatelessWidget {
  final int index;
  final Widget child;

  const _PopIn({required this.index, required this.child});

  static const Duration _pop = Duration(milliseconds: 380);

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final Duration delay = AppMotion.stagger * index.clamp(0, AppMotion.maxStagger);
    final Duration total = delay + _pop;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: Curves.easeOutBack,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.4 + 0.6 * t,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Deterministic terrain-styled basemap for offline use.
class _TerrainPainter extends CustomPainter {
  const _TerrainPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.background,
          AppColors.accentLight,
          Color.alphaBlend(AppColors.primary.withValues(alpha: 0.25), AppColors.accentLight),
          Color.alphaBlend(AppColors.primary.withValues(alpha: 0.4), AppColors.accentLight),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, paint);
    // Contour lines
    final contour = Paint()
      ..color = AppColors.primaryDark.withValues(alpha: 0.15)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (int i = 1; i <= 5; i++) {
      final path = Path();
      final baseY = size.height * i / 6;
      path.moveTo(0, baseY);
      for (double x = 0; x <= size.width; x += 8) {
        path.lineTo(
          x,
          baseY + math.sin((x / size.width) * math.pi * 2 + i) * 6,
        );
      }
      canvas.drawPath(path, contour);
    }
    // Grid
    final grid = Paint()
      ..color = AppColors.primaryDark.withValues(alpha: 0.06)
      ..strokeWidth = 0.5;
    for (double x = 0; x <= size.width; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y <= size.height; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


/// Heatmap layer for the online map: projects the points with the map
/// camera and paints them like [_HeatPainter].
class _HeatLayer extends StatelessWidget {
  final List<ScanHeatPoint> points;
  final double max;
  const _HeatLayer({required this.points, required this.max});

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _HeatPainter(
            [for (final p in points) camera.getOffsetFromOrigin(LatLng(p.lat, p.lng))],
            [for (final p in points) p.weight],
            max: max,
          ),
          size: Size(camera.size.x, camera.size.y),
          isComplex: true,
        ),
      ),
    );
  }
}

/// Weather-map style heat: each point spreads its weight over nearby cells
/// (falling off with distance), the sum per cell is coloured low to high,
/// and the cells are blurred into smooth patches. Points are binned into
/// cells first, so thousands of records stay quick to draw.
class _HeatPainter extends CustomPainter {
  final List<Offset> points;
  final List<double> weights;
  final double max;
  static const double _cell = 6;
  static const double _radius = 26;

  _HeatPainter(this.points, this.weights, {required this.max});

  static Color colorAt(double t) {
    if (t <= kHeatStops.first.$1) return kHeatStops.first.$2;
    for (var i = 1; i < kHeatStops.length; i++) {
      final (b, cb) = kHeatStops[i];
      final (a, ca) = kHeatStops[i - 1];
      if (t <= b) return Color.lerp(ca, cb, (t - a) / (b - a))!;
    }
    return kHeatStops.last.$2;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.isEmpty) return;
    final cols = (size.width / _cell).ceil() + 1;
    final rows = (size.height / _cell).ceil() + 1;
    final bins = Float32List(cols * rows);
    for (var i = 0; i < points.length; i++) {
      final o = points[i];
      if (o.dx < -_radius || o.dy < -_radius || o.dx > size.width + _radius || o.dy > size.height + _radius) continue;
      final cx = (o.dx / _cell).floor().clamp(0, cols - 1);
      final cy = (o.dy / _cell).floor().clamp(0, rows - 1);
      bins[cy * cols + cx] += weights[i];
    }
    final heat = Float32List(cols * rows);
    final rc = (_radius / _cell).ceil();
    for (var cy = 0; cy < rows; cy++) {
      for (var cx = 0; cx < cols; cx++) {
        final w = bins[cy * cols + cx];
        if (w == 0) continue;
        for (var dy = -rc; dy <= rc; dy++) {
          final y = cy + dy;
          if (y < 0 || y >= rows) continue;
          for (var dx = -rc; dx <= rc; dx++) {
            final x = cx + dx;
            if (x < 0 || x >= cols) continue;
            final d = math.sqrt((dx * dx + dy * dy).toDouble()) * _cell / _radius;
            if (d >= 1) continue;
            heat[y * cols + x] += w * (1 - d) * (1 - d);
          }
        }
      }
    }
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 5, sigmaY: 5, tileMode: TileMode.decal),
    );
    final paint = Paint();
    for (var cy = 0; cy < rows; cy++) {
      for (var cx = 0; cx < cols; cx++) {
        final v = heat[cy * cols + cx] / max;
        if (v < 0.04) continue;
        final t = v.clamp(0.0, 1.0);
        paint.color = colorAt(t).withValues(alpha: 0.35 + 0.5 * t);
        canvas.drawRect(Rect.fromLTWH(cx * _cell, cy * _cell, _cell + 0.5, _cell + 0.5), paint);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeatPainter old) =>
      old.max != max || !identical(old.points, points) || !identical(old.weights, weights);
}

class _ArrowHead extends StatelessWidget {
  final double bearing;
  final Color color;
  const _ArrowHead({required this.bearing, required this.color});

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: bearing * math.pi / 180,
        child: CustomPaint(painter: _ArrowHeadPainter(color)),
      );
}

class _ArrowHeadPainter extends CustomPainter {
  final Color color;
  const _ArrowHeadPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w / 2, h * 0.08)
      ..lineTo(w * 0.85, h * 0.85)
      ..lineTo(w / 2, h * 0.65)
      ..lineTo(w * 0.15, h * 0.85)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.surface
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _ArrowHeadPainter old) => old.color != color;
}

/// Offline preview: a straight arrow between two projected points.
class _ArrowPainter extends CustomPainter {
  final Offset from, to;
  final Color color;
  const _ArrowPainter(this.from, this.to, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, line);
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    const len = 14.0;
    final head = Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo(to.dx - len * math.cos(angle - 0.45), to.dy - len * math.sin(angle - 0.45))
      ..lineTo(to.dx - len * math.cos(angle + 0.45), to.dy - len * math.sin(angle + 0.45))
      ..close();
    canvas.drawPath(head, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => old.from != from || old.to != to || old.color != color;
}
