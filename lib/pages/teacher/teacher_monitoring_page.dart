import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../helpers/AppTheme.dart';

class TeacherMonitoringPage extends StatefulWidget {
  final String teacherId;
  const TeacherMonitoringPage({super.key, required this.teacherId});
  @override
  State<TeacherMonitoringPage> createState() => _TeacherMonitoringPageState();
}

class _TeacherMonitoringPageState extends State<TeacherMonitoringPage> {
  final _db = FirebaseFirestore.instance;
  final Set<String> _expandedStudentIds = <String>{};
  @override
  Widget build(BuildContext context) {
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
              'Monitoring Exams',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db
            .collection('exams')
            .where('teacherId', isEqualTo: widget.teacherId)
            .snapshots(),
        builder: (context, examSnapshot) {
          if (examSnapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            );
          }
          if (examSnapshot.hasError) {
            return _emptyState(
              Icons.error_outline,
              'Unable to load exams',
              'Please check your connection and try again.',
            );
          }
          final exams = examSnapshot.data?.docs ?? [];
          if (exams.isEmpty) {
            return _emptyState(
              Icons.assignment_outlined,
              'No exams found',
              'There are currently no exams assigned to you.',
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildOverviewHeader(exams.length),
                    const SizedBox(height: 16),
                    ...exams.map((exam) => _buildExamCard(exam)),
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

  Widget _buildOverviewHeader(int examCount) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.analytics_outlined,
              color: AppTheme.accent,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Exam Monitoring',
                  style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$examCount ${examCount == 1 ? 'exam' : 'exams'} available for monitoring',
                  style: TextStyle(color: AppTheme.mutedText, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamCard(QueryDocumentSnapshot exam) {
    final data = exam.data() as Map<String, dynamic>;
    final subject = (data['subject'] ?? 'Unknown Subject').toString();
    final program = (data['program'] ?? '').toString();
    final yearBlock = (data['yearBlock'] ?? '').toString();
    final status = (data['status'] ?? 'ongoing').toString().toLowerCase();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: AppTheme.cardDecoration(),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          childrenPadding: const EdgeInsets.only(bottom: 10),
          iconColor: AppTheme.accent,
          collapsedIconColor: AppTheme.mutedText,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  subject,
                  style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _statusBadge(status),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              [
                if (program.isNotEmpty) program,
                if (yearBlock.isNotEmpty) yearBlock,
              ].join(' • '),
              style: TextStyle(color: AppTheme.mutedText, fontSize: 13),
            ),
          ),
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('examResults')
                  .doc(exam.id)
                  .collection('students')
                  .snapshots(),
              builder: (context, studentSnapshot) {
                if (studentSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: CircularProgressIndicator(color: AppTheme.accent),
                    ),
                  );
                }
                if (studentSnapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      'Unable to load student monitoring data.',
                      style: TextStyle(color: AppTheme.mutedText),
                    ),
                  );
                }
                final students = studentSnapshot.data?.docs ?? [];
                if (students.isEmpty) {
                  return Container(
                    margin: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppTheme.bg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.accent.withOpacity(0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.people_outline, color: AppTheme.mutedText),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No students have taken this exam yet.',
                            style: TextStyle(color: AppTheme.mutedText),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: students.map((studentDoc) {
                    return _buildStudentCard(exam.id, studentDoc);
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentCard(String examId, QueryDocumentSnapshot studentDoc) {
    final data = studentDoc.data() as Map<String, dynamic>;
    final studentId = (data['studentId'] ?? studentDoc.id).toString();
    final status = (data['status'] ?? 'in-progress').toString();
    final cheatingCount = int.tryParse('${data['cheatingCount'] ?? 0}') ?? 0;
    final normalizedStatus = status.toLowerCase();
    final isStopped =
        normalizedStatus == 'stopped' || normalizedStatus == 'incomplete';
    final isExpanded = _expandedStudentIds.contains(studentDoc.id);
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 4, 18, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isStopped
              ? Colors.redAccent.withOpacity(0.30)
              : AppTheme.accent.withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _studentAvatar(isStopped, cheatingCount),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      studentId,
                      style: TextStyle(
                        color: AppTheme.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 7),
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
                  if (value == 'stop') {
                    _confirmStopStudent(examId, studentDoc.id, studentId);
                  } else if (value == 'retake') {
                    _confirmRetake(examId, studentDoc.id, studentId);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'stop',
                    child: Row(
                      children: [
                        const Icon(
                          Icons.stop_circle_outlined,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Stop Exam',
                          style: TextStyle(color: AppTheme.text),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'retake',
                    child: Row(
                      children: [
                        Icon(
                          Icons.restart_alt,
                          color: AppTheme.accent,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Allow Retake',
                          style: TextStyle(color: AppTheme.text),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedStudentIds.remove(studentDoc.id);
                } else {
                  _expandedStudentIds.add(studentDoc.id);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: AppTheme.header,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.accent.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 19,
                    color: AppTheme.accent,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Detailed Logs',
                      style: TextStyle(
                        color: AppTheme.text,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppTheme.mutedText,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const SizedBox(height: 12),
            _buildDetailedLogs(data, cheatingCount),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailedLogs(Map<String, dynamic> data, int cheatingCount) {
    if (cheatingCount == 0) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.header,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: AppTheme.accent, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'No cheating incidents recorded yet.',
                style: TextStyle(color: AppTheme.mutedText, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.header,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Colors.orangeAccent,
            size: 20,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '$cheatingCount violation${cheatingCount == 1 ? '' : 's'} recorded.',
              style: TextStyle(color: AppTheme.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _studentAvatar(bool isStopped, int cheatingCount) {
    final Color iconColor;
    if (isStopped) {
      iconColor = Colors.redAccent;
    } else if (cheatingCount > 0) {
      iconColor = Colors.orangeAccent;
    } else {
      iconColor = AppTheme.accent;
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: iconColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        isStopped ? Icons.block_outlined : Icons.person_outline,
        color: iconColor,
        size: 23,
      ),
    );
  }

  Widget _statusBadge(String status) {
    final normalized = status.toLowerCase();
    Color color;
    String label;
    IconData icon;
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
          Icon(icon, size: 13, color: color),
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
            size: 13,
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

  Widget _emptyState(IconData icon, String title, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(28),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 46, color: AppTheme.mutedText),
              const SizedBox(height: 14),
              Text(
                title,
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
        ),
      ),
    );
  }

  Future<void> _confirmStopStudent(
    String examId,
    String studentDocId,
    String studentId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.header,
          title: Text(
            'Stop Exam?',
            style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600),
          ),
          content: Text(
            'This will stop the exam session for student $studentId.',
            style: TextStyle(color: AppTheme.mutedText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppTheme.mutedText),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Stop Exam'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _stopStudent(examId, studentDocId);
  }

  Future<void> _confirmRetake(
    String examId,
    String studentDocId,
    String studentId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.header,
          title: Text(
            'Allow Retake?',
            style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600),
          ),
          content: Text(
            'This will remove the current exam result for student $studentId and allow a new attempt.',
            style: TextStyle(color: AppTheme.mutedText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppTheme.mutedText),
              ),
            ),
            ElevatedButton(
              style: AppTheme.primaryButton(),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Allow Retake'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _allowRetake(examId, studentDocId);
  }

  Future<void> _stopStudent(String examId, String studentId) async {
    try {
      await _db
          .collection('examResults')
          .doc(examId)
          .collection('students')
          .doc(studentId)
          .update({'currentIndex': 'stopped', 'status': 'incomplete'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student exam session stopped.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to stop student: $e')));
    }
  }

  Future<void> _allowRetake(String examId, String studentId) async {
    try {
      await _db
          .collection('examResults')
          .doc(examId)
          .collection('students')
          .doc(studentId)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Student is now allowed to retake the exam.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to allow retake: $e')));
    }
  }
}
