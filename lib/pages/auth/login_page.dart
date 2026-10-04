import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';

class TeacherLoginPage extends StatefulWidget {
  const TeacherLoginPage({super.key});

  @override
  State<TeacherLoginPage> createState() => _TeacherLoginPageState();
}

class _TeacherLoginPageState extends State<TeacherLoginPage> {
  // Shared theme palette (matches admin/student design)
  static const Color _bgColor = Color(0xFF0B1220);
  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);
  static const Color _errorColor = Color(0xFFF87171);

  final TextEditingController teacherIdController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool isLoading = false;
  bool _isPasswordVisible = false;
  String _loginError = "";

  @override
  void initState() {
    super.initState();
    teacherIdController.addListener(_onFieldChanged);
    passwordController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() => setState(() {});

  Future<void> _login() async {
    final teacherId = teacherIdController.text.trim();
    final password = passwordController.text.trim();

    if (teacherId.isEmpty || password.isEmpty) {
      setState(() => _loginError = "Teacher ID and password required");
      return;
    }

    setState(() {
      isLoading = true;
      _loginError = "";
    });

    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');

      final result = await functions
          .httpsCallable('loginWithTeacherId')
          .call({'teacherId': teacherId});

      final data = result.data as Map<String, dynamic>?;

      if (data == null || !data.containsKey('email')) {
        throw Exception("Invalid response from authentication service");
      }

      final email = data['email'] as String?;
      final role = (data['role'] ?? '').toString().toLowerCase();

      if (email == null || email.isEmpty) {
        throw Exception("No email returned for this teacher ID");
      }

      if (role != 'teacher') {
        throw Exception("Access denied (not a teacher)");
      }

      final userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = userCredential.user;
      if (user == null) throw Exception("Authentication failed");

      // Save teacher info locally using SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userId', user.uid);
      await prefs.setString('teacherId', teacherId);
      await prefs.setString('email', email);
      if (data.containsKey('name')) await prefs.setString('name', data['name'] ?? '');
      if (data.containsKey('major')) await prefs.setString('major', data['major'] ?? '');
      if (data.containsKey('yearBlock')) await prefs.setString('yearBlock', data['yearBlock'] ?? '');

      // Optional: update lastLogin
      await _db.collection('users').doc(user.uid).update({'lastLogin': FieldValue.serverTimestamp()});

      if (!mounted) return;
      context.go('/teacher-dashboard', extra: {'userId': user.uid});
    } on FirebaseFunctionsException catch (e) {
      setState(() => _loginError = e.message ?? "Login failed");
    } on FirebaseAuthException catch (e) {
      setState(() => _loginError = e.message ?? "Invalid credentials");
    } catch (e) {
      setState(() => _loginError = e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  void dispose() {
    teacherIdController.removeListener(_onFieldChanged);
    passwordController.removeListener(_onFieldChanged);
    teacherIdController.dispose();
    passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFormFilled = teacherIdController.text.trim().isNotEmpty && passwordController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          // Ambient glow
          Positioned(
            top: -120,
            left: -80,
            child: IgnorePointer(
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      _accentColor.withOpacity(0.18),
                      _accentColor.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildHeaderZone(),
                          _buildFormZone(isFormFilled),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderZone() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_headerColorLight, _headerColor],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 104,
            height: 104,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _accentColor.withOpacity(0.9),
                  _accentColor.withOpacity(0.25),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _accentColor.withOpacity(0.35),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(21),
              child: Container(
                color: _cardColor,
                padding: const EdgeInsets.all(10),
                child: Image.asset("assets/images/fots_teacher.png", fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "Welcome Back",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.25),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              "TEACHER PORTAL",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormZone(bool isFormFilled) {
    return Container(
      width: double.infinity,
      color: _cardColor,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.school_outlined, size: 16, color: _accentColor),
              ),
              const SizedBox(width: 10),
              const Text(
                "Sign In",
                style: TextStyle(
                  color: _textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 1,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Error banner
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _loginError.isEmpty
                ? const SizedBox.shrink()
                : _buildErrorBanner(),
          ),

          // Teacher ID
          TextField(
            controller: teacherIdController,
            style: const TextStyle(color: _textColor),
            cursorColor: _accentColor,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            decoration: _fieldDecoration(
              hint: "Teacher ID",
              icon: Icons.badge_outlined,
            ),
          ),
          const SizedBox(height: 14),

          // Password
          TextField(
            controller: passwordController,
            focusNode: _passwordFocus,
            obscureText: !_isPasswordVisible,
            style: const TextStyle(color: _textColor),
            cursorColor: _accentColor,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!isLoading) _login();
            },
            decoration: _fieldDecoration(
              hint: "Password",
              icon: Icons.lock_outline,
              suffix: IconButton(
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: _mutedTextColor,
                  size: 20,
                ),
                onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
              ),
            ),
          ),
          const SizedBox(height: 22),

          // Login button
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: isLoading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _accentColor.withOpacity(0.6),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: isLoading
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text("Logging in..."),
                      ],
                    )
                  : const Text("Login"),
            ),
          ),
          const SizedBox(height: 6),

          // Forgot password
          TextButton(
            onPressed: () => context.go('/forgot'),
            child: const Text(
              "Forgot Password?",
              style: TextStyle(
                color: _accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _errorColor.withOpacity(0.12),
        border: Border.all(color: _errorColor.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: _errorColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Login Failed",
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _loginError,
                  style: const TextStyle(color: _mutedTextColor, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: _mutedTextColor, fontSize: 14),
      filled: true,
      fillColor: Colors.black.withOpacity(0.22),
      prefixIcon: Icon(icon, color: _accentColor.withOpacity(0.85), size: 20),
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      enabledBorder: border(Colors.white.withOpacity(0.08)),
      focusedBorder: border(_accentColor, 1.5),
      border: border(Colors.white.withOpacity(0.08)),
    );
  }
}
