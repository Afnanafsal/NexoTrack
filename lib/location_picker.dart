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

class _LocationPickerPageState extends State<LocationPickerPage>
    with SingleTickerProviderStateMixin {
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
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
    _fetchExistingLocations();
    _requestLocationPermission();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    _nameController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      _getCurrentLocation();
    } else {
      _showSnackbar('Location permission denied', Colors.red);
    }
  }

  void _showSnackbar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(16),
        duration: Duration(seconds: 3),
      ),
    );
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
      _showSnackbar('Current location found', Colors.green);
    } catch (e) {
      _showSnackbar('Error getting location: $e', Colors.red);
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
      _showSnackbar('Error loading locations: $e', Colors.red);
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
      _showSnackbar('Error searching location: $e', Colors.red);
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
        _showSnackbar('Invalid latitude or longitude', Colors.red);
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
      _showSnackbar('Error processing coordinates: $e', Colors.red);
    }
  }

  Future<void> _saveToFirestore() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || _selectedLocation == null) return;

      final customName = _nameController.text.trim();
      if (customName.isEmpty) {
        _showSnackbar('Please enter a name for the location', Colors.red);
        return;
      }

      final userDoc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
      final role = userDoc.data()?['role']?.toString();

      if (role != 'admin') {
        _showSnackbar('Only admins can save office locations', Colors.red);
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
      _showSnackbar('Office location saved successfully!', Colors.green);
    } catch (e) {
      _showSnackbar('Error saving location: $e', Colors.red);
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    VoidCallback? onTap,
    bool readOnly = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(icon, color: Colors.indigo.shade700),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(color: Colors.indigo.shade700, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildSelectedLocationCard() {
    if (_selectedAddress == null) return SizedBox.shrink();

    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 15,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.location_on, color: Colors.green.shade700),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selected Location',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _selectedAddress!,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          _buildTextField(
            controller: _nameController,
            label: 'Enter a name for this location',
            icon: Icons.label_outline,
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _saveToFirestore,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade700,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.save),
                  SizedBox(width: 8),
                  Text(
                    'Save Location',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinateInput() {
    if (!_showLatLngInput) return SizedBox.shrink();

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pin_drop, color: Colors.indigo.shade700),
              SizedBox(width: 8),
              Text(
                'Manual Coordinates',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildTextField(
                  controller: _latController,
                  label: 'Latitude',
                  icon: Icons.my_location,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: _buildTextField(
                  controller: _lngController,
                  label: 'Longitude',
                  icon: Icons.location_searching,
                  keyboardType: TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _handleLatLngInput,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade700,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, size: 20),
                  SizedBox(width: 8),
                  Text('Find Location'),
                ],
              ),
            ),
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
        title: const Text(
          'Pick Office Location',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo.shade800,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          Container(
            margin: EdgeInsets.only(right: 8),
            child: IconButton(
              icon: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color:
                      _showLatLngInput
                          ? Colors.white.withOpacity(0.3)
                          : Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.pin_drop, color: Colors.white, size: 20),
              ),
              tooltip: 'Toggle Manual Coordinates',
              onPressed: () {
                setState(() {
                  _showLatLngInput = !_showLatLngInput;
                });
              },
            ),
          ),
          Container(
            margin: EdgeInsets.only(right: 16),
            child: IconButton(
              icon: Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child:
                    _isLocating
                        ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                        : Icon(
                          Icons.my_location,
                          color: Colors.white,
                          size: 20,
                        ),
              ),
              tooltip: 'Get Current Location',
              onPressed: _getCurrentLocation,
            ),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          children: [
            // Search Section
            Container(
              padding: EdgeInsets.all(16),
              color: Colors.white,
              child: TypeAheadField<String>(
                controller: _searchController,
                suggestionsCallback: _getSuggestions,
                builder: (context, controller, focusNode) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: 'Search for a location...',
                      hintStyle: TextStyle(color: Colors.grey.shade500),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.blue.shade700,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide(
                          color: Colors.blue.shade700,
                          width: 2,
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                  );
                },
                itemBuilder:
                    (context, suggestion) => Container(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            color: Colors.grey.shade600,
                            size: 20,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              suggestion,
                              style: TextStyle(fontSize: 14),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                onSelected: (value) {
                  _searchController.text = value;
                  _handleSearchSelection(value);
                },
                emptyBuilder:
                    (context) => Container(
                      padding: EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.search_off, color: Colors.grey.shade400),
                          SizedBox(width: 12),
                          Text(
                            'No results found',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
              ),
            ),

            // Coordinate Input
            _buildCoordinateInput(),

            // Selected Location Card
            _buildSelectedLocationCard(),

            // Map
            Expanded(
              child: Container(
                margin: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      blurRadius: 15,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
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
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                ),
                                child: Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 20,
                                ),
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
                                      message:
                                          loc['name']?.toString() ?? 'Unnamed',
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.indigo.shade800,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 2,
                                          ),
                                        ),
                                        child: Icon(
                                          Icons.business,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _getCurrentLocation,
        backgroundColor: Colors.indigo.shade800,
        foregroundColor: Colors.white,
        elevation: 4,
        icon:
            _isLocating
                ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
                : Icon(Icons.my_location),
        label: Text(_isLocating ? 'Locating...' : 'My Location'),
      ),
    );
  }
}
