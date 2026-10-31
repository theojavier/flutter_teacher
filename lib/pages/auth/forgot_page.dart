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
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          // Ambient glow (same family as login)
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
          ],
        );

        return Container(
          color: _artBg,
          constraints: BoxConstraints(minHeight: wide ? 0 : 190),
          child: ClipRect(
            child: Stack(
              children: [
                Center(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(scrollbars: false, overscroll: false),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 64, 16, 24),
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
                              children: [_buildHeaderZone(), _buildFormZone()],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Back button (top-left)
                Positioned(
                  top: 8,
                  left: 12,
                  child: Material(
                    color: Colors.white.withOpacity(0.08),
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: _textColor,
                        size: 22,
                      ),
                      tooltip: "Back to login",
                      onPressed: () => context.go('/login'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
            width: 88,
            height: 88,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
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
              borderRadius: BorderRadius.circular(19),
              child: Container(
                color: _cardColor,
                child: const Icon(
                  Icons.lock_reset,
                  size: 42,
                  color: _accentColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            "Forgot Password?",
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
              "TEACHER ACCOUNT RECOVERY",
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

  Widget _buildFormZone() {
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
                child: const Icon(
                  Icons.mail_outline,
                  size: 16,
                  color: _accentColor,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                "Reset Password",
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
          const SizedBox(height: 12),
          const Text(
            "Enter your Teacher ID and the email linked to your account. "
            "We'll send you a link to set a new password.",
            style: TextStyle(color: _mutedTextColor, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),

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

          // Teacher ID
          TextField(
            controller: teacherIdController,
            style: const TextStyle(color: _textColor),
            cursorColor: _accentColor,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _emailFocus.requestFocus(),
            decoration: _fieldDecoration(
              hint: "Teacher ID",
              icon: Icons.badge_outlined,
            ),
          ),
          const SizedBox(height: 14),

          // Email
          TextField(
            controller: emailController,
            focusNode: _emailFocus,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(color: _textColor),
            cursorColor: _accentColor,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!isLoading && !_emailSent) _sendResetEmail();
            },
            decoration: _fieldDecoration(
              hint: "Email",
              icon: Icons.alternate_email,
            ),
          ),
          const SizedBox(height: 22),

          // Send button
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: (isLoading || _emailSent) ? null : _sendResetEmail,
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
                        Text("Sending..."),
                      ],
                    )
                  : const Text("Send Reset Link"),
            ),
          ),
          const SizedBox(height: 6),

          // Back to login
          TextButton(
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
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.35)),
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

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
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
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      enabledBorder: border(Colors.white.withOpacity(0.08)),
      focusedBorder: border(_accentColor, 1.5),
      border: border(Colors.white.withOpacity(0.08)),
    );
  }
}
