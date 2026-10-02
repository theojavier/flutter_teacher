import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ExamMonitoringPage extends StatelessWidget {
  final String examId;
  const ExamMonitoringPage({super.key, required this.examId});

  final Color bgColor = const Color(0xFF0F172A);
  final Color cardColor = const Color(0xFF1E293B);
  final Color panelColor = const Color(0xFF243447);

  // Helper to determine the status color
  Color _getStatusColor(String status, int cheatingCount) {
    if (status == 'stopped') return Colors.redAccent; // Caught Cheating
    if (cheatingCount > 0) return Colors.yellowAccent; // Suspicious activity
    return Colors.greenAccent; // Usual activity
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        title: const Text(
          "Monitor Exams",
          style: TextStyle(
            color: Color(0xFFE6F0F8),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder<QuerySnapshot>(
          // Removed the .where filter so you can see students even after they are "stopped"
          stream: db
              .collection("exams")
              .doc(examId)
              .collection("students")
              .snapshots(),
          builder: (context, studentSnapshot) {
            if (studentSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!studentSnapshot.hasData ||
                studentSnapshot.data!.docs.isEmpty) {
              return const Center(
                child: Text(
                  "No students to monitor.",
                  style: TextStyle(color: Colors.white70),
                ),
              );
            }

            final students = studentSnapshot.data!.docs;

            return ListView.builder(
              itemCount: students.length,
              itemBuilder: (context, sIndex) {
                final student = students[sIndex];
                final studentData = student.data() as Map<String, dynamic>;

                final int cheatingCount = studentData['cheatingCount'] ?? 0;
                final String status = studentData['status'] ?? 'active';

                // Get our dynamic color
                final Color statusColor = _getStatusColor(
                  status,
                  cheatingCount,
                );

                return Card(
                  color: panelColor,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: statusColor.withValues(alpha: 0.5),
                      width: 2,
                    ),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: statusColor,
                      child: Icon(
                        status == 'stopped' ? Icons.block : Icons.person,
                        color: Colors.black87,
                      ),
                    ),
                    title: Text(
                      studentData['name'] ?? 'Unknown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "Status: ${status.toUpperCase()}\nViolations: $cheatingCount",
                      style: TextStyle(
                        color: statusColor.withValues(alpha: 0.9),
                      ),
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onSelected: (value) =>
                          _updateStudentStatus(db, examId, student.id, value),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'allowed_to_retake',
                          child: Text("Allow Retake"),
                        ),
                        const PopupMenuItem(
                          value: 'stopped',
                          child: Text("Stop Exam (Mark Cheating)"),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _updateStudentStatus(
    FirebaseFirestore db,
    String examId,
    String studentId,
    String status,
  ) async {
    try {
      await db
          .collection("exams")
          .doc(examId)
          .collection("students")
          .doc(studentId)
          .update({"status": status});
    } catch (e) {
      debugPrint("Error updating student status: $e");
    }
  }
}
