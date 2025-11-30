import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../teacher/teacher_dashboard.dart';
import '../teacher/exam_monitoring_page.dart';
import '../teacher/teacher_profile_page.dart';

class TeacherDashboardPageWrapper extends StatelessWidget {
  const TeacherDashboardPageWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final teacherId = FirebaseAuth.instance.currentUser?.uid ?? '';
    return TeacherDashboard(teacherId: teacherId);
  }
}

class ExamMonitoringPageWrapper extends StatelessWidget {
  const ExamMonitoringPageWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("Select an exam"));
  }
}

class TeacherSchedulePageWrapper extends StatelessWidget {
  const TeacherSchedulePageWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text("Schedule"));
  }
}
