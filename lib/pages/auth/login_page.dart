import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
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
  static const Color _paper = Color(0xFFF7F8F6);
  static const Color _ink = Color(0xFF111217);
  static const Color _artBg = Color(0xFF101215);
  static const Color _border = Color(0xFFD9DDDA);
  static const Color _muted = Color(0xFF666C6C);
  static const Color _footMuted = Color(0xFF828783);
  static const Color _accentColor = Color(0xFF153CFF);
  static const Color _accentHover = Color(0xFF0F2DB9);
  static const Color _errorText = Color(0xFFA42237);
  static const double _breakpoint = 790;

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
      final functions = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      );

      final result = await functions.httpsCallable('loginWithTeacherId').call({
        'teacherId': teacherId,
      });

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
      if (data.containsKey('name'))
        await prefs.setString('name', data['name'] ?? '');
      if (data.containsKey('major'))
        await prefs.setString('major', data['major'] ?? '');
      if (data.containsKey('yearBlock'))
        await prefs.setString('yearBlock', data['yearBlock'] ?? '');

      // Optional: update lastLogin
      await _db.collection('users').doc(user.uid).update({
        'lastLogin': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      context.go('/teacher-dashboard', extra: {'userId': user.uid});
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Teacher login lookup failed: ${e.code}');
      setState(() {
        _loginError = switch (e.code) {
          'unavailable' || 'deadline-exceeded' =>
            'The sign-in service is temporarily unavailable. Please try again.',
          'permission-denied' =>
            'This account does not have permission to sign in as a teacher.',
          _ => 'Incorrect Teacher ID or Password.',
        };
      });
    } on FirebaseAuthException catch (e) {
      debugPrint('Teacher authentication failed: ${e.code}');
      setState(() {
        _loginError = switch (e.code) {
          'user-not-found' ||
          'wrong-password' ||
          'invalid-credential' => 'Teacher ID or password is incorrect.',
          'too-many-requests' =>
            'Too many sign-in attempts. Please wait a moment and try again.',
          'network-request-failed' =>
            'Could not connect. Check your internet connection and try again.',
          _ => 'Unable to sign in. Please check your details and try again.',
        };
      });
    } catch (e) {
      debugPrint('Teacher login failed: ${e.runtimeType}');
      setState(() {
        _loginError = 'Unable to sign in right now. Please try again.';
      });
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
    return Scaffold(
      backgroundColor: _paper,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > _breakpoint;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 11, child: _buildArtPanel(wide: true)),
                Expanded(
                  flex: 10,
                  child: _buildFormPanel(wide: true, constraints: constraints),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildArtPanel(wide: false),
                _buildFormPanel(wide: false, constraints: constraints),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildArtPanel({required bool wide}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.of(context).size;
        final titleSize = wide
            ? (screen.width * 0.08).clamp(56.0, 120.0)
            : 56.0;
        final glowSize = wide ? 500.0 : 330.0;
        final content = Column(
          mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBrandRow(),
            if (!wide) const SizedBox(height: 29),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                "TEACH.\nCREATE.\nASSESS.",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: titleSize,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.085 * titleSize,
                  height: 0.91,
                ),
              ),
            ),
            if (wide)
              const Text(
                "FACE ON THE SCREEN / FACULTY WORKSPACE",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  letterSpacing: 1.8,
                ),
              ),
          ],
        );

        return Container(
          color: _artBg,
          constraints: BoxConstraints(minHeight: wide ? 0 : 190),
          child: ClipRect(
            child: Stack(
              children: [
                Positioned(
                  left: wide
                      ? constraints.maxWidth * 0.06
                      : constraints.maxWidth * 0.45,
                  top: wide ? screen.height * 0.16 : -130,
                  child: IgnorePointer(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Opacity(
                        opacity: 0.78,
                        child: Transform.rotate(
                          angle: -35 * math.pi / 180,
                          child: Container(
                            width: glowSize,
                            height: glowSize,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Color(0xFF2CD281),
                                  Color(0xFF153CFF),
                                  Color(0xFF064A33),
                                  Color(0x00064A33),
                                ],
                                stops: [0.0, 0.43, 0.60, 0.73],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: wide
                      ? const EdgeInsets.all(30)
                      : const EdgeInsets.fromLTRB(22, 19, 22, 19),
                  child: content,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBrandRow() {
    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Image.asset(
            'assets/images/teacher-removebg-preview.png',
            width: 32,
            height: 32,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          "FOTS",
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -1,
          ),
        ),
        const Spacer(),
        const Text(
          "TEACHER / 2026",
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildFormPanel({
    required bool wide,
    required BoxConstraints constraints,
  }) {
    final form = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: wide ? 440 : double.infinity),
      child: _buildForm(wide: wide),
    );

    if (!wide) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 30, 22, 48),
        child: form,
      );
    }

    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth * 0.08,
              vertical: 36,
            ),
            child: form,
          ),
        ),
      ),
    );
  }

  Widget _buildForm({required bool wide}) {
    final headingSize = wide
        ? (MediaQuery.of(context).size.width * 0.04).clamp(32.0, 49.0)
        : 37.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          "02 / FACULTY ACCESS",
          style: TextStyle(
            color: _accentColor,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          "Welcome back.",
          style: TextStyle(
            color: _ink,
            fontSize: headingSize,
            fontWeight: FontWeight.w800,
            height: 1.06,
            letterSpacing: -0.052 * headingSize,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          "Sign in to access exam creation, student monitoring, reports, and approval requests.",
          style: TextStyle(color: _muted, fontSize: 14, height: 1.7),
        ),
        const SizedBox(height: 28),
        _fieldLabel("Teacher ID"),
        TextField(
          controller: teacherIdController,
          style: const TextStyle(color: _ink, fontSize: 16),
          cursorColor: _accentColor,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username],
          onSubmitted: (_) => _passwordFocus.requestFocus(),
          decoration: _fieldDecoration(hint: "Enter your Teacher ID"),
        ),
        const SizedBox(height: 17),
        _fieldLabel("Password"),
        TextField(
          controller: passwordController,
          focusNode: _passwordFocus,
          obscureText: !_isPasswordVisible,
          style: const TextStyle(color: _ink, fontSize: 16),
          cursorColor: _accentColor,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) {
            if (!isLoading) _login();
          },
          decoration: _fieldDecoration(
            hint: "Enter your password",
            suffix: IconButton(
              tooltip: _isPasswordVisible ? "Hide password" : "Show password",
              icon: Icon(
                _isPasswordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _footMuted,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _isPasswordVisible = !_isPasswordVisible),
            ),
          ),
        ),
        const SizedBox(height: 25),
        SizedBox(
          width: double.infinity,
          height: 57,
          child: ElevatedButton(
            onPressed: isLoading ? null : _login,
            style: ButtonStyle(
              elevation: const WidgetStatePropertyAll(0),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              foregroundColor: const WidgetStatePropertyAll(Colors.white),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.disabled)) {
                  return _accentColor.withOpacity(0.6);
                }
                if (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.pressed)) {
                  return _accentHover;
                }
                return _accentColor;
              }),
              textStyle: const WidgetStatePropertyAll(
                TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
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
                      Text("Signing in..."),
                    ],
                  )
                : const Text("Sign in to Teacher Portal"),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 20),
            margin: const EdgeInsets.only(top: 12),
            child: _loginError.isEmpty
                ? const SizedBox.shrink()
                : Semantics(
                    liveRegion: true,
                    child: Text(
                      _loginError,
                      style: const TextStyle(color: _errorText, fontSize: 12),
                    ),
                  ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => context.go('/forgot'),
            child: const Text(
              "Forgot Password?",
              style: TextStyle(
                color: _accentColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "FOTS Teacher Edition · Designed for web and future Flutter WebView use.",
          style: TextStyle(color: _footMuted, fontSize: 11, height: 1.6),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: _ink,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({required String hint, Widget? suffix}) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF9AA09B), fontSize: 16),
      filled: true,
      fillColor: Colors.white,
      suffixIcon: suffix,
      constraints: const BoxConstraints(minHeight: 56),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 15),
      enabledBorder: border(_border),
      focusedBorder: border(_accentColor, 2),
      border: border(_border),
    );
  }
}
