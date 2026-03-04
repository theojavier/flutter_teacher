import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
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
      final auth = FirebaseAuth.instance;
      final functions = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      );

      // Call the Cloud Function
      final result = await functions.httpsCallable('loginWithTeacherId').call({
        'teacherId': id,
        'password': password,
      });

      final data = result.data;
      final token = data['token'];
      final role = data['role'];

      if (role.toString().toLowerCase() != "teacher") {
        _showError("Access denied (not a teacher)");
        setState(() => isLoading = false);
        return;
      }

      // Sign in with the custom token
      final userCredential = await auth.signInWithCustomToken(token);

      if (userCredential.user == null) {
        _showError("Authentication failed");
        setState(() => isLoading = false);
        return;
      }

      // Save teacher info locally
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("userId", userCredential.user!.uid);
      await prefs.setString("teacherId", id);
      await prefs.setString("email", data["email"]);
      await prefs.setString("name", data["name"] ?? "");
      await prefs.setString("major", data["major"] ?? "");
      await prefs.setString("yearBlock", data["yearBlock"] ?? "");

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Welcome Teacher!")));

      if (mounted) {
        context.go(
          '/teacher-dashboard',
          extra: {"userId": userCredential.user!.uid},
        );
      }
    } on FirebaseFunctionsException catch (e) {
      _showError(e.message ?? "Login failed");
    } catch (e) {
      _showError("Login failed: $e");
    }

    setState(() => isLoading = false);
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
              "assets/images/fots_teacher.png",
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
                        backgroundColor:
                            isFormFilled ? Colors.green : Colors.grey,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
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
