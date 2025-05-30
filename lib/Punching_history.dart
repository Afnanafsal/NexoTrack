import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';

class PunchingHistoryPage extends StatefulWidget {
  const PunchingHistoryPage({super.key});

  @override
  State<PunchingHistoryPage> createState() => _PunchingHistoryPageState();
}

class _PunchingHistoryPageState extends State<PunchingHistoryPage> {
  String? _selectedStaffId;
  String? _selectedStaffName;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  bool _showMap = false;
  List<Map<String, dynamic>> _staffList = [];
  List<Map<String, dynamic>> _locationHistory = [];
  double _totalWorkingHours = 0.0;

  @override
  void initState() {
    super.initState();
    _loadStaffList();
  }

  Future<void> _loadStaffList() async {
    setState(() => _isLoading = true);
    try {
      final query = await FirebaseFirestore.instance.collection('users').get();
      setState(() {
        _staffList =
            query.docs.map((doc) {
              final data = doc.data();
              return {
                'id': doc.id,
                'name': data['name'] ?? 'Unknown',
                'email': data['email'] ?? '',
                'role': data['role'] ?? 'Staff',
              };
            }).toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load staff list: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchPunchingData() async {
    if (_selectedStaffId == null) return;

    setState(() {
      _isLoading = true;
      _showMap = false;
      _locationHistory = [];
      _totalWorkingHours = 0.0;
    });

    try {
      // Format the selected date
      final formattedDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

      // Fetch location history
      final locationQuery =
          await FirebaseFirestore.instance
              .collection('attendanceLogs')
              .doc(_selectedStaffId)
              .collection(formattedDate)
              .orderBy('punchIn', descending: true)
              .get();

      final locations =
          locationQuery.docs.map((doc) {
            final data = doc.data();
            final geoPoint = data['location'] as GeoPoint;
            return {
              'id': doc.id,
              'timestamp': (data['punchIn'] as Timestamp).toDate(),
              'lat': geoPoint.latitude,
              'lng': geoPoint.longitude,
              'accuracy': data['accuracy'] ?? 0.0,
              'isAuto': data['isAutoPunch'] ?? false,
              'status': data['status'] ?? 'Location Ping',
            };
          }).toList();

      // Calculate working hours from attendance logs
      double totalHours = 0.0;
      for (int i = 0; i < locations.length; i++) {
        final session = locations[i];
        final punchIn = session['timestamp'] as DateTime;
        final punchOut =
            i < locations.length - 1
                ? locations[i + 1]['timestamp'] as DateTime
                : null;

        if (punchOut != null) {
          totalHours += punchOut.difference(punchIn).inMinutes / 60;
        }
      }

      setState(() {
        _locationHistory = locations;
        _totalWorkingHours = totalHours;
        _showMap = locations.isNotEmpty;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load Punching data: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildStaffDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          hint: const Text(
            'Select Staff Member',
            style: TextStyle(color: Colors.grey),
          ),
          value: _selectedStaffId,
          onChanged: (String? newValue) {
            setState(() {
              _selectedStaffId = newValue;
              _selectedStaffName =
                  _staffList.firstWhere(
                    (staff) => staff['id'] == newValue,
                  )['name'];
              _showMap = false;
            });
          },
          items:
              _staffList.map<DropdownMenuItem<String>>((
                Map<String, dynamic> staff,
              ) {
                return DropdownMenuItem<String>(
                  value: staff['id'],
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blue.shade100,
                        child: Text(staff['name'][0].toUpperCase()),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            staff['name'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            staff['email'],
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return GestureDetector(
      onTap: () async {
        final DateTime? picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Colors.blue,
                  onPrimary: Colors.white,
                  onSurface: Colors.black,
                ),
                textButtonTheme: TextButtonThemeData(
                  style: TextButton.styleFrom(foregroundColor: Colors.blue),
                ),
              ),
              child: child!,
            );
          },
        );
        if (picked != null && picked != _selectedDate) {
          setState(() {
            _selectedDate = picked;
            _showMap = false;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              DateFormat('MMMM d, yyyy').format(_selectedDate),
              style: const TextStyle(fontSize: 16),
            ),
            const Icon(Icons.calendar_today, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMapView() {
    if (!_showMap || _locationHistory.isEmpty) {
      return Container(
        height: 300,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _locationHistory.isEmpty
              ? 'No location data available'
              : 'Map will appear here',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    final points =
        _locationHistory.map((loc) => LatLng(loc['lat'], loc['lng'])).toList();

    return Container(
      height: 300,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: points.first,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c'],
              userAgentPackageName: 'com.example.app',
            ),
            PolylineLayer(
              polylines: [
                Polyline(
                  points: points,
                  color: Colors.blue.withOpacity(0.7),
                  strokeWidth: 4,
                ),
              ],
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: points.first,
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_pin,
                    color: Colors.red,
                    size: 40,
                  ),
                ),
                if (points.length > 1)
                  Marker(
                    point: points.last,
                    width: 40,
                    height: 40,
                    child: const Icon(
                      Icons.flag,
                      color: Colors.green,
                      size: 30,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    final hours = _totalWorkingHours.floor();
    final minutes = ((_totalWorkingHours - hours) * 60).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            icon: Icons.timelapse,
            value: '${hours}h ${minutes}m',
            label: 'Total Time',
            color: Colors.blue,
          ),
          _buildStatItem(
            icon: Icons.location_on,
            value: _locationHistory.length.toString(),
            label: 'Location Pings',
            color: Colors.green,
          ),
          _buildStatItem(
            icon: Icons.auto_awesome,
            value:
                _locationHistory
                    .where((loc) => loc['isAuto'])
                    .length
                    .toString(),
            label: 'Auto Pings',
            color: Colors.purple,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildLocationHistoryList() {
    if (_locationHistory.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.location_off, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No location data available',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _locationHistory.length,
      itemBuilder: (context, index) {
        final location = _locationHistory[index];
        final isAuto = location['isAuto'];
        final time = DateFormat('HH:mm:ss').format(location['timestamp']);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 5,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isAuto ? Colors.purple.shade50 : Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isAuto ? Icons.autorenew : Icons.location_on,
                color: isAuto ? Colors.purple : Colors.blue,
                size: 20,
              ),
            ),
            title: Text(
              time,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              'Accuracy: ${location['accuracy'].toStringAsFixed(0)}m',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            trailing: Text(
              isAuto ? 'AUTO' : 'MANUAL',
              style: TextStyle(
                color: isAuto ? Colors.purple : Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Staff Punching History',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_selectedStaffId != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchPunchingData,
            ),
        ],
      ),
      body:
          _isLoading && _staffList.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStaffDropdown(),
                    const SizedBox(height: 16),
                    _buildDateSelector(),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed:
                          _selectedStaffId == null
                              ? null
                              : () async {
                                await _fetchPunchingData();
                              },
                      child: const Text(
                        'View Punching History',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_selectedStaffId != null) ...[
                      _buildStatsCard(),
                      const SizedBox(height: 16),
                      _buildMapView(),
                      const SizedBox(height: 16),
                      const Text(
                        'Location History',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildLocationHistoryList(),
                    ],
                  ],
                ),
              ),
    );
  }
}
