import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class ForgotPage extends StatefulWidget {
  const ForgotPage({super.key});

  @override
  State<ForgotPage> createState() => _ForgotPageState();
}

class _ForgotPageState extends State<ForgotPage> {
  // FOTS editorial palette (matches login page)
  static const Color _paper = Color(0xFFF7F8F6);
  static const Color _ink = Color(0xFF111217);
  static const Color _artBg = Color(0xFF101215);
  static const Color _border = Color(0xFFD9DDDA);
  static const Color _muted = Color(0xFF666C6C);
  static const Color _footMuted = Color(0xFF828783);
  static const Color _accentColor = Color(0xFF153CFF);
  static const Color _accentHover = Color(0xFF0F2DB9);
  static const Color _errorBg = Color(0xFFFFEBEE);
  static const Color _errorText = Color(0xFFA42237);
  static const Color _successBg = Color(0xFFE7F9F0);
  static const Color _successText = Color(0xFF087B4F);
  static const double _breakpoint = 790;

  final TextEditingController teacherIdController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();

  bool isLoading = false;
  bool _emailSent = false;
  String _errorMessage = "";
  String _successMessage = "";

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

    setState(() {
      isLoading = true;
      _errorMessage = "";
      _successMessage = "";
    });

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('resetPasswordById');

      // Verify teacher id + email via cloud function
      await callable.call({"id": teacherId, "email": email});

      // If verification passed, send Firebase reset email
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;
      setState(() {
        _emailSent = true;
        _successMessage = "Password reset email sent to $email";
      });

      // short delay then navigate back to login
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) context.go('/login');
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Password reset verification failed: ${e.code}');
      _showError(switch (e.code) {
        'unavailable' || 'deadline-exceeded' =>
          'The password reset service is temporarily unavailable. Please try again.',
        'invalid-argument' => 'Enter a valid Teacher ID and email address.',
        _ => 'Incorrect Teacher ID or Gmail.',
      });
    } on FirebaseAuthException catch (e) {
      debugPrint('Password reset email failed: ${e.code}');
      _showError(switch (e.code) {
        'user-not-found' =>
          'We could not verify those details. Check your Teacher ID and email and try again.',
        'invalid-email' => 'Enter a valid email address and try again.',
        'too-many-requests' =>
          'Too many attempts. Please wait a moment and try again.',
        'network-request-failed' =>
          'Could not connect. Check your internet connection and try again.',
        _ => 'Unable to send a reset email right now. Please try again.',
      });
    } catch (e) {
      debugPrint('Password reset failed: ${e.runtimeType}');
      _showError('Unable to send a reset email right now. Please try again.');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() {
      _errorMessage = msg;
      _successMessage = "";
    });
  }

  @override
  void dispose() {
    teacherIdController.dispose();
    emailController.dispose();
    _emailFocus.dispose();
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
                "RESET.\nRECOVER.\nRETURN.",
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
                "FACE ON THE SCREEN / PASSWORD RECOVERY",
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
          "RECOVERY / 2026",
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
          "03 / PASSWORD RECOVERY",
          style: TextStyle(
            color: _accentColor,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          "Reset password.",
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
          "Enter your Teacher ID and email address. We'll send you a link to create a new password.",
          style: TextStyle(color: _muted, fontSize: 14, height: 1.7),
        ),
        const SizedBox(height: 28),

        // Error / success banner
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: _errorMessage.isNotEmpty
              ? _buildBanner(
                  message: _errorMessage,
                  bgColor: _errorBg,
                  textColor: _errorText,
                  icon: Icons.error_outline,
                )
              : _successMessage.isNotEmpty
              ? _buildBanner(
                  message: _successMessage,
                  bgColor: _successBg,
                  textColor: _successText,
                  icon: Icons.check_circle_outline,
                )
              : const SizedBox(width: double.infinity),
        ),

        if (_errorMessage.isNotEmpty || _successMessage.isNotEmpty)
          const SizedBox(height: 20),

        _fieldLabel("Teacher ID"),
        TextField(
          controller: teacherIdController,
          style: const TextStyle(color: _ink, fontSize: 16),
          cursorColor: _accentColor,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => _emailFocus.requestFocus(),
          decoration: _fieldDecoration(hint: "Enter your Teacher ID"),
        ),
        const SizedBox(height: 17),
        _fieldLabel("Email"),
        TextField(
          controller: emailController,
          focusNode: _emailFocus,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: _ink, fontSize: 16),
          cursorColor: _accentColor,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!isLoading && !_emailSent) _sendResetEmail();
          },
          decoration: _fieldDecoration(hint: "Enter your email"),
        ),
        const SizedBox(height: 25),
        SizedBox(
          width: double.infinity,
          height: 57,
          child: ElevatedButton(
            onPressed: (isLoading || _emailSent) ? null : _sendResetEmail,
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
                      Text("Sending reset link..."),
                    ],
                  )
                : const Text("Send Reset Link"),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => context.go('/login'),
            child: const Text(
              "Back to Login",
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
          "FOTS Teacher Edition · Password reset is sent to your registered email address.",
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

  InputDecoration _fieldDecoration({required String hint}) {
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
      constraints: const BoxConstraints(minHeight: 56),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 15),
      enabledBorder: border(_border),
      focusedBorder: border(_accentColor, 2),
      border: border(_border),
    );
  }

  Widget _buildBanner({
    required String message,
    required Color bgColor,
    required Color textColor,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
