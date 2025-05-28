class UserModel {
  final String uid;
  final String email;
  final String name;
  final String role;
  final String? companyName;
  final DateTime createdAt;
  final String officeLocationId;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    this.companyName,
    required this.createdAt,
    required this.officeLocationId,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'role': role,
      'companyName': companyName,
      'createdAt': createdAt.toIso8601String(),
      'officeLocationId': officeLocationId,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'] ?? '',
      email: map['email'] ?? '',
      name: map['name'] ?? '',
      role: map['role'] ?? '',
      companyName: map['companyName'],
      createdAt: DateTime.parse(map['createdAt']),
      officeLocationId: map['officeLocationId'] ?? '',
    );
  }
}
