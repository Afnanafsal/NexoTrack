import 'package:flutter/material.dart';
import 'package:project47/location_picker.dart';
import 'manage_locations.dart';
import 'manage_staff.dart';
import 'live_location.dart';
import 'movement_history.dart';
import '../login.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Dashboard'),
        backgroundColor: Colors.red,
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: [
            _buildFeatureCard(
              context,
              'Manage Office Locations',
              Icons.location_city,
              Colors.blue,
              const LocationPickerPage(),
            ),
            _buildFeatureCard(
              context,
              'Manage Staff Accounts',
              Icons.people,
              Colors.green,
              const ManageStaffPage(),
            ),
            _buildFeatureCard(
              context,
              'Live Staff Locations',
              Icons.gps_fixed,
              Colors.orange,
              const LiveLocationPage(),
            ),
            _buildFeatureCard(
              context,
              'Movement History',
              Icons.history,
              Colors.purple,
              const MovementHistoryPage(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    Widget page,
  ) {
    return Card(
      child: InkWell(
        onTap:
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => page),
            ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: color),
              SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
