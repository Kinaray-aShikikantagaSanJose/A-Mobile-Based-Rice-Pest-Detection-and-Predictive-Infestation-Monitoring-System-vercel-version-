import 'package:flutter/material.dart';

import '../l10n/app_language.dart';
import '../services/antique_geofence.dart';
import '../services/gps_service.dart';
import '../theme.dart';

/// The result of "find my municipality and barangay from GPS".
class GpsAreaResult {
  final GpsResult gps;
  final GeoMatch? match;
  const GpsAreaResult(this.gps, this.match);

  GeoPlace? get place => match?.place;

  /// Good enough to fill the form without asking first.
  bool get usable =>
      match != null &&
      match!.place != null &&
      const {GeoStatus.inside, GeoStatus.nearBoundary, GeoStatus.nearest}.contains(match!.status);

  /// A place was found but the GPS is too imprecise to trust it blindly.
  bool get needsConfirmation => match?.status == GeoStatus.inaccurate && match?.place != null;
}

/// Longest wait for a location (including an unanswered permission prompt or
/// a browser that never answers); then the person picks the area by hand.
const Duration kGpsAreaTimeout = Duration(seconds: 25);

/// One GPS fix and an offline lookup in the Antique barangay map. Never throws
/// and always finishes (see [kGpsAreaTimeout]).
Future<GpsAreaResult> findAreaFromGps({bool ask = true}) async {
  final gps = await GpsService.getCurrentPosition(requestPermission: ask, precise: true)
      .timeout(kGpsAreaTimeout, onTimeout: () => const GpsResult(GpsStatus.error));
  if (!gps.hasFix) return GpsAreaResult(gps, null);
  try {
    final match = await AntiqueGeofence.instance
        .locate(gps.lat!, gps.lng!, accuracyM: gps.accuracy)
        .timeout(kGpsAreaTimeout);
    return GpsAreaResult(gps, match);
  } catch (e) {
    debugPrint('[GPS] barangay lookup failed: $e');
    return GpsAreaResult(gps, null);
  }
}

/// Status line under the municipality / barangay fields: what GPS found,
/// or why it couldn't, with "Try again" and (for an imprecise fix) "Use it".
class GpsAreaNote extends StatelessWidget {
  final bool busy;
  final GpsAreaResult? result;

  /// The found place was put in the fields.
  final bool applied;
  final VoidCallback? onRetry;
  final VoidCallback? onUseAnyway;

  const GpsAreaNote({
    super.key,
    required this.busy,
    required this.result,
    this.applied = false,
    this.onRetry,
    this.onUseAnyway,
  });

  @override
  Widget build(BuildContext context) {
    if (!busy && result == null) return const SizedBox.shrink();
    final (IconData icon, Color color, String text) = _content(context);
    return Container(
      key: const ValueKey('gps-area-note'),
      margin: const EdgeInsets.only(top: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color),
                  )
                : Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.35)),
                if (!busy && (onRetry != null || (result?.needsConfirmation == true && !applied)))
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      if (result?.needsConfirmation == true && !applied && onUseAnyway != null)
                        TextButton(onPressed: onUseAnyway, child: Text(context.tr('Use it'))),
                      if (onRetry != null && !(result?.usable == true && applied))
                        TextButton(onPressed: onRetry, child: Text(context.tr('Try again'))),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  (IconData, Color, String) _content(BuildContext context) {
    if (busy) {
      return (Icons.my_location_rounded, AppColors.primary, context.tr('Finding your barangay from your location…'));
    }
    final r = result!;
    final place = r.place == null ? '' : '${r.place!.barangay}, ${r.place!.municipality}';
    if (!r.gps.hasFix) {
      final text = switch (r.gps.status) {
        GpsStatus.serviceDisabled =>
          'Location is turned off. Choose your municipality and barangay below, or turn on location and try again.',
        GpsStatus.permissionDenied => 'Location permission is off. Choose your municipality and barangay below.',
        _ => 'Could not get your location. Choose your municipality and barangay below.',
      };
      return (Icons.location_off_rounded, AppColors.textSecondary, context.tr(text));
    }
    final m = r.match;
    if (m == null || m.status == GeoStatus.invalid) {
      return (Icons.location_off_rounded, AppColors.textSecondary,
          context.tr('Could not get your location. Choose your municipality and barangay below.'));
    }
    if (m.status == GeoStatus.outside) {
      return (Icons.wrong_location_rounded, AppColors.orange,
          context.tr('You seem to be outside Antique. Choose your municipality and barangay below.'));
    }
    if (r.needsConfirmation) {
      final n = (m.accuracyM ?? 0).round();
      return applied
          ? (Icons.check_circle_rounded, AppColors.primary,
              context.tr('Filled in from GPS: {place}. Please check it.', {'place': place}))
          : (Icons.gps_not_fixed_rounded, AppColors.orange,
              context.tr('Your GPS is not accurate yet (about {n} m), so this may be wrong: {place}.',
                  {'n': n, 'place': place}));
    }
    final near = m.status != GeoStatus.inside;
    final found = applied
        ? context.tr('Found from GPS: {place}. Change it below if this is not where you farm.', {'place': place})
        : context.tr('GPS shows {place}. Your saved area was kept.', {'place': place});
    return (
      Icons.where_to_vote_rounded,
      AppColors.primary,
      near ? '$found ${context.tr('You are near a barangay boundary, so please check it.')}' : found,
    );
  }
}
