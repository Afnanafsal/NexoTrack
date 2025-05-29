// movement_history.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

class MovementHistoryPage extends StatefulWidget {
  const MovementHistoryPage({super.key});

  @override
  State<MovementHistoryPage> createState() => _MovementHistoryPageState();
}

class _MovementHistoryPageState extends State<MovementHistoryPage> {
  String? _selectedStaffId;
  DateTime _selectedDate = DateTime.now();

  Future<List<LatLng>> _fetchLocations() async {
    final start = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final end = start.add(Duration(days: 1));

    final query =
        await FirebaseFirestore.instance
            .collection('tracking')
            .where('staffId', isEqualTo: _selectedStaffId)
            .where('timestamp', isGreaterThanOrEqualTo: start)
            .where('timestamp', isLessThan: end)
            .orderBy('timestamp')
            .get();

    return query.docs.map((doc) => LatLng(doc['lat'], doc['lng'])).toList();
  }

  Future<int> _calculateWorkingMinutes() async {
    final start = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final end = start.add(Duration(days: 1));

    final punches =
        await FirebaseFirestore.instance
            .collection('attendance')
            .where('staffId', isEqualTo: _selectedStaffId)
            .where('timestamp', isGreaterThanOrEqualTo: start)
            .where('timestamp', isLessThan: end)
            .orderBy('timestamp')
            .get();

    int totalMinutes = 0;
    for (int i = 0; i < punches.docs.length; i += 2) {
      if (i + 1 < punches.docs.length) {
        final inTime = (punches.docs[i]['timestamp'] as Timestamp).toDate();
        final outTime =
            (punches.docs[i + 1]['timestamp'] as Timestamp).toDate();
        totalMinutes += outTime.difference(inTime).inMinutes;
      }
    }
    return totalMinutes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Staff Movement History')),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance.collection('staff').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return CircularProgressIndicator();
                final staffList = snapshot.data!.docs;
                return DropdownButton<String>(
                  hint: Text('Select Staff'),
                  value: _selectedStaffId,
                  onChanged: (val) => setState(() => _selectedStaffId = val),
                  items:
                      staffList.map((doc) {
                        return DropdownMenuItem(
                          value: doc.id,
                          child: Text(doc['name']),
                        );
                      }).toList(),
                );
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Date: ${DateFormat.yMMMd().format(_selectedDate)}'),
                TextButton(
                  child: Text('Pick Date'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2023),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _selectedDate = picked);
                  },
                ),
              ],
            ),
            ElevatedButton(
              onPressed:
                  _selectedStaffId == null ? null : () => setState(() {}),
              child: Text('View Movement'),
            ),
            Expanded(
              child: FutureBuilder<List<LatLng>>(
                future: _selectedStaffId == null ? null : _fetchLocations(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting)
                    return Center(child: CircularProgressIndicator());
                  final points = snapshot.data ?? [];
                  if (points.isEmpty)
                    return Center(child: Text('No data found'));
                  return FlutterMap(
                    options: MapOptions(
                      initialCenter: points.first,
                      initialZoom: 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                        subdomains: ['a', 'b', 'c'],
                      ),
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: points,
                            strokeWidth: 4,
                            color: Colors.blue,
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            FutureBuilder<int>(
              future:
                  _selectedStaffId == null ? null : _calculateWorkingMinutes(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return SizedBox();
                final hours = (snapshot.data! / 60).floor();
                final mins = snapshot.data! % 60;
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Total Working Hours: ${hours}h ${mins}m'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
