import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:project47/FirestoreService.dart';
import 'package:project47/UserModel.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  _SignupPageState createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _roleCodeController = TextEditingController();
  final _companyController = TextEditingController();
  bool _isLoading = false;
  String? _selectedRole;

  Future<void> _signup() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      try {
        // Validate role code
        String? role = FirestoreService.validateRoleCode(
          _roleCodeController.text.trim(),
        );
        if (role == null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Invalid role code')));
          setState(() => _isLoading = false);
          return;
        }

        // Create user with Firebase Auth
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: _emailController.text.trim(),
              password: _passwordController.text.trim(),
            );

        // Create user model
        UserModel newUser = UserModel(
          uid: userCredential.user!.uid,
          email: _emailController.text.trim(),
          name: _nameController.text.trim(),
          role: role,
          companyName: role == 'admin' ? _companyController.text.trim() : null,
          createdAt: DateTime.now(),
          officeLocationId: '',
        );

        // Save to Firestore
        await FirestoreService.saveUserData(newUser);

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Account created successfully')));
        Navigator.pop(context);
      } on FirebaseAuthException catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  void _checkRoleCode(String code) {
    String? role = FirestoreService.validateRoleCode(code);
    setState(() {
      _selectedRole = role;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sign Up'), backgroundColor: Colors.green),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                SizedBox(height: 20),
                Icon(Icons.person_add, size: 80, color: Colors.green),
                SizedBox(height: 30),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 20),
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your email';
                    }
                    if (!value.contains('@')) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 20),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 20),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (value) {
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 20),
                TextFormField(
                  controller: _roleCodeController,
                  decoration: InputDecoration(
                    labelText: 'Role Code',
                    prefixIcon: Icon(Icons.security),
                    border: OutlineInputBorder(),
                    helperText:
                        'Enter ADMIN456 for Admin or STAFF123 for Staff',
                  ),
                  onChanged: _checkRoleCode,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter role code';
                    }
                    if (FirestoreService.validateRoleCode(value) == null) {
                      return 'Invalid role code';
                    }
                    return null;
                  },
                ),
                if (_selectedRole != null)
                  Container(
                    margin: EdgeInsets.only(top: 10),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color:
                          _selectedRole == 'admin'
                              ? Colors.orange.shade100
                              : Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Role: ${_selectedRole!.toUpperCase()}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color:
                            _selectedRole == 'admin'
                                ? Colors.orange.shade800
                                : Colors.blue.shade800,
                      ),
                    ),
                  ),
                if (_selectedRole == 'admin') ...[
                  SizedBox(height: 20),
                  TextFormField(
                    controller: _companyController,
                    decoration: InputDecoration(
                      labelText: 'Company Name',
                      prefixIcon: Icon(Icons.business),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (_selectedRole == 'admin' &&
                          (value == null || value.isEmpty)) {
                        return 'Please enter company name';
                      }
                      return null;
                    },
                  ),
                ],
                SizedBox(height: 30),
                _isLoading
                    ? CircularProgressIndicator()
                    : SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _signup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: Text('Sign Up'),
                      ),
                    ),
                SizedBox(height: 20),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Already have an account? Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _roleCodeController.dispose();
    _companyController.dispose();
    super.dispose();
  }
}
