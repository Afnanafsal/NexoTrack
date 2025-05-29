// live_location.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

class LiveLocationPage extends StatefulWidget {
  const LiveLocationPage({super.key});

  @override
  State<LiveLocationPage> createState() => _LiveLocationPageState();
}

class _LiveLocationPageState extends State<LiveLocationPage> {
  final MapController _mapController = MapController();
  LatLng _center = const LatLng(10.0, 76.3);

  /// Optional: Reverse geocode first marker
  Future<void> _fetchInitialCenter(List<LatLng> points) async {
    if (points.isEmpty) return;

    final point = points.first;
    setState(() => _center = point);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live Staff Locations')),
      body: StreamBuilder<QuerySnapshot>(
        stream:
            FirebaseFirestore.instance
                .collection('tracking')
                .where('active', isEqualTo: true)
                .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          final markers =
              docs.map((doc) {
                final lat = doc['lat'] as double;
                final lng = doc['lng'] as double;
                return Marker(
                  width: 40,
                  height: 40,
                  point: LatLng(lat, lng),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.green,
                    size: 40,
                  ),
                );
              }).toList();

          if (markers.isNotEmpty) {
            _fetchInitialCenter(markers.map((m) => m.point).toList());
          }

          return FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 13,
              interactionOptions: const InteractionOptions(
                flags:
                    InteractiveFlag.drag |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName:
                    'com.example.nexotrack', // replace with your package
              ),
              MarkerLayer(markers: markers),
            ],
          );
        },
      ),
    );
  }
}
