import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class ForgotPage extends StatefulWidget {
  const ForgotPage({super.key});

  @override
  _ForgotPageState createState() => _ForgotPageState();
}

class _ForgotPageState extends State<ForgotPage> {
  final TextEditingController teacherIdController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;

  bool isLoading = false;

  Future<void> _sendResetEmail() async {
    final teacherId = teacherIdController.text.trim();
    final email = emailController.text.trim();

    if (teacherId.isEmpty) {
      _showError("Teacher ID required");
      return;
    }
    if (email.isEmpty) {
      _showError("Email required");
      return;
    }

    setState(() => isLoading = true);

    try {
      // Verify Teacher ID exists
      final query = await db
          .collection("users")
          .where("teacherId", isEqualTo: teacherId)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _showError("No account found with Teacher ID $teacherId");
        setState(() => isLoading = false);
        return;
      }

      final data = query.docs.first.data();
      final firestoreEmail = data["email"];

      // Check if email matches Firestore record
      if (firestoreEmail != email) {
        _showError("Email does not match this Teacher ID");
        setState(() => isLoading = false);
        return;
      }

      // Send RESET EMAIL
      await auth.sendPasswordResetEmail(email: email);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Password reset email sent to $email")),
        );
        // Wait a moment for the user to see the confirmation, then go back to login
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) context.go('/login');
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Error sending reset email");
    } catch (e) {
      _showError("Error: $e");
    }

    setState(() => isLoading = false);
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Forgot Password"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            context.go('/login');
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              const Text(
                "Forgot Password?",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),

              // Teacher ID Input
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                child: TextField(
                  controller: teacherIdController,
                  decoration: InputDecoration(
                    labelText: "Enter Teacher ID",
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

              const SizedBox(height: 20),

              // Email Input
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.8,
                child: TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: "Enter Email",
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

              const SizedBox(height: 20),

              // Reset Button
              isLoading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: MediaQuery.of(context).size.width * 0.8,
                      child: ElevatedButton(
                        onPressed: _sendResetEmail,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text("Send Reset Link"),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
