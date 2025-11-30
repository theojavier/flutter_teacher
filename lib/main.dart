import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import 'firebase_options.dart';
import 'pages/teacher/edit_exam_page.dart';
import 'pages/teacher/edit_question_page.dart';
import 'pages/auth/login_page.dart';
import 'pages/auth/forgot_page.dart';
import 'pages/teacher/exam_monitoring_page.dart';
import 'pages/teacher/teacher_monitoring_page.dart';
import 'pages/teacher/teacher_exams_page.dart';

import 'pages/teacher/teacher_dashboard_page.dart';
import 'pages/teacher/wrappers.dart';
import 'pages/teacher/teacher_profile_page.dart' as teacher_profile;
import 'widgets/responsive_scaffold.dart';

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
        /// PUBLIC ROUTES
        GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
        GoRoute(
          path: '/forgot',
          builder: (context, state) => const ForgotPage(),
        ),

        /// SHELL ROUTE FOR TEACHER NAVIGATION LAYOUT
        ShellRoute(
          builder: (context, state, child) {
            final location = state.uri.path;

            int index = 0;
            if (location.startsWith('/teacher-dashboard'))
              index = 0; // Dashboard
            if (location.startsWith('/teacher-exams')) index = 1; // Exams
            if (location.startsWith('/teacher-monitoring'))
              index = 2; // Monitoring

            return ResponsiveScaffold(
              initialIndex: index,
              homePage: TeacherDashboardPage(
                teacherId: FirebaseAuth.instance.currentUser!.uid,
              ),
              examPage: TeacherExamsPage(
                teacherId: FirebaseAuth.instance.currentUser!.uid,
              ),
              schedulePage: TeacherMonitoringPage(
                teacherId: FirebaseAuth.instance.currentUser!.uid,
              ),
              child: child, // FIXED
            );
          },

          routes: [
            GoRoute(
              path: '/teacher-dashboard',
              builder: (context, state) => TeacherDashboardPage(
                teacherId: FirebaseAuth.instance.currentUser!.uid,
              ),
            ),

            GoRoute(
              path: '/teacher-exams',
              builder: (context, state) => TeacherExamsPage(
                teacherId: FirebaseAuth.instance.currentUser!.uid,
              ),
            ),

            GoRoute(
              path: '/teacher-monitoring',
              builder: (context, state) => TeacherMonitoringPage(
                teacherId: FirebaseAuth.instance.currentUser!.uid,
              ),
            ),

            GoRoute(
              name: 'examMonitoring',
              path: '/exam-monitoring/:examId',
              builder: (context, state) {
                return ExamMonitoringPage(
                  examId: state.pathParameters['examId']!,
                );
              },
            ),

            GoRoute(
              name: 'teacherProfile',
              path: '/teacherProfile/:teacherId',
              builder: (context, state) {
                return teacher_profile.EditProfilePage(
                  teacherId: state.pathParameters['teacherId']!,
                );
              },
            ),
            // EDIT EXAM (with parameter)
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

            // EDIT QUESTION (with parameter)
            GoRoute(
              path: '/edit-question/:examDocId',
              pageBuilder: (context, state) {
                final examDocId = state.pathParameters['examDocId'];

                return NoTransitionPage(
                  child: EditQuestionPage(examDocId: examDocId),
                );
              },
            ),

            // EDIT EXAM (NO PARAM, using extras only)
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

            // EDIT QUESTION (NO PARAM, using extras only)
            GoRoute(
              path: '/edit-question',
              pageBuilder: (context, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};

                return NoTransitionPage(
                  child: EditQuestionPage(examDocId: extra['examDocId']),
                );
              },
            ),
          ],
        ),
      ],
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'FOTS: Teacher',
      theme: ThemeData(primarySwatch: Colors.blue),
      routerConfig: router,
    );
  }
}

/// LISTENER FOR AUTH EVENTS
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
