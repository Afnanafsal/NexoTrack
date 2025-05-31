import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

class LocationManager extends ChangeNotifier {
  static final LocationManager _instance = LocationManager._internal();
  factory LocationManager() => _instance;
  LocationManager._internal();

  Position? _currentPosition;
  bool _isLocationEnabled = false;
  bool _hasPermission = false;
  StreamSubscription<Position>? _positionStream;
  String _locationError = '';

  // Getters
  Position? get currentPosition => _currentPosition;
  bool get isLocationEnabled => _isLocationEnabled;
  bool get hasPermission => _hasPermission;
  String get locationError => _locationError;

  double? get latitude => _currentPosition?.latitude;
  double? get longitude => _currentPosition?.longitude;
  double? get accuracy => _currentPosition?.accuracy;
  double? get altitude => _currentPosition?.altitude;
  double? get speed => _currentPosition?.speed;

  // Initialize location services
  Future<bool> initialize() async {
    try {
      // Check if location services are enabled
      _isLocationEnabled = await Geolocator.isLocationServiceEnabled();
      if (!_isLocationEnabled) {
        _locationError = 'Location services are disabled';
        notifyListeners();
        return false;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _locationError = 'Location permissions are denied';
          notifyListeners();
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _locationError = 'Location permissions are permanently denied';
        notifyListeners();
        return false;
      }

      _hasPermission = true;

      // Get initial position
      await getCurrentLocation();

      // Start location stream
      startLocationStream();

      _locationError = '';
      notifyListeners();
      return true;
    } catch (e) {
      _locationError = 'Failed to initialize location: $e';
      notifyListeners();
      return false;
    }
  }

  // Get current location once
  Future<Position?> getCurrentLocation() async {
    if (!_hasPermission || !_isLocationEnabled) {
      return null;
    }

    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );
      notifyListeners();
      return _currentPosition;
    } catch (e) {
      _locationError = 'Failed to get current location: $e';
      notifyListeners();
      return null;
    }
  }

  // Start continuous location updates
  void startLocationStream() {
    if (!_hasPermission || !_isLocationEnabled) return;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // Update every 10 meters
    );

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        _currentPosition = position;
        _locationError = '';
        notifyListeners();
        print('Location updated: ${position.latitude}, ${position.longitude}');
      },
      onError: (error) {
        _locationError = 'Location stream error: $error';
        notifyListeners();
      },
    );
  }

  // Stop location updates
  void stopLocationStream() {
    _positionStream?.cancel();
    _positionStream = null;
  }

  // Calculate distance between two points
  double distanceTo(double latitude, double longitude) {
    if (_currentPosition == null) return 0.0;

    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      latitude,
      longitude,
    );
  }

  // Calculate bearing to a point
  double bearingTo(double latitude, double longitude) {
    if (_currentPosition == null) return 0.0;

    return Geolocator.bearingBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      latitude,
      longitude,
    );
  }

  // Open location settings
  Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  // Open app settings
  Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  // Get formatted location string
  String get formattedLocation {
    if (_currentPosition == null) return 'Location not available';
    return '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}';
  }

  // Check if location is fresh (within last 5 minutes)
  bool get isLocationFresh {
    if (_currentPosition == null) return false;
    final now = DateTime.now();
    final locationTime = _currentPosition!.timestamp;
    return now.difference(locationTime).inMinutes < 5;
  }

  @override
  void dispose() {
    stopLocationStream();
    super.dispose();
  }
}
