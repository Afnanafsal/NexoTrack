// manage_locations.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

class OfficeLocation {
  final String id;
  final String name;
  final LatLng coordinates;

  OfficeLocation({
    required this.id,
    required this.name,
    required this.coordinates,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'lat': coordinates.latitude,
    'lng': coordinates.longitude,
  };

  static OfficeLocation fromDoc(DocumentSnapshot doc) => OfficeLocation(
    id: doc.id,
    name: doc['name'],
    coordinates: LatLng(doc['lat'], doc['lng']),
  );
}

class ManageLocationsPage extends StatefulWidget {
  const ManageLocationsPage({super.key});

  @override
  State<ManageLocationsPage> createState() => _ManageLocationsPageState();
}

class _ManageLocationsPageState extends State<ManageLocationsPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();

  LatLng _initialPosition = LatLng(10.0, 76.0);
  LatLng? _pickedLocation;

  Future<void> _searchAndSelect(String query) async {
    final url =
        'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1';
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'FlutterMapExample/1.0 (your@email.com)'},
      );

      final data = json.decode(response.body);
      if (data.isNotEmpty) {
        final lat = double.parse(data[0]['lat']);
        final lon = double.parse(data[0]['lon']);
        final newPosition = LatLng(lat, lon);

        setState(() {
          _pickedLocation = newPosition;
        });

        _mapController.move(newPosition, 15);
      } else {
        _showSnackBar('Location not found.');
      }
    } catch (e) {
      _showSnackBar('Search error: $e');
    }
  }

  Future<void> _saveLocation() async {
    if (_pickedLocation == null || _nameController.text.trim().isEmpty) return;

    await FirebaseFirestore.instance.collection('locations').add({
      'name': _nameController.text.trim(),
      'lat': _pickedLocation!.latitude,
      'lng': _pickedLocation!.longitude,
    });

    _nameController.clear();
    _pickedLocation = null;
    setState(() {});
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Office Locations')),
      backgroundColor: Colors.indigo.shade800,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Location Name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search (e.g., Kochi)',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _searchAndSelect(_searchController.text),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _saveLocation,
                  icon: const Icon(Icons.save),
                  label: const Text('Save Location'),
                ),
              ],
            ),
          ),
          const Divider(),
          SizedBox(
            height: 300,
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _initialPosition,
                initialZoom: 13,
                onTap: (tapPosition, point) {
                  setState(() {
                    _pickedLocation = point;
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                  subdomains: ['a', 'b', 'c'],
                ),
                if (_pickedLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _pickedLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_pin,
                          size: 40,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('locations')
                      .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final locations =
                    snapshot.data!.docs
                        .map((doc) => OfficeLocation.fromDoc(doc))
                        .toList();
                return ListView.builder(
                  itemCount: locations.length,
                  itemBuilder: (context, index) {
                    final loc = locations[index];
                    return ListTile(
                      title: Text(loc.name),
                      subtitle: Text(
                        'Lat: ${loc.coordinates.latitude}, Lng: ${loc.coordinates.longitude}',
                      ),
                      leading: const Icon(
                        Icons.location_on,
                        color: Colors.indigo,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
