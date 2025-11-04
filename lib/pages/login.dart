import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For input formatters

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _otpController = TextEditingController();
  bool _loading = false;
  bool _rememberMe = false;
  bool _otpSent = true; // Flag to show OTP field after sending
  String? _generatedOtp; // Simulated OTP for demo
  int _otpExpirySeconds = 300; // 5 minutes expiry (demo)

  // Simple email regex for validation
  final _emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');

  void _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    // Simulate API call to send OTP (replace with real service like Firebase Auth)
    await Future.delayed(const Duration(seconds: 2)); // Simulate delay

    if (!mounted) return;

    // Generate a demo OTP (in real app, this comes from backend)
    _generatedOtp = '123456'; // For demo; show in dialog

    setState(() {
      _loading = false;
      _otpSent = true;
    });

    // Show OTP in a dialog (for demo purposes; in production, send via email/SMS)
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('OTP Sent'),
        content: Text('Your OTP is: $_generatedOtp\n(Valid for 5 minutes)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    // Start OTP expiry timer (optional demo feature)
    _startOtpTimer();
  }

  void _verifyOtp() async {
    if (_otpController.text.trim() != _generatedOtp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid OTP. Please try again.')),
      );
      return;
    }

    setState(() => _loading = true);

    // Simulate verification delay
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    // Success: Navigate to dashboard
    Navigator.of(context).pushReplacementNamed('/dashboard');

    setState(() => _loading = false);
  }

  void _startOtpTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _otpExpirySeconds > 0) {
        setState(() => _otpExpirySeconds--);
        _startOtpTimer(); // Recurse
      } else if (mounted) {
        // OTP expired
        setState(() {
          _otpSent = false;
          _generatedOtp = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('OTP expired. Please request a new one.'),
          ),
        );
      }
    });
  }

  void _forgotPassword() {
    // Navigate to Forgot Password page (assuming you have it)
    Navigator.of(context).pushNamed('/forgot-password');
  }

  @override
  void dispose() {
    _idController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Faculty Login'),
        backgroundColor: theme.primaryColor,
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 🟦 Centered Title
                      Text(
                        'Faculty Management',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Faculty / Teacher Login',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // 🟩 Email Field
                      TextFormField(
                        controller: _idController,
                        decoration: const InputDecoration(
                          labelText: 'Faculty ID or Email',
                          hintText: 'e.g., teacher@school.com',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your school email';
                          }
                          if (!_emailRegex.hasMatch(value)) {
                            return 'Please enter a valid email address';
                          }
                          return null;
                        },
                      ),

                      // 🟨 OTP Field (only visible after sending)
                      if (_otpSent) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _otpController,
                          decoration: InputDecoration(
                            labelText: 'Enter OTP',
                            hintText: '6-digit code',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.lock),
                            suffixText:
                                'Expires in ${_otpExpirySeconds ~/ 60}:${(_otpExpirySeconds % 60).toString().padLeft(2, '0')}',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter the OTP';
                            }
                            if (value.length != 6) {
                              return 'OTP must be 6 digits';
                            }
                            return null;
                          },
                        ),
                      ],

                      const SizedBox(height: 16),

                      // 🧩 Remember Me Checkbox
                      Row(
                        children: [
                          Checkbox(
                            value: _rememberMe,
                            onChanged: (value) {
                              setState(() => _rememberMe = value ?? false);
                            },
                          ),
                          const Text('Remember Me'),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // 🟢 Button
                      _loading
                          ? const CircularProgressIndicator()
                          : SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _loading
                                    ? null
                                    : (_otpSent ? _verifyOtp : _sendOtp),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  backgroundColor: theme.primaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  _otpSent ? 'Verify OTP' : 'Send OTP',
                                  style: const TextStyle(fontSize: 16),
                                ),
                              ),
                            ),

                      // 🟠 Resend + Forgot Password
                      if (_otpSent) ...[
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _otpSent = false;
                              _generatedOtp = null;
                              _otpController.clear();
                            });
                          },
                          child: Text(
                            'Resend OTP',
                            style: TextStyle(color: theme.primaryColor),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _forgotPassword,
                        child: Text(
                          'Forgot Password?',
                          style: TextStyle(color: theme.primaryColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
