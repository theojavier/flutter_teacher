import 'package:flutter/material.dart';

import 'pages/auth/login_page.dart';
import 'pages/auth/forgot_page.dart';
import 'pages/teacher/teacher_dashboard.dart';
import 'pages/teacher/exam_monitoring_page.dart';
import 'pages/teacher/teacher_profile_page.dart' as teacher_profile;

class AppRoutes {
  // Route names
  static const String login = '/login';
  static const String forgot = '/forgot';
  static const String teacherDashboard = '/teacher-dashboard';
  static const String examMonitoring = '/exam-monitoring';
  static const String teacherProfile = '/teacher-profile';

  // Route map
  static Map<String, WidgetBuilder> routes = {
    login: (context) => const LoginPage(),
    forgot: (context) => const ForgotPage(),

    teacherDashboard: (context) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
      final teacherId = args?['teacherId'] as String? ?? '';
      return TeacherDashboard(teacherId: teacherId);
    },

    examMonitoring: (context) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      return ExamMonitoringPage(examId: args['examId']);
    },

    teacherProfile: (context) {
      final args =
          ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
      final teacherId = args?['teacherId'] as String? ?? '';
      return teacher_profile.EditProfilePage(
        teacherId: teacherId,
      ); // ✅ teacher profile route
    },
  };
}

extension NavigatorExtension on BuildContext {
  Future<dynamic> pushNamed(
    String name, {
    Map<String, String>? pathParameters,
    Object? arguments,
  }) {
    // Handle path parameters if any
    String path = name;
    if (pathParameters != null) {
      pathParameters.forEach((key, value) {
        path = path.replaceAll(':$key', value);
      });
    }
    return Navigator.of(this).pushNamed(path, arguments: arguments);
  }

  void go(String name, {Object? arguments}) {
    Navigator.of(this).pushNamed(name, arguments: arguments);
  }
}

// Example of using the updated navigation with arguments
// Navigator.of(context).pushNamed(
//   AppRoutes.teacherProfile,
//   arguments: {'teacherId': 'user123'},
// );
