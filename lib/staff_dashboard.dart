import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:project47/locationservice.dart';
import 'package:project47/login.dart';

class StaffDashboard extends StatefulWidget {
  const StaffDashboard({super.key});

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard>
    with TickerProviderStateMixin {
  // Core State Variables
  bool isWithinOffice = false;
  bool isPunchedIn = false;
  bool isTracking = false;
  String officeName = "Loading...";
  String locationStatus = "Checking location...";
  String userName = "Loading...";

  // Timers
  Timer? locationCheckTimer;
  Timer? locationTrackingTimer;
  Timer? autoPunchTimer;
  Timer? autoRefreshTimer;
  Timer? autoPunchCountdownTimer;
  Timer? nextAutoPunchTimer;

  // Constants
  final double geofenceRadius = 25.0;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat formatter = DateFormat('yyyy-MM-dd');
  final DateFormat timeFormatter = DateFormat('HH:mm:ss');
  final DateFormat fullDateFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');

  // Location & Office Data
  double officeLat = 0.0;
  double officeLng = 0.0;
  String? staffOfficeId;
  List<Map<String, dynamic>> todaySessions = [];
  double totalWorkingHours = 0.0;

  // UI State
  bool isLoading = true;
  bool isAutoPunching = false;
  bool isRefreshing = false;
  String connectionStatus = "Connected";

  // Auto punch system
  int nextAutoPunchCountdown = 0;
  bool showNextAutoPunch = false;
  bool autoSystemActive = false;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late AnimationController _countdownController;
  late AnimationController _shimmerController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _countdownAnimation;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeApp();
    _startAutoRefresh();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _countdownController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);

    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );
    _countdownAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _countdownController, curve: Curves.easeInOut),
    );
    _shimmerAnimation = Tween<double>(begin: -2.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.linear),
    );
  }

  void _startAutoRefresh() {
    autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (mounted && !isLoading && !isAutoPunching) {
        await _refreshData();
      }
    });
  }

  Future<void> _refreshData() async {
    if (isRefreshing) return;

    setState(() => isRefreshing = true);
    try {
      await Future.wait([_loadTodaySessions(), _checkCurrentLocation()]);
      setState(() => connectionStatus = "Connected");
    } catch (e) {
      debugPrint('Auto refresh error: $e');
      setState(() => connectionStatus = "Connection issues");
    } finally {
      if (mounted) {
        setState(() => isRefreshing = false);
      }
    }
  }

  Future<void> _initializeApp() async {
    try {
      await _checkLocationPermission();
      await _loadUserData();
      await _loadStaffOfficeLocation();

      // Try to get initial location immediately
      await _checkCurrentLocation();

      // Then start periodic checks
      _startLocationCheck();
    } catch (e) {
      debugPrint('Initialization error: $e');
      if (mounted) {
        setState(() {
          officeName = "Initialization failed";
          locationStatus = "Please restart the app";
          isLoading = false;
          connectionStatus = "Error";
        });
      }
    }
  }

  @override
  void dispose() {
    locationCheckTimer?.cancel();
    locationTrackingTimer?.cancel();
    autoPunchTimer?.cancel();
    autoRefreshTimer?.cancel();
    autoPunchCountdownTimer?.cancel();
    nextAutoPunchTimer?.cancel();
    _pulseController.dispose();
    _scaleController.dispose();
    _countdownController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    try {
      var status = await Permission.location.status;
      if (!status.isGranted) {
        status = await Permission.location.request();
        if (status.isDenied) {
          if (mounted) {
            setState(() {
              locationStatus = "Location permission required";
            });
          }
          return;
        }
        if (status.isPermanentlyDenied) {
          if (mounted) {
            setState(() {
              locationStatus = "Enable location in app settings";
            });
          }
          await openAppSettings();
          return;
        }
      }

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            locationStatus = "Please enable location services";
          });
        }
        // Optionally prompt user to enable location services
        bool didEnable = await Geolocator.openLocationSettings();
        if (!didEnable && mounted) {
          setState(() {
            locationStatus = "Location services required";
          });
        }
        return;
      }
    } catch (e) {
      debugPrint('Permission check error: $e');
      if (mounted) {
        setState(() {
          locationStatus = "Permission check failed";
        });
      }
    }
  }

  Future<void> _loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && userDoc.data() != null) {
        final userData = userDoc.data()!;
        if (mounted) {
          setState(() {
            userName = userData['name'] ?? userData['email'] ?? 'Unknown User';
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (mounted) {
        setState(() {
          userName = _auth.currentUser?.email ?? 'Unknown User';
        });
      }
    }
  }

  Future<void> _loadStaffOfficeLocation() async {
    if (mounted) setState(() => isLoading = true);
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }

    try {
      DocumentSnapshot? userDoc;
      int retryCount = 0;
      const maxRetries = 3;

      while (retryCount < maxRetries) {
        try {
          userDoc = await _firestore.collection('users').doc(user.uid).get();
          break;
        } catch (e) {
          retryCount++;
          if (retryCount >= maxRetries) throw e;
          await Future.delayed(Duration(seconds: retryCount));
        }
      }

      if (userDoc == null || !userDoc.exists || userDoc.data() == null) {
        if (mounted) {
          setState(() {
            officeName = "User data not found";
            locationStatus = "Please contact admin to setup your account";
            isLoading = false;
          });
        }
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      staffOfficeId = userData['officeLocationId'];

      if (staffOfficeId == null || staffOfficeId!.isEmpty) {
        if (mounted) {
          setState(() {
            officeName = "No office assigned";
            locationStatus = "Contact admin to assign office location";
            isLoading = false;
          });
        }
        return;
      }

      DocumentSnapshot? officeDoc;
      retryCount = 0;

      while (retryCount < maxRetries) {
        try {
          officeDoc =
              await _firestore
                  .collection('officeLocations')
                  .doc(staffOfficeId)
                  .get();
          break;
        } catch (e) {
          retryCount++;
          if (retryCount >= maxRetries) throw e;
          await Future.delayed(Duration(seconds: retryCount));
        }
      }

      if (officeDoc == null || !officeDoc.exists || officeDoc.data() == null) {
        if (mounted) {
          setState(() {
            officeName = "Office location not found";
            locationStatus = "Contact admin about office setup";
            isLoading = false;
          });
        }
        return;
      }

      final officeData = officeDoc.data() as Map<String, dynamic>;
      officeLat = (officeData['latitude'] ?? 0.0).toDouble();
      officeLng = (officeData['longitude'] ?? 0.0).toDouble();
      officeName = officeData['name'] ?? "Office";

      if (officeLat == 0.0 || officeLng == 0.0) {
        if (mounted) {
          setState(() {
            officeName = "Invalid office coordinates";
            locationStatus = "Contact admin to fix office location";
            isLoading = false;
          });
        }
        return;
      }

      await _loadTodaySessions();
      _startLocationCheck();
      _startAutoPunchSystem();
    } catch (e) {
      debugPrint('Error loading office location: $e');
      if (mounted) {
        setState(() {
          officeName = "Connection error";
          locationStatus = "Check internet and try again";
          isLoading = false;
          connectionStatus = "Error";
        });
      }
    }
  }

  Future<void> _loadTodaySessions() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final today = formatter.format(DateTime.now());
      final query =
          await _firestore
              .collection('attendanceLogs')
              .doc(user.uid)
              .collection(today)
              .orderBy('punchIn')
              .get();

      final sessions =
          query.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList();

      double totalHours = 0.0;
      bool currentlyPunchedIn = false;

      for (int i = 0; i < sessions.length; i++) {
        final session = sessions[i];
        final punchIn = (session['punchIn'] as Timestamp).toDate();
        final punchOut =
            session['punchOut'] != null
                ? (session['punchOut'] as Timestamp).toDate()
                : null;

        if (punchOut != null) {
          totalHours += punchOut.difference(punchIn).inMinutes / 60;
        } else if (i == sessions.length - 1) {
          currentlyPunchedIn = true;
          totalHours += DateTime.now().difference(punchIn).inMinutes / 60;
        }
      }

      if (mounted) {
        setState(() {
          todaySessions = sessions;
          totalWorkingHours = totalHours;
          isPunchedIn = currentlyPunchedIn;
          if (!isAutoPunching) isLoading = false;
        });
      }

      if (currentlyPunchedIn && !isTracking) {
        _startLocationTracking();
      }
    } catch (e) {
      debugPrint('Error loading today sessions: $e');
      if (mounted && !isAutoPunching) {
        setState(() => isLoading = false);
      }
    }
  }

  void _startLocationCheck() {
    locationCheckTimer?.cancel();

    // First check immediately
    _checkCurrentLocation();

    // Then start periodic checks with longer interval
    locationCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (mounted && !isLoading) {
        await _checkCurrentLocation();
      }
    });
  }

  Future<void> _checkCurrentLocation() async {
    try {
      // Check if location services are enabled (mobile only)
      if (!kIsWeb) {
        bool serviceEnabled = await LocationService.isLocationServiceEnabled();
        if (!serviceEnabled) {
          if (mounted) {
            setState(() {
              locationStatus = "Please enable location services";
            });
          }
          bool didEnable = await Geolocator.openLocationSettings();
          if (!didEnable && mounted) {
            setState(() {
              locationStatus = "Location services required";
            });
          }
          return;
        }
      }

      // Check location permission status
      LocationPermission permission = await LocationService.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await LocationService.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              locationStatus = "Location permission denied";
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever && !kIsWeb) {
        if (mounted) {
          setState(() {
            locationStatus = "Location permissions permanently denied";
          });
        }
        await openAppSettings();
        return;
      }

      // Get position with platform-specific handling
      Position? position;
      try {
        if (!kIsWeb) {
          // Try last known position first on mobile
          position = await LocationService.getLastKnownPosition();
        }

        // If we don't have a position or we're on web, get fresh position
        if (position == null) {
          position = await LocationService.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.best,
            timeLimit: const Duration(seconds: kIsWeb ? 15 : 30),
          );
        }

        if (position != null) {
          _updateLocationStatus(position);
          if (isTracking && isPunchedIn) {
            await _recordLocation(position);
          }
        } else if (mounted) {
          setState(() {
            locationStatus = "Could not get current location";
          });
        }
      } catch (e) {
        debugPrint('Error getting position: $e');
        if (mounted) {
          setState(() {
            locationStatus =
                "Location error: ${e is TimeoutException ? 'Request timed out' : e.toString()}";
          });
        }
      }
    } catch (e) {
      debugPrint('Location check error: $e');
      if (mounted) {
        setState(() => locationStatus = "Location error: ${e.toString()}");
      }
    }
  }

  void _updateLocationStatus(Position position) {
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      officeLat,
      officeLng,
    );

    final nowWithinOffice = distance <= geofenceRadius;

    if (mounted) {
      setState(() {
        isWithinOffice = nowWithinOffice;
        locationStatus =
            isWithinOffice
                ? 'At $officeName (${distance.toStringAsFixed(0)}m)'
                : '${distance.toStringAsFixed(0)}m from $officeName';
      });
    }

    // Manage auto punch system based on location
    if (nowWithinOffice && !autoSystemActive) {
      _startAutoPunchSystem();
    } else if (!nowWithinOffice && autoSystemActive) {
      _stopAutoPunchSystem();
    }
  }

  void _startAutoPunchSystem() {
    if (autoSystemActive) return;

    setState(() {
      autoSystemActive = true;
      nextAutoPunchCountdown = 120; // 2 minutes
      showNextAutoPunch = true;
    });

    _startNextAutoPunchTimer();
    _performAutoPunch(); // Perform initial punch immediately
  }

  void _stopAutoPunchSystem() {
    setState(() {
      autoSystemActive = false;
      showNextAutoPunch = false;
    });
    nextAutoPunchTimer?.cancel();
  }

  void _startNextAutoPunchTimer() {
    nextAutoPunchTimer?.cancel();

    nextAutoPunchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted && autoSystemActive && isWithinOffice) {
        setState(() {
          nextAutoPunchCountdown--;
          if (nextAutoPunchCountdown <= 0) {
            nextAutoPunchCountdown = 120; // Reset to 2 minutes
            if (!isAutoPunching) {
              _performAutoPunch();
            }
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _performAutoPunch() async {
    if (!mounted || !isWithinOffice || isAutoPunching) return;

    setState(() {
      isAutoPunching = true;
    });

    _scaleController.forward();

    try {
      await _punchIn(isAuto: true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Auto data sent at ${timeFormatter.format(DateTime.now())}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Auto punch error: $e');
      if (mounted) {
        _showErrorSnackBar('Auto data send failed: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() => isAutoPunching = false);
        _scaleController.reverse();
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Retry',
          textColor: Colors.white,
          onPressed: () => _refreshData(),
        ),
      ),
    );
  }

  Future<void> _recordLocation(geo.Position position) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final today = formatter.format(DateTime.now());
      final activeSession = await _getActiveSession();

      if (activeSession != null && mounted) {
        await _firestore
            .collection('attendanceLogs')
            .doc(user.uid)
            .collection(today)
            .doc(activeSession.id)
            .collection('locationHistory')
            .add({
              'timestamp': Timestamp.now(),
              'location': GeoPoint(position.latitude, position.longitude),
              'accuracy': position.accuracy,
              'isWithinOffice': isWithinOffice,
            });
      }
    } catch (e) {
      debugPrint('Location recording error: $e');
    }
  }

  void _startLocationTracking() {
    if (isTracking) return;

    if (mounted) setState(() => isTracking = true);
    locationTrackingTimer = Timer.periodic(const Duration(minutes: 2), (
      _,
    ) async {
      if (isPunchedIn && mounted) {
        try {
          final position = await geo.Geolocator.getCurrentPosition(
            desiredAccuracy: geo.LocationAccuracy.high,
          );
          await _recordLocation(position);
        } catch (e) {
          debugPrint('Location tracking error: $e');
        }
      }
    });
  }

  void _stopLocationTracking() {
    locationTrackingTimer?.cancel();
    if (mounted) {
      setState(() => isTracking = false);
    }
  }

  Future<DocumentSnapshot?> _getActiveSession() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final today = formatter.format(DateTime.now());
      final query =
          await _firestore
              .collection('attendanceLogs')
              .doc(user.uid)
              .collection(today)
              .where('punchOut', isNull: true)
              .limit(1)
              .get();

      return query.docs.isNotEmpty ? query.docs.first : null;
    } catch (e) {
      debugPrint('Get active session error: $e');
      return null;
    }
  }

  Future<void> _punchIn({bool isAuto = false}) async {
    if (!mounted) return;
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
      );

      final now = DateTime.now();
      final sessionData = {
        'punchIn': Timestamp.now(),
        'location': GeoPoint(position.latitude, position.longitude),
        'officeId': staffOfficeId,
        'officeName': officeName,
        'userName': userName,
        'status': 'Auto Data Entry',
        'isAutoPunch': isAuto,
        'punchInTime': fullDateFormatter.format(now),
        'date': formatter.format(now),
        'accuracy': position.accuracy,
        'dataType': 'location_ping',
      };

      await _firestore
          .collection('attendanceLogs')
          .doc(user.uid)
          .collection(formatter.format(now))
          .add(sessionData);

      await _updateDailySummary(sessionData);
      await _loadTodaySessions();
    } catch (e) {
      debugPrint('Auto data send error: $e');
      rethrow;
    }
  }

  Future<void> _updateDailySummary(Map<String, dynamic> sessionData) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final today = formatter.format(DateTime.now());
      final summaryRef = _firestore
          .collection('dailySummary')
          .doc(user.uid)
          .collection('summaries')
          .doc(today);

      await _firestore.runTransaction((transaction) async {
        final summaryDoc = await transaction.get(summaryRef);

        if (summaryDoc.exists) {
          final existingData = summaryDoc.data()!;
          final locationPings = List<Map<String, dynamic>>.from(
            existingData['locationPings'] ?? [],
          );

          locationPings.add(sessionData);

          transaction.update(summaryRef, {
            'locationPings': locationPings,
            'totalLocationPings': locationPings.length,
            'lastLocationPing': Timestamp.now(),
            'lastUpdated': Timestamp.now(),
          });
        } else {
          transaction.set(summaryRef, {
            'date': today,
            'userName': userName,
            'officeName': officeName,
            'officeId': staffOfficeId,
            'locationPings': [sessionData],
            'totalLocationPings': 1,
            'lastLocationPing': Timestamp.now(),
            'createdAt': Timestamp.now(),
            'lastUpdated': Timestamp.now(),
          });
        }
      });
    } catch (e) {
      debugPrint('Update daily summary error: $e');
    }
  }

  String _formatCountdown(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildAdvancedPunchButton() {
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors:
              isWithinOffice && autoSystemActive
                  ? [Colors.blue.shade400, Colors.blue.shade700]
                  : [Colors.grey.shade400, Colors.grey.shade600],
        ),
        boxShadow: [
          BoxShadow(
            color: (isWithinOffice && autoSystemActive
                    ? Colors.blue
                    : Colors.grey)
                .withOpacity(0.4),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: isAutoPunching ? _scaleAnimation.value : 1.0,
            child: Container(
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isAutoPunching) ...[
                    const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'SENDING DATA...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ] else ...[
                    Icon(
                      autoSystemActive
                          ? Icons.location_searching
                          : Icons.location_off,
                      size: 45,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      autoSystemActive ? 'AUTO TRACKING' : 'TRACKING OFF',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (showNextAutoPunch && autoSystemActive) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Next ping in:',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _formatCountdown(nextAutoPunchCountdown),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSessionList() {
    if (todaySessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.location_searching,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No location data today',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Auto tracking will start when you enter the office',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: todaySessions.length,
      itemBuilder: (context, index) {
        final session = todaySessions[index];
        final punchIn = (session['punchIn'] as Timestamp).toDate();
        final isAuto = session['isAutoPunch'] ?? false;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade50, Colors.blue.shade100],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blue.shade200, width: 1),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.location_on,
                color: Colors.white,
                size: 24,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    'Location Ping - ${timeFormatter.format(punchIn)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (isAuto) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.autorenew,
                          size: 14,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'AUTO',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Status: ${session['status'] ?? 'Data Entry'}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (session['accuracy'] != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Accuracy: ${(session['accuracy'] as double).toStringAsFixed(0)}m',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'LOGGED',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatsCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.blue.shade50, Colors.blue.shade100],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TODAY\'S TRACKING',
                        style: TextStyle(
                          fontSize:
                              MediaQuery.of(context).size.width < 400 ? 16 : 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userName,
                        style: TextStyle(
                          fontSize:
                              MediaQuery.of(context).size.width < 400 ? 12 : 14,
                          color: Colors.blue.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getConnectionStatusColor().withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: AnimatedBuilder(
                    animation:
                        isRefreshing
                            ? _pulseAnimation
                            : kAlwaysCompleteAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale:
                            isRefreshing
                                ? _pulseAnimation.value * 0.3 + 0.7
                                : 1.0,
                        child: Icon(
                          _getConnectionStatusIcon(),
                          color: _getConnectionStatusColor(),
                          size: 20,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    value: todaySessions.length.toString(),
                    label: 'Location Pings',
                    icon: Icons.location_on,
                    color: Colors.purple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    value: autoSystemActive ? 'Active' : 'Inactive',
                    label: '',
                    icon: autoSystemActive ? Icons.gps_fixed : Icons.gps_off,
                    color: autoSystemActive ? Colors.green : Colors.grey,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    value: isWithinOffice ? 'In' : 'Away',
                    label: 'Location',
                    icon: isWithinOffice ? Icons.business : Icons.location_off,
                    color: isWithinOffice ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getConnectionStatusColor() {
    switch (connectionStatus) {
      case "Connected":
        return Colors.green;
      case "Connection issues":
        return Colors.orange;
      case "Error":
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getConnectionStatusIcon() {
    switch (connectionStatus) {
      case "Connected":
        return Icons.cloud_done;
      case "Connection issues":
        return Icons.cloud_queue;
      case "Error":
        return Icons.cloud_off;
      default:
        return Icons.cloud;
    }
  }

  Widget _buildStatItem({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    // Determine text size based on value length
    final fontSize = value.length > 5 ? 16.0 : 20.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationStatus() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors:
              isWithinOffice
                  ? [Colors.green.shade50, Colors.green.shade100]
                  : [Colors.orange.shade50, Colors.orange.shade100],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              isWithinOffice ? Colors.green.shade200 : Colors.orange.shade200,
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isWithinOffice ? Colors.green : Colors.orange,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isWithinOffice ? Icons.location_on : Icons.location_off,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      officeName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      locationStatus,
                      style: TextStyle(
                        fontSize: 14,
                        color:
                            isWithinOffice
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('👋 Hi ', style: TextStyle(fontSize: 18)),
            Expanded(
              child: Text(
                userName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo.shade800,
        elevation: 0,
        actions: [
          IconButton(
            icon:
                isLoading || isRefreshing
                    ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.indigo.shade800,
                      ),
                    )
                    : const Icon(Icons.refresh),
            onPressed:
                isLoading || isRefreshing
                    ? null
                    : () async {
                      setState(() => isRefreshing = true);
                      await _refreshData();
                      setState(() => isRefreshing = false);
                    },
          ),

          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () async {
              try {
                await _auth.signOut();
                if (mounted) {
                  // Navigate to the login page
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error signing out: $e')),
                  );
                }
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildStatsCard(),
            _buildLocationStatus(),
            const SizedBox(height: 24),
            _buildAdvancedPunchButton(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                autoSystemActive
                    ? 'Auto tracking is active - Location data is being sent every 2 minutes'
                    : 'Enter office area to activate auto tracking',
                style: TextStyle(
                  fontSize: 14,
                  color:
                      autoSystemActive
                          ? Colors.green.shade700
                          : Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (autoSystemActive) ...[
              const SizedBox(height: 16),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade50, Colors.blue.shade100],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value * 0.3 + 0.7,
                          child: const Icon(
                            Icons.radar,
                            color: Colors.blue,
                            size: 20,
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Auto tracking system active',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.blue.shade600, Colors.blue.shade700],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_history,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'TODAY\'S LOCATION DATA',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 18,
                          ),
                        ),
                        const Spacer(),
                        if (todaySessions.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${todaySessions.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _buildSessionList(),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
