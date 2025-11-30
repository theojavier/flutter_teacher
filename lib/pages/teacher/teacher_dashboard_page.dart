import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';

class TeacherDashboardPage extends StatefulWidget {
  final String teacherId;

  const TeacherDashboardPage({super.key, required this.teacherId});

  @override
  State<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends State<TeacherDashboardPage> {
  final db = FirebaseFirestore.instance;

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
    final studentsSnapshot = await db
        .collection('students')
        .where('teacherId', isEqualTo: widget.teacherId)
        .get();

    final examsSnapshot = await db
        .collection('exams')
        .where('teacherId', isEqualTo: widget.teacherId)
        .where('isActive', isEqualTo: true)
        .get();

    final flaggedSnapshot = await db
        .collection('students')
        .where('teacherId', isEqualTo: widget.teacherId)
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
    return Scaffold(
      appBar: AppBar(title: const Text("Teacher Dashboard")),
      body: RefreshIndicator(
        onRefresh: _loadDashboardData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildOverviewSection(),
            const SizedBox(height: 20),
            const Text(
              "Recent Exams",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: db
                  .collection('exams')
                  .where('teacherId', isEqualTo: widget.teacherId)
                  .orderBy(
                    'createdAt',
                    descending: true,
                  ) // <-- correct field name
                  .limit(10)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Text("Error: ${snapshot.error}");
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Text("No exams found.");
                }

                final docs = snapshot.data!.docs;
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final rawData = docs[index].data() as Map<String, dynamic>;
                    final createdAt = (rawData['createdAt'] as Timestamp?)
                        ?.toDate(); // <-- correct

                    return Card(
                      child: ListTile(
                        title: Text(rawData['title'] ?? 'Untitled Exam'),
                        subtitle: Text(
                          "Created: ${createdAt != null ? createdAt.toString().split('.')[0] : 'N/A'}",
                        ),
                        trailing: Icon(
                          rawData['isActive'] == true
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: rawData['isActive'] == true
                              ? Colors.green
                              : Colors.grey,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
              onPressed: () {
                context.push(
                  '/edit-exam',
                  extra: {'docId': null, 'existing': null},
                );
              },
              icon: const Icon(Icons.create),
              label: const Text("Create Exam"),
            ),
            ElevatedButton.icon(
              onPressed: () {
                context.push('/teacher-monitoring');
              },
              icon: const Icon(Icons.monitor),
              label: const Text("Monitor Exams"),
            ),
          ],
        ),
      ],
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
      margin: const EdgeInsets.symmetric(vertical: 8),
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
}
