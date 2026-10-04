import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '/helpers/AppTheme.dart';

// ---------- Data models ----------

class _FlaggedStudent {
  final String examId;
  final String examTitle;
  final String uid;
  final String name;
  final int cheatingCount;
  final String status;

  const _FlaggedStudent({
    required this.examId,
    required this.examTitle,
    required this.uid,
    required this.name,
    required this.cheatingCount,
    required this.status,
  });
}

class _DashboardData {
  final int totalStudents;
  final int ongoingExams;
  final int totalFlagged;              // NEW: all flagged, used by the card
  final List<_FlaggedStudent> flagged; // only what the table shows

  const _DashboardData({
    required this.totalStudents,
    required this.ongoingExams,
    required this.totalFlagged,
    required this.flagged,
  });

  int get flaggedStudents => totalFlagged; // was flagged.length
}

// ---------- Page ----------

class TeacherDashboardPage extends StatefulWidget {
  final String teacherId;
  const TeacherDashboardPage({super.key, required this.teacherId});

  @override
  State<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends State<TeacherDashboardPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // uid -> display name (so we don't re-read users/{uid} on every refresh)
  final Map<String, String> _nameCache = {};
  static const int _tableLimit = 5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db
            .collection('exams')
            .where('teacherId', isEqualTo: widget.teacherId)
            .snapshots(),
        builder: (context, examSnapshot) {
          if (examSnapshot.hasError) {
            return Center(
              child: AppTheme.emptyCard(
                Icons.error_outline,
                'Could not load exams.\n${examSnapshot.error}',
              ),
            );
          }
          if (!examSnapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            );
          }

          final exams = examSnapshot.data!.docs;

