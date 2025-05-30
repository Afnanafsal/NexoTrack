import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class LiveLocationPage extends StatefulWidget {
  const LiveLocationPage({Key? key}) : super(key: key);

  @override
  State<LiveLocationPage> createState() => _LiveLocationPageState();
}

class _LiveLocationPageState extends State<LiveLocationPage>
    with TickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final MapController _mapController = MapController();
  final DateFormat formatter = DateFormat('yyyy-MM-dd');
  final DateFormat timeFormatter = DateFormat('HH:mm:ss');

  LatLng? _centerPosition;
  List<Marker> _markers = [];
  StreamSubscription<QuerySnapshot>? _attendanceSubscription;
  Map<String, Map<String, dynamic>> _staffLocations = {};
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isLoading = true;
  List<String> _allStaffIds = [];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _setDefaultCenter();
    _loadAllStaffAndListenToLocations();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _attendanceSubscription?.cancel();
    super.dispose();
  }

  void _setDefaultCenter() {
    // Set a default center (you can change this to your preferred location)
    setState(() {
      _centerPosition = const LatLng(
        37.7749,
        -122.4194,
      ); // San Francisco default
    });
  }

  Future<void> _loadAllStaffAndListenToLocations() async {
    try {
      // Get all users who have officeLocationId (staff members)
      final usersSnapshot =
          await _firestore
              .collection('users')
              .where('officeLocationId', isNotEqualTo: null)
              .get();

      setState(() {
        _allStaffIds = usersSnapshot.docs.map((doc) => doc.id).toList();
      });

      _listenToStaffLocations();
    } catch (e) {
      debugPrint('Error loading staff IDs: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _listenToStaffLocations() {
    final today = formatter.format(DateTime.now());

    // Create a composite query for all staff attendance logs for today
    _loadTodaysAttendanceData(today);

    // Set up a timer to refresh data every 30 seconds
    Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        _loadTodaysAttendanceData(today);
      }
    });
  }

  Future<void> _loadTodaysAttendanceData(String today) async {
    try {
      Map<String, Map<String, dynamic>> latestStaffLocations = {};

      // Get latest location data for each staff member
      for (String staffId in _allStaffIds) {
        try {
          final attendanceQuery =
              await _firestore
                  .collection('attendanceLogs')
                  .doc(staffId)
                  .collection(today)
                  .orderBy('punchIn', descending: true)
                  .limit(1)
                  .get();

          if (attendanceQuery.docs.isNotEmpty) {
            final latestData = attendanceQuery.docs.first.data();

            // Check if this entry has location data
            if (latestData['location'] != null) {
              final geoPoint = latestData['location'] as GeoPoint;

              // Get user name
              final userDoc =
                  await _firestore.collection('users').doc(staffId).get();
              final userName =
                  userDoc.exists
                      ? (userDoc.data()?['name'] ??
                          userDoc.data()?['email'] ??
                          'Unknown Staff')
                      : 'Unknown Staff';

              latestStaffLocations[staffId] = {
                ...latestData,
                'staffId': staffId,
                'staffName': userName,
                'latitude': geoPoint.latitude,
                'longitude': geoPoint.longitude,
                'lastUpdate': latestData['punchIn'],
              };
            }
          }
        } catch (e) {
          debugPrint('Error loading data for staff $staffId: $e');
        }
      }

      if (mounted) {
        setState(() {
          _staffLocations = latestStaffLocations;
          _isLoading = false;

          // Center map on first staff location if available
          if (_staffLocations.isNotEmpty) {
            final firstStaff = _staffLocations.values.first;
            final lat = firstStaff['latitude'] as double;
            final lng = firstStaff['longitude'] as double;
            _centerPosition = LatLng(lat, lng);

            // Only move map if it's the initial load
            if (_staffLocations.length == 1) {
              _mapController.move(_centerPosition!, 12);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading today\'s attendance data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showStaffInfo(String staffId, Map<String, dynamic> staffData) {
    final staffName = staffData['staffName'] ?? 'Unknown Staff';
    final status = staffData['status'] ?? 'Auto Data Entry';
    final timestamp = (staffData['lastUpdate'] as Timestamp?)?.toDate();
    final latitude = staffData['latitude'] as double;
    final longitude = staffData['longitude'] as double;
    final officeName = staffData['officeName'] ?? 'Unknown Office';
    final accuracy = staffData['accuracy'] as double?;
    final isAuto = staffData['isAutoPunch'] ?? false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                CircleAvatar(
                  radius: 30,
                  backgroundColor: _getStatusColor(isAuto).withOpacity(0.2),
                  child: Text(
                    staffName.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(isAuto),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  staffName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(isAuto).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isAuto) ...[
                        const Icon(
                          Icons.autorenew,
                          size: 14,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        isAuto ? 'AUTO TRACKING' : 'MANUAL ENTRY',
                        style: TextStyle(
                          color: _getStatusColor(isAuto),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoRow(Icons.business, 'Office', officeName),
                _buildInfoRow(
                  Icons.gps_fixed,
                  'Coordinates',
                  '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                ),
                if (accuracy != null)
                  _buildInfoRow(
                    Icons.my_location,
                    'Accuracy',
                    '${accuracy.toStringAsFixed(0)}m',
                  ),
                _buildInfoRow(Icons.info_outline, 'Status', status),
                if (timestamp != null)
                  _buildInfoRow(
                    Icons.access_time,
                    'Last Update',
                    _formatTime(timestamp),
                  ),
                const SizedBox(height: 20),
              ],
            ),
          ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(bool isAuto) {
    return isAuto ? Colors.green : Colors.blue;
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: const Text(
          'Staff Live Locations',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          IconButton(
            icon:
                _isLoading
                    ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.blue.shade800,
                      ),
                    )
                    : const Icon(Icons.refresh),
            onPressed:
                _isLoading
                    ? null
                    : () {
                      setState(() => _isLoading = true);
                      _loadTodaysAttendanceData(
                        formatter.format(DateTime.now()),
                      );
                    },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body:
          _isLoading
              ? _buildLoadingView()
              : Column(
                children: [
                  _buildStatusCard(),
                  Expanded(child: _buildMapView()),
                  _buildStaffList(),
                ],
              ),
    );
  }

  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Loading staff locations...',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    final autoStaffCount =
        _staffLocations.values
            .where((staff) => staff['isAutoPunch'] == true)
            .length;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder:
                (context, child) => Transform.scale(
                  scale: _pulseAnimation.value,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Live Staff Tracking',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  'Showing today\'s latest locations ($autoStaffCount auto-tracking)',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            '${_staffLocations.length}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Colors.blue,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'active',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildMapView() {
    if (_centerPosition == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _centerPosition!,
            initialZoom: 12,
            minZoom: 8,
            maxZoom: 18,
            interactionOptions: const InteractionOptions(
              flags: ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.example.nexotrack',
            ),
            MarkerLayer(markers: _buildMarkers()),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffList() {
    if (_staffLocations.isEmpty) {
      return Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.location_off, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text(
                'No staff locations available today',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Active Staff',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Today',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _staffLocations.length,
              itemBuilder: (context, index) {
                final staffId = _staffLocations.keys.elementAt(index);
                final staffData = _staffLocations[staffId]!;
                return _buildStaffAvatar(staffId, staffData);
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStaffAvatar(String staffId, Map<String, dynamic> staffData) {
    final name = staffData['staffName'] ?? 'Unknown';
    final isAuto = staffData['isAutoPunch'] ?? false;

    return GestureDetector(
      onTap: () => _showStaffInfo(staffId, staffData),
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _getStatusColor(isAuto).withOpacity(0.2),
                  child: Text(
                    name.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _getStatusColor(isAuto),
                    ),
                  ),
                ),
                if (isAuto)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.autorenew,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              name.split(' ').first,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  List<Marker> _buildMarkers() {
    List<Marker> markers = [];

    _staffLocations.forEach((staffId, staffData) {
      final latitude = staffData['latitude'] as double;
      final longitude = staffData['longitude'] as double;
      final position = LatLng(latitude, longitude);
      final name = staffData['staffName'] ?? 'Unknown';
      final isAuto = staffData['isAutoPunch'] ?? false;

      markers.add(
        Marker(
          point: position,
          width: 50,
          height: 50,
          child: GestureDetector(
            onTap: () => _showStaffInfo(staffId, staffData),
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: _getStatusColor(isAuto),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: _getStatusColor(isAuto).withOpacity(0.3),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                if (isAuto)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(
                        Icons.autorenew,
                        size: 10,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    });

    return markers;
  }
}
