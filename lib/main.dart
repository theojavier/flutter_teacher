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
import 'pages/teacher/edit_exam_page.dart';
import 'pages/teacher/edit_question_page.dart';
import 'pages/auth/login_page.dart';
import 'pages/auth/forgot_page.dart';
import 'pages/teacher/exam_monitoring_page.dart';
import 'pages/teacher/teacher_monitoring_page.dart';
import 'pages/teacher/teacher_exams_page.dart';
import 'pages/teacher/student_management_page.dart';
import 'pages/teacher/teacher_dashboard_page.dart' hide ResponsiveScaffold;
import 'pages/teacher/teacher_profile_page.dart' as teacher_profile;
import 'pages/teacher/exam_clips_page.dart';

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
        final loggedIn = FirebaseAuth.instance.currentUser != null;
        final path = state.uri.path;

        final loggingIn = path == '/login' || path == '/forgot';

        if (path == '/') {
          return loggedIn ? '/teacher-dashboard' : '/login';
        }

        if (!loggedIn && !loggingIn) {
          return '/login';
        }

        if (loggedIn && loggingIn) {
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
            if (location.startsWith('/teacher-exams')) index = 1;
            if (location.startsWith('/teacher-monitoring')) index = 2;

            return ResponsiveScaffold(
              initialIndex: index,
              homePage: TeacherDashboardPage(teacherId: teacherId),
              examPage: const TeacherExamsPage(),
              schedulePage: TeacherMonitoringPage(teacherId: teacherId),
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
            GoRoute(
              path: '/exam-clips/:examId',
              pageBuilder: (context, state) {
                final examId = state.pathParameters['examId']!;

                return NoTransitionPage(child: ExamClipsPage(examId: examId));
              },
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
              pageBuilder: (context, state) {
                final teacherId = FirebaseAuth.instance.currentUser?.uid ?? "";
                return NoTransitionPage(
                  child: StudentManagementPage(teacherId: teacherId),
                );
              },
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

            // EDIT EXAM
            GoRoute(
              path: '/edit-exam/:examId',
              pageBuilder: (context, state) {
                final examId = state.pathParameters['examId'];
                final extra = state.extra as Map<String, dynamic>? ?? {};
                return NoTransitionPage(
                  child: EditExamPage(
                    docId: examId,
                    existing: extra['existing'],
                  ),
                );
              },
            ),

            GoRoute(
              path: '/edit-exam',
              pageBuilder: (context, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};
                return NoTransitionPage(
                  child: EditExamPage(
                    docId: extra['docId'],
                    existing: extra['existing'],
                  ),
                );
              },
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
        scaffoldBackgroundColor: const Color.fromARGB(255, 14, 45, 73),
        canvasColor: const Color.fromARGB(255, 14, 45, 73),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(
            const Color.fromARGB(255, 24, 39, 68),
          ),
          trackColor: WidgetStateProperty.all(Colors.black12),
          trackBorderColor: WidgetStateProperty.all(Colors.transparent),
          radius: const Radius.circular(8),
          thickness: WidgetStateProperty.all(8),
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          surface: const Color.fromARGB(255, 14, 45, 73),
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
