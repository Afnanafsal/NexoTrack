import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:permission_handler/permission_handler.dart';

class ManageStaffPage extends StatefulWidget {
  const ManageStaffPage({super.key});

  @override
  State<ManageStaffPage> createState() => _ManageStaffPageState();
}

class _ManageStaffPageState extends State<ManageStaffPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String? _selectedLocationId;
  String _searchQuery = '';
  bool _isLoading = false;

  static const String _defaultPassword = 'Staff123';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<Map<String, String>> _getLocationsMap() async {
    final snapshot =
        await FirebaseFirestore.instance.collection('officeLocations').get();
    return {for (var doc in snapshot.docs) doc.id: doc['name'] as String};
  }

  Future<void> _createOrUpdateStaff({String? userId}) async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final locationId = _selectedLocationId;

    if (locationId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a location')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (userId != null) {
        // Update existing staff user document
        await FirebaseFirestore.instance.collection('users').doc(userId).update(
          {
            'name': name,
            'email': email,
            'officeLocationId': locationId,
            // you might also want to update 'updatedAt'
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      } else {
        // Check if email already exists in Firebase Authentication
        final existingUserQuery =
            await FirebaseFirestore.instance
                .collection('users')
                .where('email', isEqualTo: email)
                .get();

        if (existingUserQuery.docs.isNotEmpty) {
          throw FirebaseAuthException(code: 'email-already-in-use');
        }

        // Create user in Firebase Authentication
        final userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: email,
              password: _defaultPassword,
            );

        // Create user document in Firestore
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
              'name': name,
              'email': email,
              'role': 'staff',
              'officeLocationId': locationId,
              'createdAt': FieldValue.serverTimestamp(),
            });
      }

      Navigator.pop(context); // Close the bottom sheet or dialog

      // Clear form after success
      _nameController.clear();
      _emailController.clear();
      _selectedLocationId = null;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userId != null
                ? 'Staff updated successfully'
                : 'Staff created successfully with default password: $_defaultPassword',
          ),
        ),
      );
    } on FirebaseAuthException catch (e) {
      String message = 'Failed to create staff user.';
      if (e.code == 'email-already-in-use') {
        message = 'This email is already in use.';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showEditDialog(Map<String, dynamic> data, String userId) {
    _nameController.text = data['name'];
    _emailController.text = data['email'];
    _selectedLocationId = data['officeLocationId'];

    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Edit Staff'),
            content: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator:
                        (val) =>
                            val == null || val.trim().length < 3
                                ? 'Enter a valid name'
                                : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator:
                        (val) =>
                            val == null || !val.contains('@')
                                ? 'Enter valid email'
                                : null,
                  ),
                  const SizedBox(height: 10),
                  FutureBuilder<Map<String, String>>(
                    future: _getLocationsMap(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return const CircularProgressIndicator();
                      final locationMap = snapshot.data!;
                      return DropdownButtonFormField<String>(
                        value: _selectedLocationId,
                        items:
                            locationMap.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            (val) => setState(() => _selectedLocationId = val),
                        decoration: const InputDecoration(
                          labelText: 'Location',
                        ),
                        validator:
                            (val) => val == null ? 'Select a location' : null,
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed:
                    _isLoading
                        ? null
                        : () => _createOrUpdateStaff(userId: userId),
                child:
                    _isLoading
                        ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Text('Update'),
              ),
            ],
          ),
    );
  }

  Future<void> _deleteStaff(String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Delete Staff'),
            content: const Text(
              'Are you sure you want to delete this staff member?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirm ?? false) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .delete();
        // Optionally, also delete from FirebaseAuth (requires admin privileges or backend)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Staff deleted')));
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error deleting staff: $e')));
      }
    }
  }

  Future<void> _exportCSV(
    List<QueryDocumentSnapshot> staffList,
    Map<String, String> locationMap,
  ) async {
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Storage permission denied')),
      );
      return;
    }

    final rows = <List<String>>[
      ['Name', 'Email', 'Location'],
      ...staffList.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return [
          data['name'] ?? '',
          data['email'] ?? '',
          locationMap[data['officeLocationId']] ?? 'Unknown',
        ];
      }),
    ];

    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getExternalStorageDirectory();
    final path = '${dir!.path}/staff_export.csv';
    final file = File(path);
    await file.writeAsString(csv);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Exported to $path')));
  }

  void _showCreateStaffSheet() {
    _nameController.clear();
    _emailController.clear();
    _selectedLocationId = null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (_) => Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              left: 16,
              right: 16,
              top: 20,
            ),
            child: FutureBuilder<Map<String, String>>(
              future: _getLocationsMap(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final locationMap = snapshot.data!;

                return Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(labelText: 'Name'),
                        validator:
                            (val) =>
                                val == null || val.trim().length < 3
                                    ? 'Enter valid name'
                                    : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator:
                            (val) =>
                                val == null || !val.contains('@')
                                    ? 'Enter valid email'
                                    : null,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _selectedLocationId,
                        items:
                            locationMap.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            (val) => setState(() => _selectedLocationId = val),
                        decoration: const InputDecoration(
                          labelText: 'Location',
                        ),
                        validator:
                            (val) => val == null ? 'Select a location' : null,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed:
                            _isLoading ? null : () => _createOrUpdateStaff(),
                        child:
                            _isLoading
                                ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Text(
                                  'Create Staff (Password: Staff123)',
                                ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Staff'),
        actions: [
          IconButton(
            onPressed: () async {
              final locations = await _getLocationsMap();

              final querySnapshot =
                  await FirebaseFirestore.instance
                      .collection('users')
                      .where('role', isEqualTo: 'staff')
                      .get();

              await _exportCSV(querySnapshot.docs, locations);
            },
            icon: const Icon(Icons.download),
            tooltip: 'Export CSV',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateStaffSheet,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search Staff',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged:
                  (val) => setState(() => _searchQuery = val.toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('users')
                      .where('role', isEqualTo: 'staff')
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final docs = snapshot.data!.docs;
                final filtered =
                    docs.where((doc) {
                      final data = doc.data()! as Map<String, dynamic>;
                      final name =
                          (data['name'] ?? '').toString().toLowerCase();
                      final email =
                          (data['email'] ?? '').toString().toLowerCase();
                      return name.contains(_searchQuery) ||
                          email.contains(_searchQuery);
                    }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('No staff found'));
                }

                return FutureBuilder<Map<String, String>>(
                  future: _getLocationsMap(),
                  builder: (context, locationSnapshot) {
                    if (!locationSnapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final locationMap = locationSnapshot.data!;

                    return ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final doc = filtered[index];
                        final data = doc.data()! as Map<String, dynamic>;
                        final locationName =
                            locationMap[data['officeLocationId']] ?? 'Unknown';

                        return ListTile(
                          title: Text(data['name'] ?? 'No Name'),
                          subtitle: Text(
                            '${data['email'] ?? 'No Email'}\nLocation: $locationName',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                                onPressed: () => _showEditDialog(data, doc.id),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () => _deleteStaff(doc.id),
                              ),
                            ],
                          ),
                        );
                      },
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
