import 'package:Nexotrack/UserModel.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FirestoreService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Save user data to Firestore
  static Future<void> saveUserData(UserModel user) async {
    try {
      await _db.collection('users').doc(user.uid).set(user.toMap());
    } catch (e) {
      throw Exception('Failed to save user data: $e');
    }
  }

  // Get user data from Firestore

  static Future<UserModel?> getUserData(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        return UserModel.fromMap(doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get user data: $e');
    }
  }

  // Check if role code is valid
  static String? validateRoleCode(String code) {
    if (code == 'ADMIN456') {
      return 'admin';
    } else if (code == 'STAFF123') {
      return 'staff';
    }
    return null;
  }

  // Add to FirestoreService class
  static Future<void> addOfficeLocation(
    String name,
    double lat,
    double lng,
  ) async {
    try {
      await _db.collection('officeLocations').add({
        'name': name,
        'location': GeoPoint(lat, lng),
        'createdAt': DateTime.now(),
      });
    } catch (e) {
      throw Exception('Failed to add office: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> getOfficeLocations() async {
    try {
      QuerySnapshot snapshot = await _db.collection('officeLocations').get();
      return snapshot.docs.map((doc) {
        var data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'name': data['name'],
          'lat': (data['location'] as GeoPoint).latitude,
          'lng': (data['location'] as GeoPoint).longitude,
        };
      }).toList();
    } catch (e) {
      throw Exception('Failed to get offices: $e');
    }
  }

  static Future<void> createUser(UserModel user) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .set(user.toMap());
  }

  static Future<void> createStaffAccount({
    required String name,
    required String email,
    required String password,
    required String officeId,
  }) async {
    try {
      // 1. Create auth user
      UserCredential credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      // 2. Save to Firestore
      await _db.collection('users').doc(credential.user!.uid).set({
        'uid': credential.user!.uid,
        'email': email,
        'name': name,
        'role': 'staff',
        'officeId': officeId,
        'createdAt': DateTime.now(),
      });
    } catch (e) {
      throw Exception('Failed to create staff: $e');
    }
  }
}
