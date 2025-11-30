import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../models/question_model.dart';

class TeacherExamsPage extends StatefulWidget {
  final String teacherId;
  const TeacherExamsPage({super.key, required this.teacherId});

  @override
  State<TeacherExamsPage> createState() => _TeacherExamsPageState();
}

class _TeacherExamsPageState extends State<TeacherExamsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Create New Exam",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: () {
                context.push(
                  '/edit-exam',
                  extra: {'docId': null, 'existing': null},
                );
              },
              child: const Text("Create Exam"),
            ),
            const SizedBox(height: 20),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: db
                    .collection("exams")
                    .where("teacherId", isEqualTo: widget.teacherId)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final exams = snapshot.data!.docs;

                  if (exams.isEmpty) {
                    return const Center(child: Text("No exams created yet."));
                  }

                  return ListView(
                    children: exams.map((e) {
                      final data = e.data() as Map<String, dynamic>;
                      return Card(
                        child: ListTile(
                          title: Text(data['subject']),
                          subtitle: Text(
                            "${data['program']} - ${data['yearBlock']}",
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () {
                                  context.push(
                                    '/edit-exam/${e.id}',
                                    extra: {'existing': data},
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                onPressed: () => _deleteExam(e.id),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteExam(String examId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Exam"),
        content: const Text("Are you sure you want to delete this exam?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final examRef = db.collection("exams").doc(examId);
        final questionsSnap = await examRef.collection("questions").get();
        for (var doc in questionsSnap.docs) {
          await doc.reference.delete();
        }
        await examRef.delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Exam deleted successfully")),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Error deleting exam: $e")));
        }
      }
    }
  }
}
