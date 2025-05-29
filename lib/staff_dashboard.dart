import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

class StaffDashboard extends StatefulWidget {
  const StaffDashboard({super.key});

  @override
  State<StaffDashboard> createState() => _StaffDashboardState();
}

class _StaffDashboardState extends State<StaffDashboard>
    with TickerProviderStateMixin {
  bool isWithinOffice = false;
  bool isPunchedIn = false;
  bool isTracking = false;
  String officeName = "Loading...";
  String locationStatus = "Checking location...";
  String userName = "Loading...";
  Timer? locationCheckTimer;
  Timer? locationTrackingTimer;
  Timer? autoPunchTimer;
  final double geofenceRadius = 25.0;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DateFormat formatter = DateFormat('yyyy-MM-dd');
  final DateFormat timeFormatter = DateFormat('HH:mm:ss');
  final DateFormat fullDateFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');

  double officeLat = 0.0;
  double officeLng = 0.0;
  String? staffOfficeId;
  List<Map<String, dynamic>> todaySessions = [];
  double totalWorkingHours = 0.0;
  bool isLoading = true;
  bool isAutoPunching = false;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _scaleController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeApp();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    _pulseController.repeat(reverse: true);
  }

  Future<void> _initializeApp() async {
    try {
      await _checkLocationPermission();
      await _loadUserData();
      await _loadStaffOfficeLocation();
    } catch (e) {
      debugPrint('Initialization error: $e');
      if (mounted) {
        setState(() {
          officeName = "Initialization failed";
          locationStatus = "Please restart the app";
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    locationCheckTimer?.cancel();
    locationTrackingTimer?.cancel();
    autoPunchTimer?.cancel();
    _pulseController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    try {
      var status = await Permission.location.status;
      if (!status.isGranted) {
        status = await Permission.location.request();
      }

      if (!status.isGranted) {
        if (mounted) {
          setState(() {
            locationStatus = "Location permission required";
          });
        }
        return;
      }

      // Check if location service is enabled
      bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            locationStatus = "Please enable location services";
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
      // Continue with default name if user data fails to load
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
      // Load user document with retry logic
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

      // Load office document with retry logic
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

      // Load today's sessions and start location services
      await _loadTodaySessions();
      _startLocationCheck();
      _startAutoPunchCheck();
    } catch (e) {
      debugPrint('Error loading office location: $e');
      if (mounted) {
        setState(() {
          officeName = "Connection error";
          locationStatus = "Check internet and try again";
          isLoading = false;
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
            data['id'] = doc.id; // Add document ID for reference
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
          // Last session is still active
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

      // Start location tracking if currently punched in
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
    locationCheckTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await _checkCurrentLocation();
    });
    // Check immediately
    _checkCurrentLocation();
  }

  Future<void> _checkCurrentLocation() async {
    try {
      final position = await geo.Geolocator.getCurrentPosition(
        desiredAccuracy: geo.LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      final distance = geo.Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        officeLat,
        officeLng,
      );

      final wasWithinOffice = isWithinOffice;
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

      // Record location if tracking
      if (isTracking && isPunchedIn) {
        await _recordLocation(position);
      }

      // Trigger auto-punch animation if just entered office
      if (!wasWithinOffice && nowWithinOffice && !isPunchedIn) {
        _triggerAutoPunchCheck();
      }
    } catch (e) {
      debugPrint('Location check error: $e');
      if (mounted) {
        setState(() => locationStatus = "Location unavailable");
      }
    }
  }

  void _startAutoPunchCheck() {
    autoPunchTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _triggerAutoPunchCheck();
    });
  }

  void _triggerAutoPunchCheck() {
    if (isWithinOffice && !isPunchedIn && !isAutoPunching && !isLoading) {
      _startAutoPunchAnimation();
    }
  }

  Future<void> _startAutoPunchAnimation() async {
    if (!mounted) return;

    setState(() => isAutoPunching = true);
    _scaleController.forward();

    // Show auto-punch dialog with animation
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            title: const Text('Auto Punch-In'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: const Icon(
                        Icons.location_on,
                        size: 60,
                        color: Colors.green,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                const Text('You are at the office location!'),
                const Text('Auto punch-in in 3 seconds...'),
              ],
            ),
          ),
    );

    // Wait 3 seconds then auto punch
    await Future.delayed(const Duration(seconds: 3));
    Navigator.of(context).pop(); // Close dialog

    await _performAutoPunch();
  }

  Future<void> _performAutoPunch() async {
    try {
      await _punchIn(isAuto: true);

      // Show success animation
      if (mounted) {
        _scaleController.reverse().then((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      'Auto punched in at ${timeFormatter.format(DateTime.now())}',
                    ),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Auto punch error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auto punch failed: ${e.toString()}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isAutoPunching = false);
      }
    }
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
    setState(() => isLoading = true);
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
        'status': 'In Progress',
        'isAutoPunch': isAuto,
        'punchInTime': fullDateFormatter.format(now),
        'date': formatter.format(now),
        'accuracy': position.accuracy,
      };

      await _firestore
          .collection('attendanceLogs')
          .doc(user.uid)
          .collection(formatter.format(now))
          .add(sessionData);

      // Create daily summary
      await _updateDailySummary(sessionData);

      _startLocationTracking();
      await _loadTodaySessions();
    } catch (e) {
      debugPrint('Punch in error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Punch in failed: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
      rethrow;
    }
  }

  Future<void> _punchOut() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final activeSession = await _getActiveSession();

      if (activeSession != null) {
        final position = await geo.Geolocator.getCurrentPosition(
          desiredAccuracy: geo.LocationAccuracy.high,
        );

        final now = DateTime.now();
        final punchInTime =
            (activeSession.data() as Map<String, dynamic>)['punchIn']
                as Timestamp;
        final duration = now.difference(punchInTime.toDate());

        final updateData = {
          'punchOut': Timestamp.now(),
          'status': 'Completed',
          'endLocation': GeoPoint(position.latitude, position.longitude),
          'punchOutTime': fullDateFormatter.format(now),
          'duration': duration.inMinutes,
          'durationFormatted':
              '${duration.inHours}h ${duration.inMinutes.remainder(60)}m',
        };

        await activeSession.reference.update(updateData);

        // Update daily summary
        await _updateDailySummary({
          ...activeSession.data() as Map<String, dynamic>,
          ...updateData,
        });

        _stopLocationTracking();
        await _loadTodaySessions();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Punched out successfully'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Punch out error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Punch out failed: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
        setState(() => isLoading = false);
      }
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
          final sessions = List<Map<String, dynamic>>.from(
            existingData['sessions'] ?? [],
          );

          // Update or add session
          final sessionIndex = sessions.indexWhere(
            (s) =>
                s['punchIn'] == sessionData['punchIn'] ||
                (s['punchInTime'] == sessionData['punchInTime']),
          );

          if (sessionIndex >= 0) {
            sessions[sessionIndex] = sessionData;
          } else {
            sessions.add(sessionData);
          }

          // Recalculate totals
          double totalHours = 0.0;
          int completedSessions = 0;

          for (final session in sessions) {
            if (session['duration'] != null) {
              totalHours += (session['duration'] as int) / 60.0;
              completedSessions++;
            }
          }

          transaction.update(summaryRef, {
            'sessions': sessions,
            'totalSessions': sessions.length,
            'completedSessions': completedSessions,
            'totalWorkingHours': totalHours,
            'lastUpdated': Timestamp.now(),
          });
        } else {
          // Create new summary
          transaction.set(summaryRef, {
            'date': today,
            'userName': userName,
            'officeName': officeName,
            'officeId': staffOfficeId,
            'sessions': [sessionData],
            'totalSessions': 1,
            'completedSessions': sessionData['status'] == 'Completed' ? 1 : 0,
            'totalWorkingHours':
                sessionData['duration'] != null
                    ? (sessionData['duration'] as int) / 60.0
                    : 0.0,
            'createdAt': Timestamp.now(),
            'lastUpdated': Timestamp.now(),
          });
        }
      });
    } catch (e) {
      debugPrint('Update daily summary error: $e');
    }
  }

  Widget _buildPunchButton() {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: isAutoPunching ? _scaleAnimation.value : 1.0,
          child: SizedBox(
            width: 200,
            height: 200,
            child: ElevatedButton(
              onPressed:
                  isWithinOffice && !isLoading && !isAutoPunching
                      ? () {
                        if (isPunchedIn) {
                          _punchOut();
                        } else {
                          _punchIn();
                        }
                      }
                      : null,
              style: ElevatedButton.styleFrom(
                shape: const CircleBorder(),
                backgroundColor:
                    isWithinOffice
                        ? isPunchedIn
                            ? Colors.redAccent
                            : Colors.greenAccent
                        : Colors.grey,
                padding: const EdgeInsets.all(24),
                elevation: 8,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isAutoPunching)
                    const CircularProgressIndicator(color: Colors.white)
                  else
                    Icon(
                      isPunchedIn ? Icons.logout : Icons.login,
                      size: 40,
                      color: Colors.white,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    isAutoPunching
                        ? 'AUTO PUNCHING...'
                        : isPunchedIn
                        ? 'PUNCH OUT'
                        : 'PUNCH IN',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSessionList() {
    if (todaySessions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No sessions today',
          style: TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
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
        final punchOut =
            session['punchOut'] != null
                ? (session['punchOut'] as Timestamp).toDate()
                : null;
        final duration =
            punchOut != null
                ? punchOut.difference(punchIn)
                : DateTime.now().difference(punchIn);
        final isAuto = session['isAutoPunch'] ?? false;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: punchOut == null ? Colors.green : Colors.blue,
              child: Icon(
                punchOut == null ? Icons.timer : Icons.check_circle,
                color: Colors.white,
              ),
            ),
            title: Row(
              children: [
                Text(
                  '${timeFormatter.format(punchIn)} - ${punchOut != null ? timeFormatter.format(punchOut) : 'Active'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (isAuto) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.autorenew, size: 16, color: Colors.orange),
                ],
              ],
            ),
            subtitle: Text(
              '${duration.inHours}h ${duration.inMinutes.remainder(60)}m${isAuto ? ' (Auto)' : ''}',
            ),
            trailing:
                punchOut == null
                    ? const Chip(
                      label: Text('Active'),
                      backgroundColor: Colors.green,
                      labelStyle: TextStyle(color: Colors.white),
                    )
                    : null,
          ),
        );
      },
    );
  }

  Widget _buildStatsCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'TODAY\'S SUMMARY - $userName',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  value: todaySessions.length.toString(),
                  label: 'Sessions',
                  icon: Icons.list_alt,
                ),
                _buildStatItem(
                  value: totalWorkingHours.toStringAsFixed(1),
                  label: 'Total Hours',
                  icon: Icons.timer,
                ),
                _buildStatItem(
                  value: isPunchedIn ? 'Active' : 'Inactive',
                  label: 'Status',
                  icon: isPunchedIn ? Icons.check_circle : Icons.pending,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required String value,
    required String label,
    required IconData icon,
  }) {
    return Column(
      children: [
        Icon(icon, size: 30, color: Colors.blue),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadTodaySessions();
              _checkCurrentLocation();
            },
          ),
        ],
      ),
      body:
          isLoading && !isAutoPunching
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                child: Column(
                  children: [
                    _buildStatsCard(),
                    const SizedBox(height: 16),
                    Text(
                      officeName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      locationStatus,
                      style: TextStyle(
                        fontSize: 16,
                        color: isWithinOffice ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildPunchButton(),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        isWithinOffice
                            ? isPunchedIn
                                ? 'You can punch out now'
                                : 'You can punch in now (Auto punch-in enabled)'
                            : 'Move closer to office to enable punch-in',
                        style: TextStyle(
                          fontSize: 14,
                          color: isWithinOffice ? Colors.green : Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (isTracking) ...[
                      const SizedBox(height: 16),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.green.withOpacity(0.3),
                          ),
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
                                    Icons.my_location,
                                    color: Colors.green,
                                    size: 20,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Location tracking active',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    const Divider(),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'TODAY\'S SESSIONS',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    _buildSessionList(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
    );
  }
}
