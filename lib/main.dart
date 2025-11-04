import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Faculty Management',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      initialRoute: '/',
      routes: {
        '/': (_) => const LoginPage(),
        '/dashboard': (_) => const DashboardPage(),
        '/forgot-password': (_) => const ForgotPasswordPage(),
      },
    );
  }
}

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
  bool _otpSent = false; // start with false; user sends OTP first
  String? _generatedOtp; // Simulated OTP for demo
  int _otpExpirySeconds = 300; // 5 minutes expiry (demo)

  final _emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+$');

  void _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    // Simulate API call to send OTP
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    _generatedOtp = '123456'; // demo OTP

    setState(() {
      _loading = false;
      _otpSent = true;
      _otpExpirySeconds = 300;
    });

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

    _startOtpTimer();
  }

  void _verifyOtp() async {
    if (!_formKey.currentState!.validate()) return;

    if (_otpController.text.trim() != _generatedOtp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid OTP. Please try again.')),
      );
      return;
    }

    setState(() => _loading = true);

    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    setState(() => _loading = false);
    Navigator.of(context).pushReplacementNamed('/dashboard');
  }

  void _startOtpTimer() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (_otpExpirySeconds > 0) {
        setState(() => _otpExpirySeconds--);
        _startOtpTimer();
      } else {
        setState(() {
          _otpSent = false;
          _generatedOtp = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('OTP expired. Please request a new one.'),
            ),
          );
        }
      }
    });
  }

  void _forgotPassword() {
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

                      // Email field
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

                      const SizedBox(height: 16),

                      // OTP field (visible if _otpSent)
                      if (_otpSent) ...[
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
                            if (_otpSent) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter the OTP';
                              }
                              if (value.length != 6) {
                                return 'OTP must be 6 digits';
                              }
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

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

                      if (_otpSent) ...[
                        const SizedBox(height: 12),
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

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard'), centerTitle: true),
      body: const Center(child: Text('Welcome to the Dashboard')),
    );
  }
}

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password'), centerTitle: true),
      body: const Center(child: Text('Forgot Password Page (stub)')),
    );
  }
}
