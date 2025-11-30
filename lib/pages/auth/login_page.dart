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
  bool get isFormFilled =>
      idController.text.trim().isNotEmpty &&
      passwordController.text.trim().isNotEmpty;

  bool isLoading = false;
  bool _isPasswordVisible = false;
  StreamSubscription? _examListener;
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
      // Fetch teacher profile by ID
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
        _showError("Account setup error. Please contact admin.");
        setState(() => isLoading = false);
        return;
      }

      // Authenticate with Firebase
      final userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user == null || userCredential.user!.uid != uid) {
        _showError("Account mismatch. Please contact admin.");
        await auth.signOut();
        setState(() => isLoading = false);
        return;
      }

      // Proceed only if teacher role
      if (role.toString().toLowerCase() == "teacher") {
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
            "programs",
            List<String>.from(data["programs"]),
          );
        }

        if (data.containsKey("yearBlock")) {
          await prefs.setString("yearBlock", data["yearBlock"]);
        }

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Welcome Teacher!")));

        // Start optional exam listener (if needed)
        if (data["programs"] != null && data["yearBlock"] != null) {
          startExamListener(
            doc.id,
            data["programs"][0], // first program
            data["yearBlock"],
          );
        }

        if (mounted) {
  await prefs.reload(); // ensure SharedPreferences is updated
  context.go('/teacher-dashboard', extra: {'userId': doc.id});
}
      } else {
        _showError("Access denied (not a Teacher account)");
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? "Invalid ID or Password");
    } catch (e) {
      _showError("Login failed: $e");
    }

    setState(() => isLoading = false);
  }

  // Real-time exam notifications (optional)
  void startExamListener(String userId, String program, String yearBlock) {
    _examListener = db
        .collection('exams')
        .where('program', isEqualTo: program)
        .where('yearBlock', isEqualTo: yearBlock)
        .snapshots()
        .listen((snapshot) async {
          final userRef = db.collection('users').doc(userId);

          for (var examDoc in snapshot.docs) {
            final examId = examDoc.id;
            final notifRef = userRef.collection('notifications').doc(examId);

            final notifSnap = await notifRef.get();
            if (!notifSnap.exists) {
              await notifRef.set({
                'viewed': false,
                'subject': examDoc['subject'],
                'createdAt': examDoc['createdAt'],
              });
              debugPrint("Created notif for $userId -> exam $examId");
            }
          }
        });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _examListener?.cancel();
    idController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo/Image
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/images/fots_teacher.png',
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    // Fallback to icon if image not found
                    return Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.school,
                        size: 100,
                        color: Colors.blue[800],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 60),

              // Teacher ID Field
              SizedBox(
                width: 320,
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

              // Password Field
              SizedBox(
                width: 320,
                child: TextField(
                  controller: passwordController,
                  obscureText: !_isPasswordVisible,
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
                        _isPasswordVisible
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _isPasswordVisible = !_isPasswordVisible;
                        });
                      },
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Login Button
              isLoading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                      width: 340,
                      child: ElevatedButton(
                        onPressed: isFormFilled ? _login : null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: isFormFilled
                              ? Colors.green
                              : Colors.grey,
                        ),
                        child: const Text("Login"),
                      ),
                    ),

              const SizedBox(height: 20),

              // Forgot Password
              TextButton(
                onPressed: () {
                  context.go('/forgot');
                },
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
    );
  }
}
