import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

class TeacherMonitoringPage extends StatelessWidget {
  final String teacherId;
  const TeacherMonitoringPage({super.key, required this.teacherId});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Monitor Exams"),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder<QuerySnapshot>(
          stream: db
              .collection("exams")
              .where("teacherId", isEqualTo: teacherId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return const Center(
                child: Text(
                  "No exams to monitor.",
                  style: TextStyle(fontSize: 18),
                ),
              );
            }

            final exams = snapshot.data!.docs;

            return ListView.builder(
              itemCount: exams.length,
              itemBuilder: (context, index) {
                final exam = exams[index];
                final data = exam.data() as Map<String, dynamic>;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(
                      data['subject'] ?? "Unknown Subject",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "${data['program']} - ${data['yearBlock']}",
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      // GO TO MONITORING PAGE FOR THIS EXAM
                      context.goNamed(
                        "examMonitoring", // your route name
                        pathParameters: {
                          "examId": exam.id, // send the exam ID
                        },
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
