import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

class TeacherExamsPage extends StatefulWidget {
  const TeacherExamsPage({super.key});

  @override
  State<TeacherExamsPage> createState() => _TeacherExamsPageState();
}

class _TeacherExamsPageState extends State<TeacherExamsPage> {
  final FirebaseFirestore db = FirebaseFirestore.instance;

  Future<String?> _loadTeacherId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final doc = await db.collection("users").doc(uid).get();
    if (!doc.exists) return null;

    return doc.data()?["ID"]; // example "001-0711"
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _loadTeacherId(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final teacherId = snapshot.data;

        if (teacherId == null) {
          return const Scaffold(
            body: Center(child: Text("Teacher ID not found")),
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F2B45),
          appBar: AppBar(
            title: const Text(
              "Teacher Exams",
              style: TextStyle(
                color: Color(0xFFE6F0F8),
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: true,
            backgroundColor: const Color(0xFF0A1F36),
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Create New Exam",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: () {
                    // Pass teacherId to the EditExamPage
                    context.push(
                      '/edit-exam',
                      extra: {
                        'teacherId': teacherId,
                        'docId': null,
                        'existing': null,
                      },
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue, // Button background color
                  ),
                  child: const Text(
                    "Create Exam",
                    style: TextStyle(
                      color: Colors.white, // Make text white
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: db
                        .collection("exams")
                        .where("teacherId", isEqualTo: teacherId)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final exams = snapshot.data!.docs;

                      if (exams.isEmpty) {
                        return const Center(
                          child: Text("No exams created yet."),
                        );
                      }

                      return ListView(
                        children: exams.map((e) {
                          final data = e.data() as Map<String, dynamic>;

                          return Card(
                            color: const Color(0xFF1F3A57),
                            child: ListTile(
                              title: Text(
                                data['subject'],
                                style: const TextStyle(color: Colors.white),
                              ),
                              subtitle: Text(
                                "${data['program']} - ${data['yearBlock']}",
                                style: const TextStyle(color: Colors.white),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // EDIT
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      context.push(
                                        '/edit-exam/${e.id}',
                                        extra: {'existing': data},
                                      );
                                    },
                                  ),

                                  // DELETE
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
      },
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

        // delete inner questions
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
