import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<Position?> getLastKnownPosition() async {
    if (kIsWeb) {
      // Web doesn't support last known position
      return null;
    }
    return await Geolocator.getLastKnownPosition();
  }

  static Future<Position> getCurrentPosition({
    LocationAccuracy desiredAccuracy = LocationAccuracy.best,
    Duration? timeLimit,
  }) async {
    if (kIsWeb) {
      // Web-specific implementation
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: desiredAccuracy,
      );
    } else {
      // Mobile implementation with timeout
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: desiredAccuracy,
      ).timeout(
        timeLimit ?? const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException("Location request timed out"),
      );
    }
  }

  static Future<bool> isLocationServiceEnabled() async {
    if (kIsWeb) {
      // Web always returns true as we can't check this
      return true;
    }
    return await Geolocator.isLocationServiceEnabled();
  }

  static Future<LocationPermission> checkPermission() async {
    if (kIsWeb) {
      // Web has different permission handling
      return LocationPermission.whileInUse;
    }
    return await Geolocator.checkPermission();
  }

  static Future<LocationPermission> requestPermission() async {
    if (kIsWeb) {
      // Web permissions are handled by browser
      return LocationPermission.whileInUse;
    }
    return await Geolocator.requestPermission();
  }
}
