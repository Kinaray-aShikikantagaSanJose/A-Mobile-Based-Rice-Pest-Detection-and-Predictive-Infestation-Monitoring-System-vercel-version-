import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

enum GpsStatus { detecting, ok, serviceDisabled, permissionDenied, error }

class GpsResult {
  final GpsStatus status;
  final double? lat;
  final double? lng;

  /// Horizontal accuracy in metres as the phone reports it (null if unknown).
  final double? accuracy;

  /// True when the fix is an older position the phone remembered (no fresh fix).
  final bool stale;

  /// True when location access is blocked for this app ("Don't ask again").
  /// Only the phone's app settings can turn it back on.
  final bool deniedForever;

  const GpsResult(this.status, [this.lat, this.lng, this.accuracy, this.stale = false]) : deniedForever = false;

  const GpsResult.deniedForever()
      : status = GpsStatus.permissionDenied,
        lat = null,
        lng = null,
        accuracy = null,
        stale = false,
        deniedForever = true;

  bool get hasFix => status == GpsStatus.ok && lat != null && lng != null;
}

/// Location detection driven entirely by the phone's own location status.
/// No in-app toggles: callers watch [serviceStatusStream] and re-detect
/// automatically whenever the phone's location service turns on.
class GpsService {
  /// Emits true/false as the phone's location service is enabled/disabled.
  /// ServiceStatus is an enum in this geolocator version, so compare
  /// against ServiceStatus.enabled instead of reading an `.enabled` field.
  /// Browsers don't report this (geolocator_web throws), so on the web the
  /// stream is empty and location is detected on demand only.
  static Stream<bool> get serviceStatusStream => kIsWeb
      ? const Stream<bool>.empty()
      : Geolocator.getServiceStatusStream()
          .map((status) => status == ServiceStatus.enabled);

  /// One detection attempt. Never throws — reports status instead.
  ///
  /// The permission dialog is shown only when [requestPermission] is true
  /// and the permission is still undecided (`denied`). Pass false for
  /// automatic retries so a refusal does not re-open the dialog in a loop.
  ///
  /// [precise] asks for the best accuracy the phone can give (used to find
  /// the barangay); it may take a little longer.
  static Future<GpsResult> getCurrentPosition({bool requestPermission = true, bool precise = false}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const GpsResult(GpsStatus.serviceDisabled);
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && requestPermission) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        return const GpsResult.deniedForever();
      }
      if (perm != LocationPermission.whileInUse && perm != LocationPermission.always) {
        return const GpsResult(GpsStatus.permissionDenied);
      }
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: precise ? LocationAccuracy.high : LocationAccuracy.medium,
            timeLimit: Duration(seconds: precise ? 15 : 10),
          ),
        );
        return GpsResult(GpsStatus.ok, pos.latitude, pos.longitude, _accuracy(pos.accuracy));
      } on TimeoutException {
        // No fresh fix yet (indoors / weak signal): a recent known
        // position is better than none (browsers have no last position).
        if (kIsWeb) return const GpsResult(GpsStatus.error);
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) {
          return GpsResult(GpsStatus.ok, last.latitude, last.longitude, _accuracy(last.accuracy), true);
        }
        return const GpsResult(GpsStatus.error);
      }
    } catch (_) {
      return const GpsResult(GpsStatus.error);
    }
  }

  static double? _accuracy(double a) => a.isFinite && a > 0 ? a : null;

  /// Opens this app's system settings page (to re-allow a blocked
  /// permission). Never throws.
  static Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  /// Opens the phone's location settings (to turn location on). Never throws.
  static Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }
}
