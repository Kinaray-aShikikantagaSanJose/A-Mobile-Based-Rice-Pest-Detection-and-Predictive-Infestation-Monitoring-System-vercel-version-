import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

enum GpsStatus { detecting, ok, serviceDisabled, permissionDenied, error }

class GpsResult {
  final GpsStatus status;
  final double? lat;
  final double? lng;

  /// True when location access is blocked for this app ("Don't ask again").
  /// Only the phone's app settings can turn it back on.
  final bool deniedForever;

  const GpsResult(this.status, [this.lat, this.lng]) : deniedForever = false;

  const GpsResult.deniedForever()
      : status = GpsStatus.permissionDenied,
        lat = null,
        lng = null,
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
  static Future<GpsResult> getCurrentPosition({bool requestPermission = true}) async {
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
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          ),
        );
        return GpsResult(GpsStatus.ok, pos.latitude, pos.longitude);
      } on TimeoutException {
        // No fresh fix yet (indoors / weak signal): a recent known
        // position is better than none.
        final last = await Geolocator.getLastKnownPosition();
        if (last != null) return GpsResult(GpsStatus.ok, last.latitude, last.longitude);
        return const GpsResult(GpsStatus.error);
      }
    } catch (_) {
      return const GpsResult(GpsStatus.error);
    }
  }

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
