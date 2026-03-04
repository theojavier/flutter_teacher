import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

class ExamMonitoringPage extends StatelessWidget {
  final String examId;
  const ExamMonitoringPage({super.key, required this.examId});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF0F2B45),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1F36),
        title: const Text(
          "Monitor Exams",
          style: TextStyle(
            color: Color(0xFFE6F0F8),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder<QuerySnapshot>(
          stream: db
              .collection("exams")
              .doc(examId)
              .collection("students")
              .where(
                "status",
                isEqualTo: "incompleted",
              ) // Students who need to retake
              .snapshots(),
          builder: (context, studentSnapshot) {
            if (studentSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!studentSnapshot.hasData ||
                studentSnapshot.data!.docs.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text("No students to monitor."),
              );
            }

            final students = studentSnapshot.data!.docs;

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: students.length,
              itemBuilder: (context, sIndex) {
                final student = students[sIndex];
                final studentData = student.data() as Map<String, dynamic>;

                final cheatingCount = studentData['cheatingCount'] ?? 0;
                final status = studentData['status'];

                return ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(studentData['name'] ?? 'Unknown'),
                  subtitle: Text(
                    "Status: $status, Cheating count: $cheatingCount",
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      // Update status of student to allow retake or stop the exam
                      _updateStudentStatus(db, examId, student.id, value);
                    },
                    itemBuilder: (context) {
                      return [
                        const PopupMenuItem<String>(
                          value: 'allowed_to_retake',
                          child: Text("Allow Retake"),
                        ),
                        const PopupMenuItem<String>(
                          value: 'stopped',
                          child: Text("Stop Exam"),
                        ),
                      ];
                    },
                    icon: const Icon(Icons.more_vert),
                  ),
                  onTap: () {
                    // Navigate to retake exam page if status is allowed
                    if (status == "allowed_to_retake") {
                      context.goNamed(
                        "examRetake",
                        pathParameters: {"examId": examId},
                      );
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  // Update the status of a student
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
          .update({
            "status": status, // Update the student status
          });
    } catch (e) {
      print("Error updating student status: $e");
    }
  }
}
