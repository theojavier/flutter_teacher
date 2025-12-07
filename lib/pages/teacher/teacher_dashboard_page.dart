import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TeacherDashboardPage extends StatelessWidget {
  final String teacherId;
  const TeacherDashboardPage({super.key, required this.teacherId});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: const Color(0xFF0F2B45),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1F36),
        title: const Text(
          "Teacher Dashboard",
          style: TextStyle(color: Color(0xFFE6F0F8), fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection('exams').where('teacherId', isEqualTo: teacherId).snapshots(),
        builder: (context, examSnapshot) {
          if (!examSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }

          final exams = examSnapshot.data!.docs;

          return StreamBuilder<List<int>>(
            stream: _aggregateStreams(db, exams, now),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }

              final counts = snapshot.data!;
              final totalStudents = counts[0];
              final ongoingExams = counts[1];
              final flaggedStudents = counts[2];

              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _dashboardCard(
                      title: "Total Students",
                      count: totalStudents,
                      icon: Icons.people,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(height: 16),
                    _dashboardCard(
                      title: "Ongoing Exams",
                      count: ongoingExams,
                      icon: Icons.timer,
                      color: Colors.orangeAccent,
                    ),
                    const SizedBox(height: 16),
                    _dashboardCard(
                      title: "Flagged Students",
                      count: flaggedStudents,
                      icon: Icons.warning,
                      color: Colors.redAccent,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _dashboardCard({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
    double height = 120,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            offset: Offset(0, 4),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 40),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                count.toString(),
                style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Stream<List<int>> _aggregateStreams(
      FirebaseFirestore db, List<QueryDocumentSnapshot> exams, DateTime now) async* {
    while (true) {
      int totalStudents = 0;
      int totalFlagged = 0;
      int totalOngoing = 0;

      for (var exam in exams) {
        final examId = exam.id;
        final examData = exam.data() as Map<String, dynamic>;

        final start = (examData['startTime'] as Timestamp).toDate();
        final end = (examData['endTime'] as Timestamp).toDate();

        final isOngoing = now.isAfter(start) && now.isBefore(end);
        if (isOngoing) {
          totalOngoing += 1;

          final studentSnap = await db.collection('examResults').doc(examId).collection('students').get();
          totalStudents += studentSnap.size;

          final flaggedCount = studentSnap.docs
              .where((doc) => (doc.data() as Map<String, dynamic>)['cheatingCount'] != null &&
                  (doc.data() as Map<String, dynamic>)['cheatingCount'] > 0)
              .length;
          totalFlagged += flaggedCount;
        }
      }

      yield [totalStudents, totalOngoing, totalFlagged];
      await Future.delayed(const Duration(seconds: 1));
    }
  }
}
