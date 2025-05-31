import 'package:Nexotrack/LocationManager.dart';
import 'package:Nexotrack/login.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _progressController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _progressAnimation;
  bool _isInitializingLocation = true;
  String _locationStatus = "Setting up location services...";
  bool _locationInitialized = false;

  @override
  void initState() {
    super.initState();

    // Setup animations
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    // Setup progress controller for the entire splash duration
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 10000), // Total splash duration
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(0.0, 0.8, curve: Curves.easeIn),
      ),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.elasticOut));

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );

    // Start animations
    _controller.forward();
    _progressController.forward();

    // Initialize location after animations start
    _initializeLocation();
  }

  Future<void> _initializeLocation() async {
    try {
      final locationManager = Provider.of<LocationManager>(
        context,
        listen: false,
      );

      setState(() {
        _locationStatus = "Requesting location permissions...";
      });

      bool locationInitialized = await locationManager.initialize();

      if (!locationInitialized) {
        setState(() {
          _locationStatus = "Location access denied";
          _isInitializingLocation = false;
        });
        _showLocationErrorDialog(locationManager.locationError);
        return;
      }

      setState(() {
        _locationStatus = "Getting your location...";
      });

      await Future.delayed(Duration(milliseconds: 500));

      setState(() {
        _locationInitialized = true;
        _isInitializingLocation = false;
        _locationStatus = "Location initialized";
      });

      Future.delayed(const Duration(milliseconds: 200), () {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder:
                (context, animation, secondaryAnimation) => const LoginPage(),
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              var curve = Curves.easeInOut;
              var curveTween = CurveTween(curve: curve);

              var fadeAnimation = Tween<double>(
                begin: 0.0,
                end: 1.0,
              ).animate(animation.drive(curveTween));

              var slideAnimation = Tween<Offset>(
                begin: const Offset(0.0, 0.5),
                end: Offset.zero,
              ).animate(animation.drive(curveTween));

              return FadeTransition(
                opacity: fadeAnimation,
                child: SlideTransition(position: slideAnimation, child: child),
              );
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      });
    } catch (e) {
      setState(() {
        _locationStatus = "Error: ${e.toString()}";
        _isInitializingLocation = false;
      });
      _showErrorDialog("Location initialization failed: $e");
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
                setState(() {
                  _isInitializingLocation = true;
                });
                _initializeLocation();
              },
              child: Text('Retry'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await Geolocator.openLocationSettings();
                setState(() {
                  _isInitializingLocation = true;
                });
                _initializeLocation();
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
                setState(() {
                  _isInitializingLocation = true;
                });
                _initializeLocation();
              },
              child: Text('Retry'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.indigo.shade800,
      body: Stack(
        children: [
          // Logo with animation
          Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset('assets/logo.png', width: 200, height: 200),
                        SizedBox(height: 40),

                        // App name
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Overall Progress Indicator (from start to snackbar)
          Positioned(
            bottom: 200,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _progressController,
              builder: (context, child) {
                return AnimatedOpacity(
                  opacity: _controller.value > 0.5 ? 1.0 : 0.0,
                  duration: Duration(milliseconds: 500),
                  child: Column(
                    children: [
                      Container(
                        margin: EdgeInsets.symmetric(horizontal: 60),
                        height: 6,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: _progressAnimation.value,
                            backgroundColor: Colors.white.withOpacity(0.3),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                            minHeight: 6,
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '${(_progressAnimation.value * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Location status UI
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _controller.value > 0.7 ? 1.0 : 0.0,
              duration: Duration(milliseconds: 500),
              child: Column(
                children: [
                  // Location status card
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 40),
                    padding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _isInitializingLocation
                                ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.indigo,
                                    ),
                                  ),
                                )
                                : Icon(
                                  _locationInitialized
                                      ? Icons.location_on
                                      : Icons.location_off,
                                  color:
                                      _locationInitialized
                                          ? Colors.green
                                          : Colors.red,
                                ),
                            SizedBox(width: 10),
                            Text(
                              _locationStatus,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.indigo.shade800,
                              ),
                            ),
                          ],
                        ),
                        if (_locationInitialized) ...[
                          SizedBox(height: 10),
                          Consumer<LocationManager>(
                            builder: (context, locationManager, child) {
                              return locationManager.currentPosition != null
                                  ? Text(
                                    locationManager.formattedLocation,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                    ),
                                    textAlign: TextAlign.center,
                                  )
                                  : SizedBox.shrink();
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
