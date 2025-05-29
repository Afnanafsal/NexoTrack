import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _latController = TextEditingController();
  final TextEditingController _lngController = TextEditingController();

  LatLng? _selectedLocation;
  String? _selectedAddress;
  LatLng? _currentLocation;
  List<Map<String, dynamic>> _existingLocations = [];
  bool _showLatLngInput = false;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _fetchExistingLocations();
    _requestLocationPermission();
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      _getCurrentLocation();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permission denied')),
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final loc = LatLng(position.latitude, position.longitude);
      final address = await _reverseGeocode(loc);

      setState(() {
        _currentLocation = loc;
        _selectedLocation = loc;
        _selectedAddress = address;
      });

      _mapController.move(loc, 16);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error getting location: $e')));
    } finally {
      setState(() => _isLocating = false);
    }
  }

  Future<void> _fetchExistingLocations() async {
    try {
      final snapshot =
          await FirebaseFirestore.instance
              .collection('officeLocations')
              .orderBy('timestamp', descending: true)
              .get();

      setState(() {
        _existingLocations =
            snapshot.docs.map((doc) {
              final data = doc.data();
              // Ensure latitude and longitude exist and are valid
              if (data['latitude'] == null || data['longitude'] == null) {
                return {
                  ...data,
                  'latitude': 0.0,
                  'longitude': 0.0,
                  'id': doc.id,
                };
              }
              return {...data, 'id': doc.id};
            }).toList();
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading locations: $e')));
    }
  }

  Future<List<String>> _getSuggestions(String query) async {
    if (query.isEmpty) return [];
    try {
      final url =
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(query)}&format=json&addressdetails=1&limit=5';
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'NexoTrack/1.0'},
      );

      if (response.statusCode != 200) return [];
      final results = json.decode(response.body) as List<dynamic>;
      return results.map<String>((e) => e['display_name'] as String).toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> _handleSearchSelection(String address) async {
    try {
      final url =
          'https://nominatim.openstreetmap.org/search?q=${Uri.encodeComponent(address)}&format=json&limit=1';
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'NexoTrack/1.0'},
      );

      if (response.statusCode != 200) return;
      final result = json.decode(response.body) as List<dynamic>;
      if (result.isEmpty) return;

      final latStr = result[0]['lat']?.toString();
      final lonStr = result[0]['lon']?.toString();
      if (latStr == null || lonStr == null) return;

      final lat = double.tryParse(latStr);
      final lon = double.tryParse(lonStr);
      if (lat == null || lon == null) return;

      final loc = LatLng(lat, lon);

      setState(() {
        _selectedLocation = loc;
        _selectedAddress =
            result[0]['display_name']?.toString() ?? 'Unnamed Location';
      });

      _mapController.move(loc, 16);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error searching location: $e')));
    }
  }

  Future<String> _reverseGeocode(LatLng point) async {
    try {
      final url =
          'https://nominatim.openstreetmap.org/reverse?lat=${point.latitude}&lon=${point.longitude}&format=json';
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'NexoTrack/1.0'},
      );

      if (response.statusCode != 200) return 'Unnamed Location';
      final data = json.decode(response.body);
      return data['display_name']?.toString() ?? 'Unnamed Location';
    } catch (e) {
      return 'Unnamed Location';
    }
  }

  void _handleLatLngInput() async {
    try {
      final lat = double.tryParse(_latController.text);
      final lng = double.tryParse(_lngController.text);

      if (lat == null || lng == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid latitude or longitude')),
        );
        return;
      }

      final loc = LatLng(lat, lng);
      final address = await _reverseGeocode(loc);

      setState(() {
        _selectedLocation = loc;
        _selectedAddress = address;
        _showLatLngInput = false;
      });

      _mapController.move(loc, 16);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing coordinates: $e')),
      );
    }
  }

  Future<void> _saveToFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _selectedLocation == null) return;

      final customName = _nameController.text.trim();
      if (customName.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter a name for the location")),
        );
        return;
      }

      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
      final role = userDoc.data()?['role']?.toString();

      if (role != 'admin') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only admins can save office locations.'),
          ),
        );
        return;
      }

      await FirebaseFirestore.instance.collection('officeLocations').add({
        'name': customName,
        'address': _selectedAddress ?? 'Unnamed Address',
        'latitude': _selectedLocation!.latitude,
        'longitude': _selectedLocation!.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _nameController.clear();
      _searchController.clear();
      _latController.clear();
      _lngController.clear();

      setState(() {
        _selectedLocation = null;
        _selectedAddress = null;
      });

      await _fetchExistingLocations();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Office location saved!')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving location: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pick Office Location"),
        actions: [
          IconButton(
            icon: const Icon(Icons.pin_drop),
            tooltip: 'Toggle Manual Lat/Lng Input',
            onPressed: () {
              setState(() {
                _showLatLngInput = !_showLatLngInput;
              });
            },
          ),
          IconButton(
            icon:
                _isLocating
                    ? const CircularProgressIndicator()
                    : const Icon(Icons.my_location),
            tooltip: 'Get Current Location',
            onPressed: _getCurrentLocation,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TypeAheadField<String>(
              controller: _searchController,
              suggestionsCallback: _getSuggestions,
              builder: (context, controller, focusNode) {
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Search location',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                );
              },
              itemBuilder:
                  (context, suggestion) => ListTile(title: Text(suggestion)),
              onSelected: (value) {
                _searchController.text = value;
                _handleSearchSelection(value);
              },
              emptyBuilder:
                  (context) => const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text('No results found'),
                  ),
            ),
          ),

          if (_showLatLngInput)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _latController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: "Latitude",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _lngController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: "Longitude",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: 'Find location by Lat/Lng',
                    onPressed: _handleLatLngInput,
                  ),
                ],
              ),
            ),

          if (_selectedAddress != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _selectedAddress!,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: "Enter a name for this location",
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _saveToFirestore,
                    icon: const Icon(Icons.save),
                    label: const Text("Save to Firestore"),
                  ),
                ],
              ),
            ),

          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(10.0, 76.3),
                initialZoom: 6,
                interactionOptions: const InteractionOptions(
                  flags:
                      InteractiveFlag.drag |
                      InteractiveFlag.pinchZoom |
                      InteractiveFlag.doubleTapZoom,
                ),
                onTap: (tapPosition, point) async {
                  final address = await _reverseGeocode(point);
                  setState(() {
                    _selectedLocation = point;
                    _selectedAddress = address;
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.example.yourapp',
                ),
                if (_currentLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _currentLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.person_pin_circle,
                          color: Colors.green,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                if (_selectedLocation != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: _selectedLocation!,
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers:
                      _existingLocations
                          .where((loc) {
                            final lat = loc['latitude'] as double?;
                            final lng = loc['longitude'] as double?;
                            return lat != null && lng != null;
                          })
                          .map(
                            (loc) => Marker(
                              point: LatLng(
                                loc['latitude'] as double,
                                loc['longitude'] as double,
                              ),
                              width: 35,
                              height: 35,
                              child: Tooltip(
                                message: loc['name']?.toString() ?? 'Unnamed',
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.blue,
                                  size: 30,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _getCurrentLocation,
        tooltip: 'Current Location',
        child:
            _isLocating
                ? const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                )
                : const Icon(Icons.my_location),
      ),
    );
  }
}
