import 'package:flutter/material.dart';

import 'pages/auth/login_page.dart';
import 'pages/auth/forgot_page.dart';
import 'pages/teacher/teacher_dashboard_page.dart';
import 'pages/teacher/exam_monitoring_page.dart';
import 'pages/teacher/teacher_profile_page.dart' as teacher_profile;

class AppRoutes {
  // --------------------------------------
  // ROUTE NAMES
  // --------------------------------------
  static const String login = '/login';
  static const String forgot = '/forgot';

  static const String teacherDashboard = '/teacher-dashboard';  
  static const String examMonitoring = '/exam-monitoring';      
  static const String teacherProfile = '/teacher-profile';

  // --------------------------------------
  // ROUTE MAP
  // --------------------------------------
  static Map<String, WidgetBuilder> routes = {
    // LOGIN
    login: (context) => const LoginPage(),

    // FORGOT PASSWORD
    forgot: (context) => const ForgotPage(),

    // TEACHER DASHBOARD
    teacherDashboard: (context) {
      final args = _getArgs(context);
      final teacherId = args['teacherId'] ?? '';
      return TeacherDashboardPage(teacherId: teacherId);
    },

    // EXAM MONITORING
    examMonitoring: (context) {
      final args = _getArgs(context);
      final examId = args['examId'] ?? '';
      return ExamMonitoringPage(examId: examId);
    },

    // TEACHER PROFILE
    teacherProfile: (context) {
      final args = _getArgs(context);
      final teacherId = args['teacherId'] ?? '';
      return teacher_profile.EditProfilePage(teacherId: teacherId);
    },
  };

  // --------------------------------------------------
  // SAFE ARGUMENT HELPER (prevents crashes)
  // --------------------------------------------------
  static Map<String, dynamic> _getArgs(BuildContext context) {
    final settings = ModalRoute.of(context)?.settings;
    if (settings?.arguments is Map<String, dynamic>) {
      return settings!.arguments as Map<String, dynamic>;
    }
    return {};
  }
}

// --------------------------------------------------
// NAVIGATION EXTENSIONS (IMPROVED)
// --------------------------------------------------
extension NavigatorExtension on BuildContext {
  /// Push a named route with optional path parameters & arguments
  Future<dynamic> pushNamed(
    String name, {
    Map<String, String>? pathParameters,
    Object? arguments,
  }) {
    // Replace path parameters like "/exam-monitoring/:id"
    String finalPath = name;
    if (pathParameters != null) {
      pathParameters.forEach((key, value) {
        finalPath = finalPath.replaceAll(':$key', value);
      });
    }

    return Navigator.of(this).pushNamed(
      finalPath,
      arguments: arguments,
    );
  }

  /// Replace current page (similar to GoRouter go())
  void go(String name, {Object? arguments}) {
    Navigator.of(this).pushReplacementNamed(name, arguments: arguments);
  }
}


// Example of using the updated navigation with arguments
// Navigator.of(context).pushNamed(
//   AppRoutes.teacherProfile,
//   arguments: {'teacherId': 'user123'},
// );
