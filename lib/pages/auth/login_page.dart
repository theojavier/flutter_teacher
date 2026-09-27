import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController idController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;

  bool isLoading = false;
  bool isPasswordVisible = false;

  bool get isFormFilled =>
      idController.text.trim().isNotEmpty &&
      passwordController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    idController.addListener(() => setState(() {}));
    passwordController.addListener(() => setState(() {}));
  }

  Future<void> _login() async {
    final id = idController.text.trim();
    final password = passwordController.text.trim();

    if (id.isEmpty) return _showError("Teacher ID required");
    if (password.isEmpty) return _showError("Password required");

    setState(() => isLoading = true);

    try {
      final query = await db
          .collection('users')
          .where('ID', isEqualTo: id)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _showError('Teacher ID not found');
        return;
      }

      final data = query.docs.first.data();
      final email = data['email'];
      final uid = data['UID'];
      final role = data['role'];

      if (email is! String || email.isEmpty || uid is! String || uid.isEmpty) {
        _showError('Account setup error. Contact admin.');
        return;
      }

      if (role.toString().toLowerCase() != "teacher") {
        _showError("Access denied (not a teacher)");
        return;
      }

      final userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user == null || userCredential.user!.uid != uid) {
        await auth.signOut();
        _showError('Account mismatch. Contact admin.');
        return;
      }

      // Save teacher info locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("userId", userCredential.user!.uid);
      await prefs.setString("teacherId", id);
      await prefs.setString("email", email);
      await prefs.setString("name", data["name"] ?? "");
      await prefs.setString("major", data["major"] ?? "");
      await prefs.setString("yearBlock", data["yearBlock"] ?? "");
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Welcome Teacher!")));

      if (mounted) {
        context.go(
          '/teacher-dashboard',
          extra: {"userId": userCredential.user!.uid},
        );
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Invalid ID or password");
    } catch (e) {
      _showError("Login failed: $e");
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 400, // 👈 prevents weird web stretching
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    "assets/images/Fots.png",
                    width: 200,
                    height: 200,
                  ),
                  const SizedBox(height: 60),

                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      controller: idController,
                      decoration: InputDecoration(
                        hintText: "Teacher ID",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 25),

                  SizedBox(
                    width: double.infinity,
                    child: TextField(
                      controller: passwordController,
                      obscureText: !isPasswordVisible, // 👈 FIXED variable
                      decoration: InputDecoration(
                        hintText: "Password",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        suffixIcon: IconButton(
                          icon: Icon(
                            isPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setState(() {
                              isPasswordVisible = !isPasswordVisible;
                            });
                          },
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  isLoading
                      ? const CircularProgressIndicator()
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isFormFilled ? _login : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isFormFilled
                                  ? Colors.green
                                  : Colors.grey,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text("Login"),
                          ),
                        ),

                  const SizedBox(height: 20),

                  TextButton(
                    onPressed: () => context.go('/forgot'),
                    child: const Text(
                      "Forgot Password?",
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
