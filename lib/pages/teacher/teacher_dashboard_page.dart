import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TeacherDashboardPage extends StatelessWidget {
  final String teacherId;
  const TeacherDashboardPage({super.key, required this.teacherId});

  // UI Theme Colors
  final Color bgColor = const Color(0xFF0F172A);
  final Color cardColor = const Color(0xFF1E293B);

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: bgColor,
      body: StreamBuilder(
        stream: db
            .collection('exams')
            .where('teacherId', isEqualTo: teacherId)
            .snapshots(),
        builder: (context, examSnapshot) {
          if (!examSnapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          final exams = examSnapshot.data!.docs;

          return StreamBuilder<List<int>>(
            stream: _aggregateStreams(db, exams, now),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              }

              final counts = snapshot.data!;
              final totalStudents = counts[0];
              final ongoingExams = counts[1];
              final flaggedStudents = counts[2];

              return _buildMainContent(
                totalStudents: totalStudents,
                ongoingExams: ongoingExams,
                flaggedStudents: flaggedStudents,
              );
            },
          );
        },
      ),
    );
  }

  // --- UI Components ---

  Widget _buildMainContent({
    required int totalStudents,
    required int ongoingExams,
    required int flaggedStudents,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 850;
        final horizontalPadding = constraints.maxWidth < 500 ? 16.0 : 24.0;
        final contentWidth = constraints.maxWidth - horizontalPadding * 2;

        final header = const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Teacher Dashboard',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
        final metrics = _buildMetricCards(
          width: contentWidth,
          totalStudents: totalStudents,
          ongoingExams: ongoingExams,
          flaggedStudents: flaggedStudents,
        );

        if (compact) {
          return SingleChildScrollView(
            padding: EdgeInsets.all(horizontalPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                header,
                const SizedBox(height: 20),
                metrics,
                const SizedBox(height: 20),
                SizedBox(height: 320, child: _buildMonitoringPanel()),
                const SizedBox(height: 16),
                _buildStatusPanel(totalStudents),
              ],
            ),
          );
        }

        return Padding(
          padding: EdgeInsets.all(horizontalPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 24),
              metrics,
              const SizedBox(height: 24),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: _buildMonitoringPanel()),
                    const SizedBox(width: 16),
                    Expanded(child: _buildStatusPanel(totalStudents)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricCards({
    required double width,
    required int totalStudents,
    required int ongoingExams,
    required int flaggedStudents,
  }) {
    const spacing = 16.0;
    final columns = width >= 760
        ? 3
        : width >= 480
        ? 2
        : 1;
    final cardWidth = (width - spacing * (columns - 1)) / columns;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: [
        SizedBox(
          width: cardWidth,
          child: _buildMetricCard(
            'Total Students',
            totalStudents.toString(),
            Icons.people,
            Colors.blue,
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: _buildMetricCard(
            'Ongoing Exams',
            ongoingExams.toString(),
            Icons.timer,
            Colors.orange,
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: _buildMetricCard(
            'Flagged Students',
            flaggedStudents.toString(),
            Icons.warning,
            Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildMonitoringPanel() {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Real-time Monitoring & Flags',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingTextStyle: const TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                  dataTextStyle: const TextStyle(color: Colors.white),
                  columns: const [
                    DataColumn(label: Text('STUDENT')),
                    DataColumn(label: Text('ALERT TYPE')),
                    DataColumn(label: Text('ACTION')),
                  ],
                  rows: const [
                    DataRow(
                      cells: [
                        DataCell(Text('Sarah Jenkins')),
                        DataCell(Text('Gaze Deviation')),
                        DataCell(
                          Text(
                            '[Review]',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                    DataRow(
                      cells: [
                        DataCell(Text('Mike Rossi')),
                        DataCell(Text('Speech detected')),
                        DataCell(
                          Text(
                            '[Review]',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPanel(int totalStudents) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Active Taking Status',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '$totalStudents students connected',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: totalStudents > 0 ? 1.0 : 0.0,
            backgroundColor: Colors.grey[700],
            valueColor: const AlwaysStoppedAnimation(Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color iconColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Icon(icon, color: iconColor),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // --- Your existing Data Logic ---

  Stream<List<int>> _aggregateStreams(
    FirebaseFirestore db,
    List exams,
    DateTime now,
  ) async* {
    while (true) {
      int totalStudents = 0;
      int totalFlagged = 0;
      int totalOngoing = 0;

      for (var exam in exams) {
        final examId = exam.id;
        final examData = exam.data() as Map;

        final start = (examData['startTime'] as Timestamp).toDate();
        final end = (examData['endTime'] as Timestamp).toDate();

        final isOngoing = now.isAfter(start) && now.isBefore(end);
        if (isOngoing) {
          totalOngoing += 1;

          final studentSnap = await db
              .collection('examResults')
              .doc(examId)
              .collection('students')
              .get();
          totalStudents += studentSnap.size;

          final flaggedCount = studentSnap.docs
              .where(
                (doc) =>
                    (doc.data())['cheatingCount'] != null &&
                    (doc.data())['cheatingCount'] > 0,
              )
              .length;
          totalFlagged += flaggedCount;
        }
      }

      yield [totalStudents, totalOngoing, totalFlagged];
      await Future.delayed(const Duration(seconds: 1));
    }
  }
}
