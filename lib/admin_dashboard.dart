import 'package:flutter/material.dart';
import 'package:project47/location_picker.dart';
import 'package:project47/Punching_history.dart';
import 'manage_locations.dart';
import 'manage_staff.dart';
import 'live_location.dart';
import '../login.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  _AdminDashboardState createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  String _adminName = 'Admin';
  int _staffCount = 0;
  int _locationCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchDashboardData();
  }

  void _loadUserData() {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null && user.displayName != null) {
      setState(() {
        _adminName = user.displayName!.split(' ')[0];
      });
    }
  }

  Future<void> _fetchDashboardData() async {
    try {
      // Get staff count
      final staffSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'staff')
          .get();
      
      // Get location count
      final locationsSnapshot = await FirebaseFirestore.instance
          .collection('officeLocations')
          .get();
      
      setState(() {
        _staffCount = staffSnapshot.docs.length;
        _locationCount = locationsSnapshot.docs.length;
        _isLoading = false;
      });
    } catch (e) {
      print('Error fetching dashboard data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _logout(BuildContext context) async {
    bool? confirmLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.logout, color: Colors.red),
              SizedBox(width: 10),
              Text('Confirm Logout'),
            ],
          ),
          content: Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text('Logout'),
            ),
          ],
        );
      },
    );

    if (confirmLogout == true) {
      await FirebaseAuth.instance.signOut();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => LoginPage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: _isLoading 
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: BouncingScrollPhysics(),
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildWelcomeSection(),
                        SizedBox(height: 20),
                        _buildStatsSection(),
                        SizedBox(height: 20),
                        _buildFeatureCardsSection(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.indigo[800],
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Admin Dashboard',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Manage your team efficiently',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: () => _logout(context),
            icon: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.logout_rounded, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeSection() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo[400]!, Colors.indigo[700]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white.withOpacity(0.2),
            radius: 25,
            child: Icon(
              Icons.person,
              size: 30,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
                Text(
                  _adminName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total Staff',
                '$_staffCount',
                Icons.people_alt_rounded,
                Colors.teal,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Locations',
                '$_locationCount',
                Icons.location_on_rounded,
                Colors.amber[700]!,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCardsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Management Tools',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        GridView.count(
          physics: NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 1.05,
          children: [
            _buildFeatureCard(
              'Office\nLocations',
              Icons.location_city_rounded,
              Colors.blue[700]!,
              () => Navigator.push(
                context, 
                MaterialPageRoute(builder: (_) => const LocationPickerPage())
              ),
            ),
            _buildFeatureCard(
              'Staff\nManagement',
              Icons.people_rounded,
              Colors.green[700]!,
              () => Navigator.push(
                context, 
                MaterialPageRoute(builder: (_) => const ManageStaffPage())
              ),
            ),
            _buildFeatureCard(
              'Live\nTracking',
              Icons.gps_fixed_rounded,
              Colors.orange[700]!,
              () => Navigator.push(
                context, 
                MaterialPageRoute(builder: (_) => const LiveLocationPage())
              ),
            ),
            _buildFeatureCard(
              'Attendance\nHistory',
              Icons.history_rounded,
              Colors.purple[700]!,
              () => Navigator.push(
                context, 
                MaterialPageRoute(builder: (_) => const PunchingHistoryPage())
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFeatureCard(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
