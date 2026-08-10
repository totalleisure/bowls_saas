// Foreground-only current location and straight-line venue distance.
// Revision: 20260730-phase2d2-distance.
import 'dart:async';

import 'package:geolocator/geolocator.dart';

class DeviceLocationPoint {
  const DeviceLocationPoint({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final DateTime capturedAt;
}

enum DeviceLocationFailureReason {
  servicesDisabled,
  permissionDenied,
  permissionDeniedForever,
  timedOut,
  unavailable,
}

class DeviceLocationException implements Exception {
  const DeviceLocationException(this.reason, this.message);

  final DeviceLocationFailureReason reason;
  final String message;

  @override
  String toString() => message;
}

class DeviceLocationService {
  DeviceLocationService._();

  static const Duration _cacheLifetime = Duration(minutes: 15);
  static DeviceLocationPoint? _cachedLocation;

  static double? coordinate(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().trim());
  }

  static bool hasCoordinates(Map<String, dynamic> venue) {
    return coordinate(venue['latitude']) != null &&
        coordinate(venue['longitude']) != null;
  }

  static Future<DeviceLocationPoint> currentLocation({
    bool forceRefresh = false,
  }) async {
    final cached = _cachedLocation;

    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.capturedAt) < _cacheLifetime) {
      return cached;
    }

    var serviceEnabled = true;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
    } on UnsupportedError {
      // Some browser/platform implementations cannot report service state.
      // Continue and allow getCurrentPosition to decide.
    }

    if (!serviceEnabled) {
      throw const DeviceLocationException(
        DeviceLocationFailureReason.servicesDisabled,
        'Location services are switched off.',
      );
    }

    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw const DeviceLocationException(
        DeviceLocationFailureReason.permissionDenied,
        'Location permission was not granted.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw const DeviceLocationException(
        DeviceLocationFailureReason.permissionDeniedForever,
        'Location permission is blocked in the device settings.',
      );
    }

    Position? position;

    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } on TimeoutException {
      try {
        position = await Geolocator.getLastKnownPosition();
      } catch (_) {
        position = null;
      }

      if (position == null) {
        throw const DeviceLocationException(
          DeviceLocationFailureReason.timedOut,
          'The device could not determine its current location in time.',
        );
      }
    } catch (error) {
      if (error is DeviceLocationException) rethrow;

      throw DeviceLocationException(
        DeviceLocationFailureReason.unavailable,
        'Current location is unavailable: $error',
      );
    }

    final resolvedPosition = position;
    if (resolvedPosition == null) {
      throw const DeviceLocationException(
        DeviceLocationFailureReason.unavailable,
        'Current location is unavailable.',
      );
    }

    final location = DeviceLocationPoint(
      latitude: resolvedPosition.latitude,
      longitude: resolvedPosition.longitude,
      capturedAt: DateTime.now(),
    );

    _cachedLocation = location;
    return location;
  }

  static double? distanceMilesToVenue({
    required DeviceLocationPoint currentLocation,
    required Map<String, dynamic> venue,
  }) {
    final latitude = coordinate(venue['latitude']);
    final longitude = coordinate(venue['longitude']);

    if (latitude == null || longitude == null) return null;

    final metres = Geolocator.distanceBetween(
      currentLocation.latitude,
      currentLocation.longitude,
      latitude,
      longitude,
    );

    return metres / 1609.344;
  }

  static String formatMiles(double miles) {
    if (!miles.isFinite || miles < 0) return '';

    if (miles < 0.1) return 'under 0.1 miles';

    final rounded = miles < 100
        ? double.parse(miles.toStringAsFixed(1))
        : double.parse(miles.toStringAsFixed(0));

    final unit = (rounded - 1).abs() < 0.05 ? 'mile' : 'miles';
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);

    return '$text $unit';
  }

  static void clearCache() {
    _cachedLocation = null;
  }
}
