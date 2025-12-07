import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ExamRetakePage extends StatelessWidget {
  final String examId;

  const ExamRetakePage({super.key, required this.examId});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Retake Exam"),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: db.collection("exams").doc(examId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Exam not found."));
          }

          final examData = snapshot.data!.data() as Map<String, dynamic>;

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Text(
                  "Subject: ${examData['subject']}",
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                // Other exam details
                ElevatedButton(
                  onPressed: () {
                    // Start retake exam logic
                    // e.g., mark the student as retaking and allow them to answer questions
                  },
                  child: const Text("Start Retake"),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
