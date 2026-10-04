import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../helpers/AppTheme.dart';

class ExamMonitoringPage extends StatelessWidget {
  final String examId;
  const ExamMonitoringPage({super.key, required this.examId});
  Color _getStatusColor(String status, int cheatingCount) {
    final normalized = status.toLowerCase();
    if (normalized == 'stopped' || normalized == 'incomplete') {
      return Colors.redAccent;
    }
    if (cheatingCount > 0) {
      return Colors.orangeAccent;
    }
    return Colors.greenAccent;
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 80,
        titleSpacing: 16,
        backgroundColor: AppTheme.header,
        foregroundColor: AppTheme.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            AppTheme.appBarIcon(Icons.monitor_heart_outlined),
            const SizedBox(width: 12),
            const Text(
              'Exam Monitoring',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: db
            .collection('exams')
            .doc(examId)
            .collection('students')
            .snapshots(),
        builder: (context, studentSnapshot) {
          if (studentSnapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            );
          }
          if (studentSnapshot.hasError) {
            return _emptyState(
              context,
              Icons.error_outline,
              'Unable to load monitoring data',
              'Please check your connection and try again.',
            );
          }
          final students = studentSnapshot.data?.docs ?? [];
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSummaryCard(students),
                    const SizedBox(height: 16),
                    if (students.isEmpty)
                      _emptyState(
                        context,
                        Icons.people_outline,
                        'No students to monitor',
                        'Students will appear here once they start this exam.',
                      )
                    else
                      ...students.map(
                        (student) => _buildStudentCard(context, db, student),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(List<QueryDocumentSnapshot> students) {
    int active = 0;
    int stopped = 0;
    int violations = 0;
    for (final student in students) {
      final data = student.data() as Map<String, dynamic>;
      final status = (data['status'] ?? 'active').toString().toLowerCase();
      final count = int.tryParse('${data['cheatingCount'] ?? 0}') ?? 0;
      violations += count;
      if (status == 'stopped' || status == 'incomplete') {
        stopped++;
      } else {
        active++;
      }
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTheme.sectionHeader(Icons.dashboard_outlined, 'Live Overview'),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final children = [
                _summaryItem(
                  Icons.people_outline,
                  'Students',
                  '${students.length}',
                  AppTheme.accent,
                ),
                _summaryItem(
                  Icons.play_circle_outline,
                  'Active',
                  '$active',
                  Colors.greenAccent,
                ),
                _summaryItem(
                  Icons.stop_circle_outlined,
                  'Stopped',
                  '$stopped',
                  Colors.redAccent,
                ),
                _summaryItem(
                  Icons.warning_amber_outlined,
                  'Violations',
                  '$violations',
                  Colors.orangeAccent,
                ),
              ];
              if (compact) {
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: children
                      .map(
                        (item) => SizedBox(
                          width: (constraints.maxWidth - 10) / 2,
                          child: item,
                        ),
                      )
                      .toList(),
                );
              }
              return Row(
                children: children
                    .map(
                      (item) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: item,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(color: AppTheme.mutedText, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentCard(
    BuildContext context,
    FirebaseFirestore db,
    QueryDocumentSnapshot student,
  ) {
    final data = student.data() as Map<String, dynamic>;
    final name = (data['name'] ?? 'Unknown Student').toString();
    final studentId = (data['studentId'] ?? student.id).toString();
    final status = (data['status'] ?? 'active').toString();
    final cheatingCount = int.tryParse('${data['cheatingCount'] ?? 0}') ?? 0;
    final statusColor = _getStatusColor(status, cheatingCount);
    final stopped =
        status.toLowerCase() == 'stopped' ||
        status.toLowerCase() == 'incomplete';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.header,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withOpacity(0.20)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              stopped ? Icons.block_outlined : Icons.person_outline,
              color: statusColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'ID: $studentId',
                  style: TextStyle(color: AppTheme.mutedText, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _statusBadge(status),
                    _violationBadge(cheatingCount),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: 'Student actions',
            icon: Icon(Icons.more_vert, color: AppTheme.mutedText),
            color: AppTheme.header,
            onSelected: (value) {
              _updateStudentStatus(db, student.id, value);
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'allowed_to_retake',
                child: Row(
                  children: [
                    Icon(Icons.restart_alt, color: AppTheme.accent, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Allow Retake',
                      style: TextStyle(color: AppTheme.text),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'stopped',
                child: Row(
                  children: [
                    const Icon(
                      Icons.stop_circle_outlined,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text('Stop Exam', style: TextStyle(color: AppTheme.text)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final normalized = status.toLowerCase();
    final Color color;
    final String label;
    final IconData icon;
    if (normalized == 'stopped' || normalized == 'incomplete') {
      color = Colors.redAccent;
      label = 'Stopped';
      icon = Icons.stop_circle_outlined;
    } else if (normalized == 'finished' || normalized == 'completed') {
      color = AppTheme.accent;
      label = 'Finished';
      icon = Icons.check_circle_outline;
    } else {
      color = Colors.greenAccent;
      label = 'Active';
      icon = Icons.circle;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _violationBadge(int count) {
    final color = count > 0 ? Colors.orangeAccent : AppTheme.mutedText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            count > 0 ? Icons.warning_amber_outlined : Icons.verified_outlined,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            count == 0
                ? 'No violations'
                : '$count violation${count == 1 ? '' : 's'}',
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(
    BuildContext context,
    IconData icon,
    String title,
    String message,
  ) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 46, color: AppTheme.mutedText),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.text,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.mutedText, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _updateStudentStatus(
    FirebaseFirestore db,
    String studentId,
    String status,
  ) async {
    try {
      await db
          .collection('exams')
          .doc(examId)
          .collection('students')
          .doc(studentId)
          .update({'status': status});
    } catch (e) {
      debugPrint('Error updating student status: $e');
    }
  }
}
