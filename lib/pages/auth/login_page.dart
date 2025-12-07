import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
      final query = await db
          .collection("users")
          .where("ID", isEqualTo: id)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _showError("Teacher ID not found");
        setState(() => isLoading = false);
        return;
      }

      final doc = query.docs.first;
      final data = doc.data();

      final email = data["email"];
      final uid = data["UID"];
      final role = data["role"];

      if (email == null || uid == null) {
        _showError("Account setup error. Contact admin.");
        setState(() => isLoading = false);
        return;
      }

      final userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user == null ||
          userCredential.user!.uid != uid) {
        _showError("Account mismatch. Contact admin.");
        await auth.signOut();
        setState(() => isLoading = false);
        return;
      }

      if (role.toString().toLowerCase() != "teacher") {
        _showError("Access denied (not a teacher)");
        setState(() => isLoading = false);
        return;
      }

      await db.collection("users").doc(doc.id).update({
        "lastLogin": FieldValue.serverTimestamp(),
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("userId", doc.id);
      await prefs.setString("teacherId", data["ID"]);
      await prefs.setString("name", data["name"] ?? "");
      await prefs.setString("email", email);
      await prefs.setString("major", data["major"] ?? "");
      await prefs.setString("gender", data["gender"] ?? "");
      await prefs.setString("civilStatus", data["civilStatus"] ?? "");
      await prefs.setString("nationality", data["nationality"] ?? "");
      await prefs.setString("profileImage", data["profileImage"] ?? "");

      if (data.containsKey("programs")) {
        await prefs.setStringList(
            "programs", List<String>.from(data["programs"]));
      }

      if (data.containsKey("yearBlock")) {
        await prefs.setString("yearBlock", data["yearBlock"]);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Welcome Teacher!")),
      );

      if (mounted) {
        context.go('/teacher-dashboard',
            extra: {"userId": doc.id});
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Invalid ID or Password");
    } catch (e) {
      _showError("Login failed: $e");
    }

    setState(() => isLoading = false);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/images/fots_teacher.png',
                  width: 350,
                  height: 350,
                  fit: BoxFit.cover,
                ),
              ),

              const SizedBox(height: 40),

              // ID field
              SizedBox(
                width: 320,
                child: TextField(
                  controller: idController,
                  decoration: InputDecoration(
                    hintText: "Teacher ID",
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Password field
              SizedBox(
                width: 320,
                child: TextField(
                  controller: passwordController,
                  obscureText: !isPasswordVisible,
                  decoration: InputDecoration(
                    hintText: "Password",
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    suffixIcon: IconButton(
                      icon: Icon(isPasswordVisible
                          ? Icons.visibility
                          : Icons.visibility_off),
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

              // Login
              isLoading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: 340,
                      child: ElevatedButton(
                        onPressed: isFormFilled ? _login : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isFormFilled ? Colors.green : Colors.grey,
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
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
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
