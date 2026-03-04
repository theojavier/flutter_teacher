import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TeacherMonitoringPage extends StatelessWidget {
  final String teacherId;
  const TeacherMonitoringPage({super.key, required this.teacherId});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Scaffold(
      backgroundColor: const Color(0xFF0F2B45),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1F36),
        title: const Text(
          "Monitoring Exams",
          style: TextStyle(
            color: Color(0xFFE6F0F8),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection("exams")
            .where("teacherId", isEqualTo: teacherId)
            .snapshots(),
        builder: (context, examSnapshot) {
          if (!examSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final exams = examSnapshot.data!.docs;

          if (exams.isEmpty) {
            return const Center(child: Text("No exams found."));
          }

          return ListView(
            children: exams.map((exam) {
              final examData = exam.data() as Map<String, dynamic>;

              return Card(
                color: const Color(0xFF0F2B45),
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  title: Text(
                    examData['subject'] ?? "Unknown Subject",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(255, 255, 255, 255),
                    ),
                  ),
                  subtitle: Text(
                    "${examData['program']} - ${examData['yearBlock'] ?? ''}",
                    style: const TextStyle(
                      color: Color.fromARGB(255, 255, 255, 255),
                    ),
                  ),
                  children: [
                    StreamBuilder<QuerySnapshot>(
                      stream: db
                          .collection('examResults')
                          .doc(exam.id)
                          .collection('students')
                          .snapshots(),
                      builder: (context, studentSnapshot) {
                        if (!studentSnapshot.hasData) {
                          return const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          );
                        }

                        final students = studentSnapshot.data!.docs;

                        if (students.isEmpty) {
                          return const ListTile(
                            title: Text(
                              "No students have taken this exam yet.",
                              style: TextStyle(color: Colors.white)
                            ),
                          );
                        }

                        // Display each student as a card with buttons
                        return Column(
                          children: students.map((studentDoc) {
                            final sData =
                                studentDoc.data() as Map<String, dynamic>;
                            return Card(
                              color: const Color.fromARGB(255, 24, 58, 91),
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  children: [
                                    // Student info
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            "Student ID: ${sData['studentId'] ?? ''}",
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                          Text(
                                            "Status: ${sData['status'] ?? 'N/A'}",
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                          Text(
                                            "Cheating Count: ${sData['cheatingCount'] ?? 0}",
                                            style: const TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Buttons
                                    Column(
                                      children: [
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.red,
                                            fixedSize: const Size(100, 36),
                                          ),
                                          onPressed: () => _stopStudent(
                                            db,
                                            exam.id,
                                            studentDoc.id,
                                          ),
                                          child: const Text(
                                            'Stop',
                                            style: TextStyle(fontSize: 14),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.green,
                                            fixedSize: const Size(100, 36),
                                          ),
                                          onPressed: () => _allowRetake(
                                            db,
                                            exam.id,
                                            studentDoc.id,
                                          ),
                                          child: const Text(
                                            'Retake',
                                            style: TextStyle(fontSize: 14),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  // Stop a student from continuing the exam
  void _stopStudent(
    FirebaseFirestore db,
    String examId,
    String studentId,
  ) async {
    await db
    .collection('examResults')
    .doc(examId)
    .collection('students')
    .doc(studentId)
    .update({
      'currentIndex': 'stopped',
      'status': 'incomplete',
    });

  }

  // Allow a student to retake the exam
  void _allowRetake(
    FirebaseFirestore db,
    String examId,
    String studentId,
  ) async {
    await db
        .collection('examResults')
        .doc(examId)
        .collection('students')
        .doc(studentId)
        .delete();
  }
}
