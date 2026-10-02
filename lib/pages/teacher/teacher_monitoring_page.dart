import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TeacherMonitoringPage extends StatefulWidget {
  final String teacherId;
  const TeacherMonitoringPage({super.key, required this.teacherId});

  @override
  State<TeacherMonitoringPage> createState() => _TeacherMonitoringPageState();
}

class _TeacherMonitoringPageState extends State<TeacherMonitoringPage> {
  final Color bgColor = const Color(0xFF0F172A);
  final Color cardColor = const Color(0xFF1E293B);
  final Color panelColor = const Color(0xFF243447);
  final Set<String> _expandedStudentIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
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
            .where("teacherId", isEqualTo: widget.teacherId)
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
            padding: const EdgeInsets.only(bottom: 16),
            children: exams.map((exam) {
              final examData = exam.data() as Map<String, dynamic>;

              return Card(
                color: cardColor,
                margin: const EdgeInsets.only(bottom: 12),
                child: ExpansionTile(
                  collapsedIconColor: Colors.white70,
                  iconColor: Colors.white,
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
                              style: TextStyle(color: Colors.white),
                            ),
                          );
                        }

                        return Column(
                          children: students.map((studentDoc) {
                            final sData =
                                studentDoc.data() as Map<String, dynamic>;
                            final studentId = (sData['studentId'] ?? '')
                                .toString();
                            final status = (sData['status'] ?? 'in-progress')
                                .toString();
                            final cheatingCount =
                                int.tryParse(
                                  '${sData['cheatingCount'] ?? 0}',
                                ) ??
                                0;

                            return Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: panelColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Student ID: $studentId',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 18,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Text(
                                                  'Status: $status',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                if (status.toLowerCase() !=
                                                    'stopped')
                                                  const Padding(
                                                    padding: EdgeInsets.only(
                                                      left: 4,
                                                    ),
                                                    child: Icon(
                                                      Icons.check_circle,
                                                      color: Colors.green,
                                                      size: 18,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "Cheating Count: $cheatingCount",
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        children: [
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.red,
                                              fixedSize: const Size(100, 38),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                            onPressed: () => _stopStudent(
                                              db,
                                              exam.id,
                                              studentDoc.id,
                                            ),
                                            child: const Text(
                                              'Stop',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.green,
                                              fixedSize: const Size(100, 38),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                            ),
                                            onPressed: () => _allowRetake(
                                              db,
                                              exam.id,
                                              studentDoc.id,
                                            ),
                                            child: const Text(
                                              'Retake',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        if (_expandedStudentIds.contains(
                                          studentDoc.id,
                                        )) {
                                          _expandedStudentIds.remove(
                                            studentDoc.id,
                                          );
                                        } else {
                                          _expandedStudentIds.add(
                                            studentDoc.id,
                                          );
                                        }
                                      });
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: bgColor,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Detailed Logs',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Icon(
                                            _expandedStudentIds.contains(
                                                  studentDoc.id,
                                                )
                                                ? Icons.keyboard_arrow_up
                                                : Icons.keyboard_arrow_down,
                                            color: Colors.white,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_expandedStudentIds.contains(
                                    studentDoc.id,
                                  ))
                                    const Padding(
                                      padding: EdgeInsets.only(top: 12),
                                      child: Text(
                                        'No cheating incidents recorded yet.',
                                        style: TextStyle(color: Colors.white70),
                                      ),
                                    ),
                                ],
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
        .update({'currentIndex': 'stopped', 'status': 'incomplete'});
  }

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
