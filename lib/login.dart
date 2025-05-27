import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:project47/home.dart';
import 'package:project47/reset.dart';
import 'package:project47/signup.dart';

  class LoginPage extends StatefulWidget {
    @override
    _LoginPageState createState() => _LoginPageState();
  }

  class _LoginPageState extends State<LoginPage> {
    final _formKey = GlobalKey<FormState>();
    final _emailController = TextEditingController();
    final _passwordController = TextEditingController();
    bool _isLoading = false;

    Future<void> _login() async {
      if (_formKey.currentState!.validate()) {
        setState(() => _isLoading = true);
        try {
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
            Navigator.pushReplacement(
    context,
    MaterialPageRoute(builder: (context) => HomePage()),
  );
          // Success - user is logged in
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Login successful')),
          );
        } on FirebaseAuthException catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.message}')),
          );
        } finally {
          setState(() => _isLoading = false);
        }
      }
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        appBar: AppBar(title: Text('Login')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(labelText: 'Email'),
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
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 20),
                _isLoading
                    ? CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _login,
                        child: Text('Login'),
                      ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => SignupPage()),
                    );
                  },
                  child: Text('Create an account'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => ResetPasswordPage()),
                    );
                  },
                  child: Text('Forgot password?'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    @override
    void dispose() {
      _emailController.dispose();
      _passwordController.dispose();
      super.dispose();
    }
  }