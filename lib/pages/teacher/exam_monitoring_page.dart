import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ExamMonitoringPage extends StatefulWidget {
  final String examId;

  const ExamMonitoringPage({super.key, required this.examId});

  @override
  State<ExamMonitoringPage> createState() => _ExamMonitoringPageState();
}

class _ExamMonitoringPageState extends State<ExamMonitoringPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Exam Monitoring"),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db.collection("examResults").doc(widget.examId).collection("results").snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No students taking this exam."));
          }
          final results = snapshot.data!.docs;
          return ListView.builder(
            itemCount: results.length,
            itemBuilder: (context, index) {
              final data = results[index].data() as Map<String, dynamic>;
              final studentId = results[index].id;
              final status = data['status'] ?? 'unknown';
              final score = data['score'] ?? 'N/A';

              return ListTile(
                title: Text("Student ID: $studentId"),
                subtitle: Text("Status: $status, Score: $score"),
                trailing: status == 'in-progress'
                    ? const Icon(Icons.hourglass_top, color: Colors.orange)
                    : const Icon(Icons.check_circle, color: Colors.green),
              );
            },
          );
        },
      ),
    );
  }
}