          return StreamBuilder<_DashboardData>(
            stream: _aggregateStreams(exams),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent),
                );
              }
              return _buildMainContent(snapshot.data!);
            },
          );
        },
      ),
    );
  }

  // ---------- Layout ----------

  Widget _buildMainContent(_DashboardData data) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 850;
        final pad = constraints.maxWidth < 500 ? 16.0 : 24.0;
        final contentWidth = constraints.maxWidth - pad * 2;

        final monitoring = _buildMonitoringPanel(data.flagged, contentWidth);
        final status = _buildStatusPanel(data);

        return AppTheme.noScrollbars(
          context,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHero(),
                const SizedBox(height: 20),
                _buildMetricCards(contentWidth, data),
                const SizedBox(height: 24),
                if (compact) ...[
                  monitoring,
                  const SizedBox(height: 16),
                  status,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: monitoring),
                      const SizedBox(width: 16),
                      Expanded(child: status),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.heroDecoration(),
      child: Row(
        children: [
          AppTheme.appBarIcon(Icons.dashboard_rounded),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Teacher Dashboard',
                  style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                AppTheme.pill('LIVE EXAM MONITORING'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCards(double width, _DashboardData data) {
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
          child: AppTheme.statCard(
            icon: Icons.people,
            title: 'Total Students',
            count: data.totalStudents,
            color: AppTheme.accent,
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: AppTheme.statCard(
            icon: Icons.timer,
            title: 'Ongoing Exams',
            count: data.ongoingExams,
            color: Colors.orange,
          ),
        ),
        SizedBox(
          width: cardWidth,
          child: AppTheme.statCard(
            icon: Icons.warning_amber_rounded,
            title: 'Flagged Students',
            count: data.flaggedStudents,
            color: AppTheme.error,
          ),
        ),
      ],
    );
  }

  Widget _buildMonitoringPanel(List<_FlaggedStudent> flagged, double width) {
  Widget body;

  if (flagged.isEmpty) {
    body = AppTheme.emptyCard(
      Icons.verified_user_outlined,
      'No flagged students right now',
    );
  } else {
    body = LayoutBuilder(
      builder: (context, box) {
        // Fit to the card: hide the Exam column when it's narrow
        final showExam = box.maxWidth >= 520;

        final headers = <String>[
          'STUDENT',
          if (showExam) 'EXAM',
          'STRIKES',
          'STATUS',
          'ACTION',
        ];

        final columnWidths = <int, TableColumnWidth>{
          0: const FlexColumnWidth(2.2),
          if (showExam) 1: const FlexColumnWidth(2),
          (showExam ? 2 : 1): const FlexColumnWidth(1.1),
          (showExam ? 3 : 2): const FlexColumnWidth(1.6),
          (showExam ? 4 : 3): const FlexColumnWidth(1.6),
        };

        final rows = <List<Widget>>[
          for (final s in flagged)
            [
              AppTheme.tableCell(s.name),
              if (showExam)
                AppTheme.tableCell(s.examTitle, color: AppTheme.mutedText),
              AppTheme.tableCell(
                s.cheatingCount.toString(),
                color: AppTheme.error,
                weight: FontWeight.bold,
              ),
              AppTheme.statusChip(s.status, successValue: 'completed'),
              Center(
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => _showReviewDialog(s),
                  child: const Text('Review'),
                ),
              ),
            ],
        ];

        return AppTheme.tableCard(
          headers: headers,
          columnWidths: columnWidths,
          rows: rows,
          maxHeight: 420,
        );
      },
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppTheme.sectionHeader(Icons.sensors, 'Real-time Monitoring & Flags'),
      body,
    ],
  );
}

  Widget _buildStatusPanel(_DashboardData data) {
    final total = data.totalStudents;
    final clean = math.max(total - data.flaggedStudents, 0);
    final cleanRatio = total > 0 ? clean / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTheme.sectionHeader(Icons.groups_2_outlined, 'Active Taking Status'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$total students connected',
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: total > 0 ? cleanRatio : 0.0,
                  backgroundColor: total > 0
                      ? AppTheme.error.withOpacity(0.5)
                      : Colors.white.withOpacity(0.08),
                  valueColor: const AlwaysStoppedAnimation(AppTheme.success),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _legendDot(AppTheme.success),
                  const SizedBox(width: 6),
                  Text('$clean clean',
                      style: const TextStyle(
                          color: AppTheme.mutedText, fontSize: 12)),
                  const SizedBox(width: 16),
                  _legendDot(AppTheme.error),
                  const SizedBox(width: 6),
                  Text('${data.flaggedStudents} flagged',
                      style: const TextStyle(
                          color: AppTheme.mutedText, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _legendDot(Color c) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  // ---------- Review / preview dialog ----------

  void _showReviewDialog(_FlaggedStudent s) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
          decoration: BoxDecoration(
            color: AppTheme.bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.name,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, color: AppTheme.mutedText),
                  ),
                ],
              ),
              Text(
                '${s.examTitle}  •  ${s.cheatingCount} strike(s)',
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.25)),
                ),
                child: const Text(
                  'Each clip is about 3 seconds long. The strike number(s) '
                  'shown on a clip are the cheat count(s) that happened '
                  'during that clip (e.g. "#3 – #5").',
                  style: TextStyle(color: AppTheme.text, fontSize: 12.5),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(child: _buildClipList(s)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClipList(_FlaggedStudent s) {
    final clipsStream = _db
        .collection('examResults')
        .doc(s.examId)
        .collection('students')
        .doc(s.uid)
        .collection('cheatClips')
        .orderBy('number')
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: clipsStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return AppTheme.emptyCard(
              Icons.error_outline, 'Could not load clips.\n${snap.error}');
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            ),
          );
        }

        final clips = snap.data!.docs;
        if (clips.isEmpty) {
          return AppTheme.emptyCard(
              Icons.videocam_off_outlined, 'No video clips recorded');
        }

        return ListView.separated(
          shrinkWrap: true,
          itemCount: clips.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _buildClipTile(clips[i].data()),
        );
      },
    );
  }

  Widget _buildClipTile(Map<String, dynamic> clip) {
    final number = clip['number'] ?? '-';
    final start = clip['startCheatCount'];
    final end = clip['endCheatCount'] ?? clip['cheatCount'];
    final strikeLabel = (start != null && end != null && start != end)
        ? '#$start – #$end'
        : '#${end ?? '-'}';

    final occurred = clip['occurredAt'];
    String when = '';
    if (occurred is Timestamp) {
      final d = occurred.toDate();
      String p(int v) => v.toString().padLeft(2, '0');
      when = '${d.year}-${p(d.month)}-${p(d.day)}  ${p(d.hour)}:${p(d.minute)}:${p(d.second)}';
    }

    final files = (clip['files'] as Map?) ?? const {};
    final screenPath = (files['screen'] as Map?)?['path'] as String?;
    final cameraPath = (files['camera'] as Map?)?['path'] as String?;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Clip $number',
                style: const TextStyle(
                  color: AppTheme.text,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              AppTheme.pill('STRIKE $strikeLabel'),
            ],
          ),
          if (when.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(when,
                style: const TextStyle(
                    color: AppTheme.mutedText, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _clipButton('Screen', Icons.desktop_windows_outlined, screenPath),
              _clipButton('Camera', Icons.videocam_outlined, cameraPath),
            ],
          ),
        ],
      ),
    );
  }

  Widget _clipButton(String label, IconData icon, String? path) {
    if (path == null || path.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$label: no video',
          style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
        ),
      );
    }

    return ElevatedButton.icon(
      style: AppTheme.primaryButton(),
      onPressed: () => _openClip(path),
      icon: Icon(icon, size: 18),
      label: Text('View $label'),
    );
  }

  Future<void> _openClip(String storagePath) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await FirebaseStorage.instance.ref(storagePath).getDownloadURL();
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) throw 'Could not open the video link';
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: AppTheme.error,
          content: Text('Could not open clip: $e'),
        ),
      );
    }
  }

  // ---------- Data logic ----------

  Future<String> _resolveName(String uid, Map<String, dynamic> studentData) async {
    final inDoc = (studentData['studentName'] ??
            studentData['name'] ??
            studentData['fullName'])
        ?.toString();
    if (inDoc != null && inDoc.trim().isNotEmpty) {
      _nameCache[uid] = inDoc;
      return inDoc;
    }

    final cached = _nameCache[uid];
    if (cached != null) return cached;

    try {
      final userDoc = await _db.collection('users').doc(uid).get();
      final u = userDoc.data();
      final n = (u?['name'] ?? u?['fullName'] ?? u?['displayName'])?.toString();
      if (n != null && n.trim().isNotEmpty) {
        _nameCache[uid] = n;
        return n;
      }
    } catch (_) {}

    _nameCache[uid] = uid;
    return uid;
  }

  Stream<_DashboardData> _aggregateStreams(
  List<QueryDocumentSnapshot<Map<String, dynamic>>> exams,
) async* {
  while (true) {
    final now = DateTime.now();

    int totalStudents = 0;
    int totalOngoing = 0;
    int totalFlagged = 0;

    DateTime? newestStart;
    List<_FlaggedStudent> newestFlagged = [];

    for (final exam in exams) {
      final examData = exam.data();
      final startTs = examData['startTime'];
      final endTs = examData['endTime'];
      if (startTs is! Timestamp || endTs is! Timestamp) continue;

      final start = startTs.toDate();
      final end = endTs.toDate();
      if (!(now.isAfter(start) && now.isBefore(end))) continue;

      totalOngoing += 1;

      final studentSnap = await _db
          .collection('examResults')
          .doc(exam.id)
          .collection('students')
          .get();
      totalStudents += studentSnap.size;

      final examTitle =
          (examData['title'] ?? examData['examTitle'] ?? examData['name'] ?? 'Exam')
              .toString();

      final examFlagged = <_FlaggedStudent>[];
      for (final doc in studentSnap.docs) {
        final d = doc.data();
        final count = (d['cheatingCount'] as num?)?.toInt() ?? 0;
        if (count <= 0) continue;

        examFlagged.add(_FlaggedStudent(
          examId: exam.id,
          examTitle: examTitle,
          uid: doc.id,
          name: await _resolveName(doc.id, d),
          cheatingCount: count,
          status: (d['status'] ?? 'in-progress').toString(),
        ));
      }
      totalFlagged += examFlagged.length;

      // Only keep the NEWEST exam that actually has students
      if (studentSnap.size > 0 &&
          (newestStart == null || start.isAfter(newestStart))) {
        newestStart = start;
        newestFlagged = examFlagged;
      }
    }

    // Highest cheat count first, then cut to the limit
    newestFlagged.sort((a, b) => b.cheatingCount.compareTo(a.cheatingCount));
    final top = newestFlagged.take(_tableLimit).toList();

    yield _DashboardData(
      totalStudents: totalStudents,
      ongoingExams: totalOngoing,
      totalFlagged: totalFlagged,
      flagged: top,
    );

    await Future.delayed(const Duration(seconds: 5));
  }
}
}