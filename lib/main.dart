import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import 'firebase_options.dart';
import 'pages/teacher/teacher_dashboard.dart';
import 'pages/teacher/exam_monitoring_page.dart';
import 'pages/auth/login_page.dart';
import 'pages/auth/forgot_page.dart';

import 'pages/teacher/teacher_profile_page.dart' as teacher_profile;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final GoRouter router = GoRouter(
      // Listen to auth changes to reactively redirect
      refreshListenable: GoRouterRefreshStream(
        FirebaseAuth.instance.authStateChanges(),
      ),
      initialLocation: '/login',
      routes: [
        // Public Routes
        GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
        GoRoute(
          path: '/forgot',
          builder: (context, state) => const ForgotPage(),
        ),
        // Teacher Routes
        GoRoute(
          name: 'teacherDashboard',
          path: '/teacher-dashboard',
          builder: (context, state) {
            final teacherId = FirebaseAuth.instance.currentUser?.uid ?? '';
            return TeacherDashboard(teacherId: teacherId);
          },
        ),

        GoRoute(
          name: 'teacherProfile',
          path: '/teacherProfile/:teacherId',
          builder: (context, state) {
            final teacherId = state.pathParameters['teacherId']!;
            return teacher_profile.EditProfilePage(teacherId: teacherId);
          },
        ),

        GoRoute(
          name: 'examMonitoring',
          path: '/exam-monitoring/:examId',
          builder: (context, state) =>
              ExamMonitoringPage(examId: state.pathParameters['examId']!),
        ),
      ],
      redirect: (context, state) {
        final loggedIn = FirebaseAuth.instance.currentUser != null;
        final loggingIn =
            state.uri.toString() == '/login' ||
            state.uri.toString() == '/forgot';

        if (!loggedIn && !loggingIn) return '/login';
        if (loggedIn && loggingIn) return '/teacher-dashboard';
        return null;
      },
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'FOTS: Teacher',
      theme: ThemeData(primarySwatch: Colors.blue),
      routerConfig: router,
    );
  }
}

// Helper to allow GoRouter to listen to Firebase auth changes
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((event) {
      notifyListeners();
    });
  }
  late final StreamSubscription<dynamic> _subscription;
  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
