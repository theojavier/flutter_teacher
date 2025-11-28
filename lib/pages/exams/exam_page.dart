
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/question_model.dart';
import 'package:go_router/go_router.dart';

class TeacherDashboard extends StatefulWidget {
  final String teacherId;

  const TeacherDashboard({super.key, required this.teacherId});

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  int _selectedIndex = 0; // 0 for Exams, 1 for Monitoring

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Teacher Dashboard"),
      ),
      body: _selectedIndex == 0 ? _buildExamsSection() : _buildMonitoringSection(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.create),
            label: 'Exams',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.monitor),
            label: 'Monitoring',
          ),
        ],
      ),
    );
  }

  Widget _buildExamsSection() {
    return Padding(
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
              _showCreateExamDialog();
            },
            child: const Text("Create Exam"),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: db.collection("exams").where("teacherId", isEqualTo: widget.teacherId).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("No exams created yet."));
                }
                final exams = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: exams.length,
                  itemBuilder: (context, index) {
                    final exam = exams[index];
                    final data = exam.data() as Map<String, dynamic>;
                    return Card(
                      child: ListTile(
                        title: Text(data['subject'] ?? 'Exam'),
                        subtitle: Text("Program: ${data['program'] ?? 'N/A'}, Year Block: ${data['yearBlock'] ?? 'N/A'}"),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () {
                            // Optionally, implement edit exam
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonitoringSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: StreamBuilder<QuerySnapshot>(
        stream: db.collection("exams").where("teacherId", isEqualTo: widget.teacherId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No exams to monitor."));
          }
          final exams = snapshot.data!.docs;
          return ListView.builder(
            itemCount: exams.length,
            itemBuilder: (context, index) {
              final exam = exams[index];
              final data = exam.data() as Map<String, dynamic>;
              return Card(
                child: ListTile(
                  title: Text(data['subject'] ?? 'Exam'),
                  subtitle: Text("Program: ${data['program'] ?? 'N/A'}, Year Block: ${data['yearBlock'] ?? 'N/A'}"),
                  onTap: () {
                    context.goNamed(
                      'examMonitoring',
                      pathParameters: {'examId': exam.id},
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showCreateExamDialog() {
    final TextEditingController subjectController = TextEditingController();
    final TextEditingController programController = TextEditingController();
    final TextEditingController yearBlockController = TextEditingController();
    DateTime? startTime;
    DateTime? endTime;
    List<QuestionModel> questions = [];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Create Exam"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: subjectController,
                      decoration: const InputDecoration(labelText: "Subject"),
                    ),
                    TextField(
                      controller: programController,
                      decoration: const InputDecoration(labelText: "Program"),
                    ),
                    TextField(
                      controller: yearBlockController,
                      decoration: const InputDecoration(labelText: "Year Block"),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () async {
                        startTime = await _selectDateTime(context, "Select Start Time");
                        setState(() {});
                      },
                      child: Text(startTime == null ? "Select Start Time" : "Start: ${startTime!.toString()}"),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        endTime = await _selectDateTime(context, "Select End Time");
                        setState(() {});
                      },
                      child: Text(endTime == null ? "Select End Time" : "End: ${endTime!.toString()}"),
                    ),
                    const SizedBox(height: 20),
                    const Text("Questions:"),
                    ...questions.map((q) => ListTile(
                      title: Text(q.questionText ?? ''),
                      subtitle: Text("Type: ${q.type}"),
                    )),
                    ElevatedButton(
                      onPressed: () {
                        _addQuestionDialog(questions, setState);
                      },
                      child: const Text("Add Question"),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (subjectController.text.isNotEmpty && startTime != null && endTime != null && questions.isNotEmpty) {
                      await _createExam(subjectController.text, programController.text, yearBlockController.text, startTime!, endTime!, questions);
                      Navigator.of(context).pop();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields and add questions.")));
                    }
                  },
                  child: const Text("Create"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<DateTime?> _selectDateTime(BuildContext context, String title) async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (date != null) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.now(),
      );
      if (time != null) {
        return DateTime(date.year, date.month, date.day, time.hour, time.minute);
      }
    }
    return null;
  }

  void _addQuestionDialog(List<QuestionModel> questions, StateSetter setState) {
    final TextEditingController questionController = TextEditingController();
    String type = "multiple-choice";
    List<String> options = [];
    String? correctAnswer;
    final TextEditingController optionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Add Question"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: questionController,
                      decoration: const InputDecoration(labelText: "Question Text"),
                    ),
                    DropdownButton<String>(
                      value: type,
                      items: ["multiple-choice", "true-false", "matching"].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (val) {
                        setStateDialog(() {
                          type = val!;
                        });
                      },
                    ),
                    if (type == "multiple-choice" || type == "matching") ...[
                      TextField(
                        controller: optionController,
                        decoration: const InputDecoration(labelText: "Add Option"),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          if (optionController.text.isNotEmpty) {
                            setStateDialog(() {
                              options.add(optionController.text);
                              optionController.clear();
                            });
                          }
                        },
                        child: const Text("Add Option"),
                      ),
                      ...options.map((opt) => ListTile(
                        title: Text(opt),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () {
                            setStateDialog(() {
                              options.remove(opt);
                            });
                          },
                        ),
                      )),
                    ],
                    TextField(
                      decoration: const InputDecoration(labelText: "Correct Answer"),
                      onChanged: (val) => correctAnswer = val,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (questionController.text.isNotEmpty && correctAnswer != null) {
                      final q = QuestionModel(
                        id: UniqueKey().toString(),
                        questionText: questionController.text,
                        type: type,
                        options: type == "multiple-choice" || type == "matching" ? options : null,
                        correctAnswer: correctAnswer,
                      );
                      setState(() {
                        questions.add(q);
                      });
                      Navigator.of(context).pop();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill question and correct answer.")));
                    }
                  },
                  child: const Text("Add"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createExam(String subject, String program, String yearBlock, DateTime startTime, DateTime endTime, List<QuestionModel> questions) async {
    final examRef = db.collection("exams").doc();
    await examRef.set({
      "teacherId": widget.teacherId,
      "subject": subject,
      "program": program,
      "yearBlock": yearBlock,
      "startTime": Timestamp.fromDate(startTime),
      "endTime": Timestamp.fromDate(endTime),
    });

    for (var q in questions) {
      await examRef.collection("questions").add(q.toMap());
    }
  }
}

// Assuming you have an ExamMonitoringPage for monitoring specific exams
// You need to create this separately, e.g., in a new file.

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
        stream: db.collectionGroup("result").where("examId", isEqualTo: widget.examId).snapshots(),
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
              final result = results[index];
              final data = result.data() as Map<String, dynamic>;
              return Card(
                child: ListTile(
                  title: Text("Student: ${data['studentId']}"),
                  subtitle: Text("Status: ${data['status']}, Cheating Count: ${data['cheatingCount'] ?? 0}"),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
