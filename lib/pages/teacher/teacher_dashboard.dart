import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  int _selectedIndex = 0;

  // Dashboard summary stats
  int totalStudents = 0;
  int ongoingExams = 0;
  int flaggedStudents = 0;
  double averageScore = 0.0;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    final studentsSnapshot = await db.collection('students').get();
    final examsSnapshot = await db
        .collection('exams')
        .where('teacherId', isEqualTo: widget.teacherId)
        .where('status', isEqualTo: 'ongoing')
        .get();
    final flaggedSnapshot = await db
        .collection('students')
        .where('flagged', isEqualTo: true)
        .get();

    double totalScore = 0;
    for (var doc in studentsSnapshot.docs) {
      totalScore += (doc['average_score'] ?? 0);
    }

    setState(() {
      totalStudents = studentsSnapshot.size;
      ongoingExams = examsSnapshot.size;
      flaggedStudents = flaggedSnapshot.size;
      averageScore = studentsSnapshot.size > 0
          ? totalScore / studentsSnapshot.size
          : 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _buildOverviewSection(),
      _buildExamsSection(),
      _buildMonitoringSection(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text("Teacher Dashboard"),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: 'Profile',
            onPressed: () {
              context.goNamed(
                'teacherProfile',
                pathParameters: {'teacherId': widget.teacherId},
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                context.goNamed('login');
              }
            },
          ),
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.create), label: 'Exams'),
          BottomNavigationBarItem(
            icon: Icon(Icons.monitor),
            label: 'Monitoring',
          ),
        ],
      ),
    );
  }

  // -----------------------
  // 🧭 1. OVERVIEW SECTION
  // -----------------------
  Widget _buildOverviewSection() {
    return RefreshIndicator(
      onRefresh: _loadDashboardData,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "Class Overview",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          _buildInfoCard(
            "Total Students",
            totalStudents.toString(),
            Icons.people,
            Colors.blue,
          ),
          _buildInfoCard(
            "Ongoing Exams",
            ongoingExams.toString(),
            Icons.access_time,
            Colors.orange,
          ),
          _buildInfoCard(
            "Flagged Students",
            flaggedStudents.toString(),
            Icons.warning,
            Colors.redAccent,
          ),
          _buildInfoCard(
            "Average Score",
            averageScore.toStringAsFixed(2),
            Icons.bar_chart,
            Colors.green,
          ),
          const SizedBox(height: 30),
          const Text(
            "Quick Actions",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: () => setState(() => _selectedIndex = 1),
                icon: const Icon(Icons.create),
                label: const Text("Create Exam"),
              ),
              ElevatedButton.icon(
                onPressed: () => setState(() => _selectedIndex = 2),
                icon: const Icon(Icons.monitor),
                label: const Text("Monitor Exams"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        trailing: Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }

  // -----------------------
  // 🧾 2. EXAMS SECTION
  // -----------------------
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
            onPressed: () => _showCreateExamDialog(),
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
                        subtitle: Text(
                          "Program: ${data['program'] ?? 'N/A'}, Year Block: ${data['yearBlock'] ?? 'N/A'}",
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () =>
                                  _showEditExamDialog(exam.id, data),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteExam(exam.id),
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
        ],
      ),
    );
  }

  // -----------------------
  // 🖥️ 3. MONITORING SECTION
  // -----------------------
  Widget _buildMonitoringSection() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection("exams")
            .where("teacherId", isEqualTo: widget.teacherId)
            .snapshots(),
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
                  subtitle: Text(
                    "Program: ${data['program'] ?? 'N/A'}, Year Block: ${data['yearBlock'] ?? 'N/A'}",
                  ),
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

  // -----------------------
  // ⚙️ CREATE EXAM DIALOG
  // -----------------------
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
                      decoration: const InputDecoration(
                        labelText: "Year Block",
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () async {
                        startTime = await _selectDateTime(
                          context,
                          "Select Start Time",
                        );
                        setState(() {});
                      },
                      child: Text(
                        startTime == null
                            ? "Select Start Time"
                            : "Start: ${startTime!.toString()}",
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        endTime = await _selectDateTime(
                          context,
                          "Select End Time",
                        );
                        setState(() {});
                      },
                      child: Text(
                        endTime == null
                            ? "Select End Time"
                            : "End: ${endTime!.toString()}",
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text("Questions:"),
                    ...questions.map(
                      (q) => ListTile(
                        title: Text(q.questionText ?? ''),
                        subtitle: Text("Type: ${q.type}"),
                      ),
                    ),
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
                    if (subjectController.text.isNotEmpty &&
                        startTime != null &&
                        endTime != null &&
                        questions.isNotEmpty) {
                      await _createExam(
                        subjectController.text,
                        programController.text,
                        yearBlockController.text,
                        startTime!,
                        endTime!,
                        questions,
                      );
                      Navigator.of(context).pop();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Please fill all fields and add questions.",
                          ),
                        ),
                      );
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
        return DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
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
                      decoration: const InputDecoration(
                        labelText: "Question Text",
                      ),
                    ),
                    DropdownButton<String>(
                      value: type,
                      items: ["multiple-choice", "true-false", "matching"]
                          .map(
                            (t) => DropdownMenuItem(value: t, child: Text(t)),
                          )
                          .toList(),
                      onChanged: (val) {
                        setStateDialog(() {
                          type = val!;
                        });
                      },
                    ),
                    if (type == "multiple-choice" || type == "matching") ...[
                      TextField(
                        controller: optionController,
                        decoration: const InputDecoration(
                          labelText: "Add Option",
                        ),
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
                      ...options.map(
                        (opt) => ListTile(
                          title: Text(opt),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () {
                              setStateDialog(() {
                                options.remove(opt);
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                    TextField(
                      decoration: const InputDecoration(
                        labelText: "Correct Answer",
                      ),
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
                    if (questionController.text.isNotEmpty &&
                        correctAnswer != null) {
                      final q = QuestionModel(
                        id: UniqueKey().toString(),
                        questionText: questionController.text,
                        type: type,
                        options: type == "multiple-choice" || type == "matching"
                            ? options
                            : null,
                        correctAnswer: correctAnswer,
                      );
                      setState(() {
                        questions.add(q);
                      });
                      Navigator.of(context).pop();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Please fill question and correct answer.",
                          ),
                        ),
                      );
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

  Future<void> _createExam(
    String subject,
    String program,
    String yearBlock,
    DateTime startTime,
    DateTime endTime,
    List<QuestionModel> questions,
  ) async {
    final examRef = db.collection("exams").doc();
    await examRef.set({
      "teacherId": widget.teacherId,
      "subject": subject,
      "program": program,
      "yearBlock": yearBlock,
      "startTime": Timestamp.fromDate(startTime),
      "endTime": Timestamp.fromDate(endTime),
      "status": "upcoming",
      "createdAt": FieldValue.serverTimestamp(),
    });

    for (var q in questions) {
      await examRef.collection("questions").add(q.toMap());
    }
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

  Future<void> _showEditExamDialog(
    String examId,
    Map<String, dynamic> data,
  ) async {
    final TextEditingController subjectController = TextEditingController(
      text: data['subject'] ?? '',
    );
    final TextEditingController programController = TextEditingController(
      text: data['program'] ?? '',
    );
    final TextEditingController yearBlockController = TextEditingController(
      text: data['yearBlock'] ?? '',
    );
    DateTime? startTime = (data['startTime'] as Timestamp?)?.toDate();
    DateTime? endTime = (data['endTime'] as Timestamp?)?.toDate();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text("Edit Exam"),
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
                      decoration: const InputDecoration(
                        labelText: "Year Block",
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () async {
                        startTime = await _selectDateTime(
                          context,
                          "Select Start Time",
                        );
                        setState(() {});
                      },
                      child: Text(
                        startTime == null
                            ? "Select Start Time"
                            : "Start: ${startTime!.toString()}",
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () async {
                        endTime = await _selectDateTime(
                          context,
                          "Select End Time",
                        );
                        setState(() {});
                      },
                      child: Text(
                        endTime == null
                            ? "Select End Time"
                            : "End: ${endTime!.toString()}",
                      ),
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
                    if (subjectController.text.isNotEmpty &&
                        startTime != null &&
                        endTime != null) {
                      try {
                        await db.collection("exams").doc(examId).update({
                          "subject": subjectController.text,
                          "program": programController.text,
                          "yearBlock": yearBlockController.text,
                          "startTime": Timestamp.fromDate(startTime!),
                          "endTime": Timestamp.fromDate(endTime!),
                        });
                        if (mounted) {
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Exam updated successfully"),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("Error updating exam: $e")),
                          );
                        }
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Please fill all required fields."),
                        ),
                      );
                    }
                  },
                  child: const Text("Update"),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
