import 'dart:async';
import 'package:flutter/material.dart';
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
import 'pages/teacher/teacher_dashboard_page.dart';
import 'pages/teacher/teacher_profile_page.dart' as teacher_profile;

import 'widgets/responsive_scaffold.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await initializeFCM();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final GoRouter router = GoRouter(
      refreshListenable: GoRouterRefreshStream(
        FirebaseAuth.instance.authStateChanges(),
      ),

      initialLocation: '/login',

      redirect: (context, state) {
        final loggedIn = FirebaseAuth.instance.currentUser != null;
        final path = state.uri.path;

        final loggingIn = path == '/login' || path == '/forgot';

        if (!loggedIn && !loggingIn) return '/login';
        if (loggedIn && loggingIn) return '/teacher-dashboard';

        return null;
      },

      routes: [
        // -----------------------------
        // PUBLIC ROUTES
        // -----------------------------
        GoRoute(
          path: '/login',
          pageBuilder: (context, state) =>
              NoTransitionPage(child: const LoginPage()),
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
                  child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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
                          body: Center(child: Text('User not found')),
                        );
                      }

                      final data = snapshot.data!.data()!;
                      final teacherId = data['ID'] ?? '';

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

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Teacher FOTS',
      theme: ThemeData(
        scaffoldBackgroundColor: Color.fromARGB(255, 14, 45, 73),
        canvasColor: Color.fromARGB(255, 14, 45, 73),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(Color.fromARGB(255, 24, 39, 68)),
          trackColor: WidgetStateProperty.all(Colors.black12),
          trackBorderColor: WidgetStateProperty.all(Colors.transparent),
          radius: const Radius.circular(8),
          thickness: WidgetStateProperty.all(8),
        ),

        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          background: Color.fromARGB(255, 14, 45, 73),
        ),
      ),

      routerConfig: router,
    );
  }
}


// AUTH LISTENER (no changes needed)

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
