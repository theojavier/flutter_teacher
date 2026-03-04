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
      // Verify Teacher ID exists in Firestore
      final query = await db
          .collection("users")
          .where(
            "ID",
            isEqualTo: teacherId,
          ) // <-- Use correct Firestore field name
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _showError("No account found with Teacher ID $teacherId");
        setState(() => isLoading = false);
        return;
      }

      final data = query.docs.first.data();
      final firestoreEmail = data["email"];

      if (firestoreEmail == null || firestoreEmail != email) {
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
        // Wait a moment, then go back to login
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) context.push('/login');
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
      backgroundColor: const Color(0xFF0F2B45),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1F36),
        title: const Text(
          "Forgot Password",
          style: TextStyle(color: Color(0xFFE6F0F8)),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFFE6F0F8)),
          onPressed: () {
            context.push('/login');
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
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFE6F0F8),
                ),
              ),
              const SizedBox(height: 40),

              // Teacher ID Input
              SizedBox(
                width: 340,
                child: TextField(
                  style: TextStyle(color: Colors.white),
                  controller: teacherIdController,
                  decoration: InputDecoration(
                    labelText: "Enter Teacher ID",
                    labelStyle: const TextStyle(color: Colors.white),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white70),
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
                width: 340,
                child: TextField(
                  style: TextStyle(color: Colors.white),
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: "Enter Email",
                    labelStyle: const TextStyle(color: Colors.white),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white70),
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
                      width: 320,
                      child: ElevatedButton(
                        onPressed: _sendResetEmail,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          "Send Reset Link",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
