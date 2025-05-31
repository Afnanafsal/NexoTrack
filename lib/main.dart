import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:project47/LocationManager.dart';
import 'package:project47/login.dart';
import 'firebase_options.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => LocationManager(),
      child: MaterialApp(
        title: 'NexoTrack',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: AppInitializer(),
      ),
    );
  }
}

class AppInitializer extends StatefulWidget {
  @override
  _AppInitializerState createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  bool _isInitializing = true;
  String _initializationMessage = 'Initializing app...';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _initializationMessage = 'Setting up location services...';
      });

      final locationManager = Provider.of<LocationManager>(
        context,
        listen: false,
      );
      bool locationInitialized = await locationManager.initialize();

      if (!locationInitialized) {
        _showLocationErrorDialog(locationManager.locationError);
        return;
      }

      setState(() {
        _initializationMessage = 'Getting your location...';
      });

      // Wait a bit for initial location
      await Future.delayed(Duration(seconds: 2));

      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      _showErrorDialog('Initialization failed: $e');
    }
  }

  void _showLocationErrorDialog(String error) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Location Required'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _initializeApp();
              },
              child: Text('Retry'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await Geolocator.openLocationSettings();
                _initializeApp();
              },
              child: Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Error'),
          content: Text(error),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _initializeApp();
              },
              child: Text('Retry'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(_initializationMessage, style: TextStyle(fontSize: 16)),
              SizedBox(height: 10),
              Consumer<LocationManager>(
                builder: (context, locationManager, child) {
                  if (locationManager.currentPosition != null) {
                    return Text(
                      'Location: ${locationManager.formattedLocation}',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    );
                  }
                  return SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      );
    }

    return MainApp();
  }
}

class MainApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<LocationManager>(
      builder: (context, locationManager, child) {
        return Scaffold(
          body: Stack(
            children: [
              LoginPage(), // Your main app content
              // Location status indicator (optional)
              Positioned(
                top: 50,
                right: 10,
                child: Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        locationManager.currentPosition != null
                            ? Colors.green.withOpacity(0.8)
                            : Colors.red.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        locationManager.currentPosition != null
                            ? Icons.location_on
                            : Icons.location_off,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        locationManager.currentPosition != null
                            ? 'GPS Active'
                            : 'GPS Off',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
