import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'firebase_options.dart';
import 'services/fcm_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore
import 'pages/teacher/edit_question_page.dart';
import 'pages/auth/login_page.dart';
import 'pages/auth/forgot_page.dart';
import 'pages/teacher/exam_monitoring_page.dart';
import 'pages/teacher/teacher_monitoring_page.dart';
import 'pages/teacher/teacher_exams_page.dart';
import 'pages/teacher/teacher_schedule_page.dart';
import 'pages/teacher/student_management_page.dart';
import 'pages/teacher/teacher_dashboard_page.dart';
import 'pages/teacher/teacher_profile_page.dart' as teacher_profile;
import 'pages/teacher/teacher_reports_page.dart';
import 'pages/teacher/teacher_notifications_page.dart';

import 'widgets/responsive_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // FIX 1: make context.push()/pushReplacement() update the browser URL too.
  // (Since go_router 10 this is OFF by default, so pushed pages never
  // changed the "#/..." part of the address bar.)
  GoRouter.optionURLReflectsImperativeAPIs = true;

  // FIX 2: on web, Firebase restores the logged-in user asynchronously.
  // If the router runs its first redirect before that finishes, it thinks
  // you're logged out, sends you to /login, and then bounces you to
  // /teacher-dashboard -> every reload "goes back" to the dashboard.
  // Wait for the first auth state before building the router.
  if (kIsWeb) {
    await FirebaseAuth.instance.authStateChanges().first.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
  }

  await initializeFCM();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  GoRouterRefreshStream? _refreshAuth;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();

    final refreshAuthChanges =
        kIsWeb || defaultTargetPlatform != TargetPlatform.windows;

    if (refreshAuthChanges) {
      _refreshAuth = GoRouterRefreshStream(
        FirebaseAuth.instance.authStateChanges(),
      );
    }

    // FIX 3: build the router ONCE. Before, it was created inside build(),
    // so any rebuild (hot reload, theme change...) made a brand-new router
    // that restarted at '/login' -> '/teacher-dashboard'.
    _router = _buildRouter();
  }

  @override
  void dispose() {
    _refreshAuth?.dispose();
    _router.dispose();
    super.dispose();
  }

  GoRouter _buildRouter() {
    return GoRouter(
      refreshListenable: _refreshAuth,

      initialLocation: '/login',

      redirect: (context, state) {
        final user = FirebaseAuth.instance.currentUser;
        final path = state.matchedLocation;
        final authRoute = path == '/login' || path == '/forgot';

        // A logged-out user may still briefly be seen as null during web auth
        // restoration. Keep auth routes accessible, but prevent any protected
        // route from redirecting back to /login after the user is already known.
        if (user == null) {
          if (authRoute || path == '/') {
            return null;
          }
          return '/login';
        }

        if (path == '/') {
          return '/teacher-dashboard';
        }

        if (authRoute) {
          return '/teacher-dashboard';
        }

        return null;
      },

      routes: [
        // -----------------------------
        // PUBLIC ROUTES
        // -----------------------------
        GoRoute(
          path: '/login',
          pageBuilder: (context, state) =>
              NoTransitionPage(child: TeacherLoginPage()),
        ),
        GoRoute(
          path: '/forgot',
          pageBuilder: (context, state) =>
              NoTransitionPage(child: const ForgotPage()),
        ),

        // -----------------------------
        // TEACHER PROTECTED LAYOUT
        // -----------------------------
        ShellRoute(
          builder: (context, state, child) {
            final teacherId = FirebaseAuth.instance.currentUser?.uid ?? '';

            final location = state.uri.path;
            int index = 0;

            if (location.startsWith('/teacher-dashboard')) index = 0;
            if (location.startsWith('/teacher-exams') ||
                location.startsWith('/exam-clips'))
              index = 1;
            if (location.startsWith('/teacher-monitoring')) index = 2;

            return ResponsiveScaffold(
              initialIndex: index,
              homePage: TeacherDashboardPage(teacherId: teacherId),
              examPage: const TeacherExamsPage(),
              schedulePage: const TeacherSchedulePage(),
              child: child,
            );
          },
          routes: [
            // DASHBOARD
            GoRoute(
              path: '/teacher-dashboard',
              pageBuilder: (context, state) {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid == null) {
                  return NoTransitionPage(
                    child: const Scaffold(
                      body: Center(child: Text('No user logged in')),
                    ),
                  );
                }

                return NoTransitionPage(
                  child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .where('UID', isEqualTo: uid)
                        .limit(1)
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Scaffold(
                          body: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Scaffold(
                          body: Center(child: Text('User not found')),
                        );
                      }

                      final data = snapshot.data!.docs.first.data();
                      final teacherId = data['ID'];
                      if (teacherId is! String || teacherId.isEmpty) {
                        return const Scaffold(
                          body: Center(child: Text('Teacher ID is missing')),
                        );
                      }

                      return TeacherDashboardPage(teacherId: teacherId);
                    },
                  ),
                );
              },
            ),

            // TEACHER EXAMS
            GoRoute(
              path: '/teacher-exams',
              pageBuilder: (context, state) =>
                  NoTransitionPage(child: const TeacherExamsPage()),
            ),

            // TEACHER SCHEDULE
            GoRoute(
              path: '/teacher-schedule',
              pageBuilder: (context, state) =>
                  NoTransitionPage(child: const TeacherSchedulePage()),
            ),

            // MONITORING
            GoRoute(
              path: '/teacher-monitoring',
              pageBuilder: (context, state) {
                final uid = FirebaseAuth.instance.currentUser?.uid ?? "";

                return NoTransitionPage(
                  child: FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .get(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Scaffold(
                          body: Center(child: CircularProgressIndicator()),
                        );
                      }

                      if (!snapshot.hasData || !snapshot.data!.exists) {
                        return const Scaffold(
                          body: Center(child: Text("Teacher data not found.")),
                        );
                      }

                      final data =
                          snapshot.data!.data() as Map<String, dynamic>;
                      final teacherId = data['ID'] ?? "";

                      return TeacherMonitoringPage(teacherId: teacherId);
                    },
                  ),
                );
              },
            ),

            // STUDENT MANAGEMENT
            GoRoute(
              path: '/student-management',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: StudentManagementPage()),
            ),

            GoRoute(
              path: '/teacher-reports',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: TeacherReportsPage()),
            ),
            GoRoute(
              path: '/teacher-notifications',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: TeacherNotificationsPage()),
            ),

            // SPECIFIC EXAM MONITORING
            GoRoute(
              name: 'examMonitoring',
              path: '/exam-monitoring/:examId',
              pageBuilder: (context, state) => NoTransitionPage(
                child: ExamMonitoringPage(
                  examId: state.pathParameters['examId']!,
                ),
              ),
            ),

            // TEACHER PROFILE
            GoRoute(
              name: 'teacherProfile',
              path: '/teacherProfile/:teacherId',
              pageBuilder: (context, state) => NoTransitionPage(
                child: teacher_profile.EditProfilePage(
                  teacherId: state.pathParameters['teacherId']!,
                ),
              ),
            ),

            // EDIT QUESTION
            GoRoute(
              path: '/edit-question/:examDocId',
              pageBuilder: (context, state) => NoTransitionPage(
                child: EditQuestionPage(
                  examDocId: state.pathParameters['examDocId']!,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Teacher FOTS',
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF7F8F6),
        canvasColor: const Color(0xFFF7F8F6),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(
            const Color(0xFF153CFF).withValues(alpha: 0.45),
          ),
          trackColor: WidgetStateProperty.all(const Color(0xFFDCDDDC)),
          trackBorderColor: WidgetStateProperty.all(Colors.transparent),
          radius: const Radius.circular(8),
          thickness: WidgetStateProperty.all(8),
        ),
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(0xFF153CFF),
              brightness: Brightness.light,
            ).copyWith(
              primary: const Color(0xFF153CFF),
              secondary: const Color(0xFF153CFF),
              tertiary: const Color(0xFF153CFF),
              surface: const Color(0xFFF7F8F6),
              error: const Color(0xFFC73044),
            ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF7F8F6),
          foregroundColor: Color(0xFF111217),
          elevation: 0,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: Color(0xFF153CFF),
        ),
      ),
      routerConfig: _router,
    );
  }
}

// AUTH LISTENER

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
