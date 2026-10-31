import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '/helpers/app_theme.dart';

// ---------- Data models ----------

enum _ClipKind {
  camera('camera', 'Camera', Icons.videocam_outlined),
  screen('screen', 'Screen recording', Icons.desktop_windows_outlined);

  final String key;
  final String label;
  final IconData icon;

  const _ClipKind(this.key, this.label, this.icon);
}

class _FlaggedStudent {
  final String examId;
  final String examTitle;
  final String uid;
  final String name;
  final int cheatingCount;
  final String status;
  final bool isPc;

  const _FlaggedStudent({
    required this.examId,
    required this.examTitle,
    required this.uid,
    required this.name,
    required this.cheatingCount,
    required this.status,
    required this.isPc,
  });
}

class _DashboardData {
  final int totalStudents;
  final int ongoingExams;
  final int totalExams;
  final int examsToday;
  final int examsThisWeek;
  final int upcomingExams;
  final List<String> ongoingExamIds;
  final int totalFlagged; // NEW: all flagged, used by the card
  final List<_FlaggedStudent> flagged; // only what the table shows

  const _DashboardData({
    required this.totalStudents,
    required this.ongoingExams,
    required this.totalExams,
    required this.examsToday,
    required this.examsThisWeek,
    required this.upcomingExams,
    required this.ongoingExamIds,
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
  List<String> _presenceExamIds = const [];
  Stream<Map<String, int>>? _presenceStream;

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
              if (snapshot.hasError) {
                return Center(
                  child: AppTheme.emptyCard(
                    Icons.error_outline,
                    'Could not load dashboard data.\n${snapshot.error}',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent),
                );
              }
              final data = snapshot.data!;
              return _buildMainContent(
                data,
                _presenceCounts(data.ongoingExamIds),
              );
            },
          );
        },
      ),
    );
  }

  // ---------- Layout ----------

  Widget _buildMainContent(
    _DashboardData data,
    Stream<Map<String, int>> presenceStream,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 850;
        final pad = constraints.maxWidth < 500 ? 16.0 : 24.0;
        final contentWidth = constraints.maxWidth - pad * 2;

        final monitoring = _buildMonitoringPanel(data.flagged, contentWidth);
        final status = _buildStatusPanel(data, presenceStream);

        return AppTheme.noScrollbars(
          context,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHero(),
                const SizedBox(height: 20),
                _buildMetricCards(contentWidth, data, presenceStream),
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

  Widget _buildMetricCards(
    double width,
    _DashboardData data,
    Stream<Map<String, int>> presenceStream,
  ) {
    return StreamBuilder<Map<String, int>>(
      stream: presenceStream,
      initialData: const {'taking': 0, 'offline': 0, 'disconnected': 0},
      builder: (context, presenceSnapshot) {
        final taking = presenceSnapshot.hasError
            ? null
            : (presenceSnapshot.data?['taking'] ?? 0);
        const spacing = 16.0;
        final cardWidth = (width - spacing * 2) / 3;
        final takingColor = data.ongoingExams > 0
            ? AppTheme.success
            : AppTheme.mutedText;

        Widget card({
          required IconData icon,
          required String title,
          required String value,
          required Color color,
        }) {
          return SizedBox(
            width: cardWidth,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.mutedText,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (presenceSnapshot.hasError)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Unable to load live exam presence: ${presenceSnapshot.error}',
                  style: const TextStyle(color: AppTheme.error),
                ),
              ),
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                card(
                  icon: Icons.assignment_outlined,
                  title: 'My Exams',
                  value: '${data.totalExams}',
                  color: AppTheme.accent,
                ),
                card(
                  icon: Icons.play_circle_outline,
                  title: 'Ongoing Exams',
                  value: '${data.ongoingExams}',
                  color: Colors.orange,
                ),

                card(
                  icon: Icons.edit_note_rounded,
                  title: 'Taking Exam Now',
                  value: taking?.toString() ?? '—',
                  color: takingColor,
                ),
                card(
                  icon: Icons.today_outlined,
                  title: 'Exams Today',
                  value: '${data.examsToday}',
                  color: AppTheme.accent,
                ),
                card(
                  icon: Icons.people_outline,
                  title: 'Attempts in Live Exams',
                  value: '${data.totalStudents}',
                  color: AppTheme.success,
                ),
                card(
                  icon: Icons.warning_amber_rounded,
                  title: 'Flagged Students',
                  value: '${data.flaggedStudents}',
                  color: AppTheme.error,
                ),
              ],
            ),
          ],
        );
      },
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
          final compact = box.maxWidth < 520;

          final rows = <List<Widget>>[
            for (final s in flagged)
              [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 6 : 8,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        s.examTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.mutedText,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

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
            headers: const ['STUDENT / EXAM', 'STRIKES', 'STATUS', 'ACTION'],
            columnWidths: {
              0: const FlexColumnWidth(2.2),
              1: const FlexColumnWidth(1.1),
              2: const FlexColumnWidth(1.6),
              3: const FlexColumnWidth(1.6),
            },
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

  Widget _buildStatusPanel(
    _DashboardData data,
    Stream<Map<String, int>> presenceStream,
  ) {
    final takingColor = data.ongoingExams > 0
        ? AppTheme.success
        : AppTheme.mutedText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: takingColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.groups_2_outlined,
                  size: 16,
                  color: takingColor,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Active Taking Status',
                style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ],
          ),
        ),
        StreamBuilder<Map<String, int>>(
          stream: presenceStream,
          initialData: const {'taking': 0, 'offline': 0, 'disconnected': 0},
          builder: (context, snapshot) {
            final taking = snapshot.data?['taking'] ?? 0;
            final offline = snapshot.data?['offline'] ?? 0;
            final disconnected = snapshot.data?['disconnected'] ?? 0;
            final total = taking + offline + disconnected;
            final takingRatio = total > 0 ? taking / total : 0.0;
            final hasOngoingExams = data.ongoingExams > 0;
            final offlineColor = hasOngoingExams
                ? const Color(0xFFFBBF24)
                : AppTheme.mutedText;
            final disconnectedColor = hasOngoingExams
                ? AppTheme.error
                : AppTheme.mutedText;
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.hasError
                        ? 'Unable to load live exam presence'
                        : hasOngoingExams
                        ? '$taking students taking an exam'
                        : 'No exam is currently ongoing',
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.hasError)
                    Text(
                      '${snapshot.error}',
                      style: const TextStyle(
                        color: AppTheme.error,
                        fontSize: 12,
                      ),
                    )
                  else ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        minHeight: 8,
                        value: takingRatio,
                        backgroundColor: offline + disconnected > 0
                            ? offlineColor.withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.08),
                        valueColor: AlwaysStoppedAnimation(takingColor),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _legendDot(takingColor),
                            const SizedBox(width: 6),
                            Text(
                              '$taking taking',
                              style: const TextStyle(
                                color: AppTheme.mutedText,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _legendDot(offlineColor),
                            const SizedBox(width: 6),
                            Text(
                              '$offline offline',
                              style: const TextStyle(
                                color: AppTheme.mutedText,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _legendDot(disconnectedColor),
                            const SizedBox(width: 6),
                            Text(
                              '$disconnected disconnected',
                              style: const TextStyle(
                                color: AppTheme.mutedText,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  if (!hasOngoingExams && !snapshot.hasError) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Taking status will be available when an exam starts.',
                      style: TextStyle(color: AppTheme.mutedText, fontSize: 12),
                    ),
                  ],
                ],
              ),
            );
          },
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
    var selectedKind = _ClipKind.camera;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
            decoration: BoxDecoration(
              color: AppTheme.bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _clipKindButton(
                      kind: _ClipKind.camera,
                      selected: selectedKind == _ClipKind.camera,
                      onPressed: () =>
                          setDialogState(() => selectedKind = _ClipKind.camera),
                    ),
                    if (s.isPc) ...[
                      const SizedBox(width: 6),
                      _clipKindButton(
                        kind: _ClipKind.screen,
                        selected: selectedKind == _ClipKind.screen,
                        onPressed: () => setDialogState(
                          () => selectedKind = _ClipKind.screen,
                        ),
                      ),
                    ],
                    IconButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      icon: const Icon(Icons.close, color: AppTheme.mutedText),
                    ),
                  ],
                ),
                Text(
                  '${s.examTitle}  •  ${s.cheatingCount} strike(s)',
                  style: const TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Text(
                    'Each clip is about 3 seconds long. The strike number(s) '
                    'shown on a clip are the cheat count(s) that happened '
                    'during that clip (e.g. "#3 – #5").',
                    style: TextStyle(color: AppTheme.text, fontSize: 12.5),
                  ),
                ),
                const SizedBox(height: 14),
                Flexible(child: _buildClipList(s, selectedKind)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _clipKindButton({
    required _ClipKind kind,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    final color = selected ? AppTheme.accent : AppTheme.mutedText;
    return Tooltip(
      message: kind.label,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          foregroundColor: color,
          backgroundColor: selected
              ? AppTheme.accent.withValues(alpha: 0.15)
              : Colors.transparent,
          side: BorderSide(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.12),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: Icon(kind.icon, size: 18),
      ),
    );
  }

  Widget _buildClipList(_FlaggedStudent s, _ClipKind kind) {
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
            Icons.error_outline,
            'Could not load clips.\n${snap.error}',
          );
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
            Icons.videocam_off_outlined,
            'No video clips recorded',
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          itemCount: clips.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _buildClipTile(clips[index].data(), kind),
        );
      },
    );
  }

  Widget _buildClipTile(Map<String, dynamic> clip, _ClipKind kind) {
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
      when =
          '${d.year}-${p(d.month)}-${p(d.day)}  ${p(d.hour)}:${p(d.minute)}:${p(d.second)}';
    }

    final files = (clip['files'] as Map?) ?? const {};
    final path = (files[kind.key] as Map?)?['path'] as String?;

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
            Text(
              when,
              style: const TextStyle(color: AppTheme.mutedText, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          _clipButton(kind.label, kind.icon, path),
        ],
      ),
    );
  }

  Widget _clipButton(String label, IconData icon, String? path) {
    if (path == null || path.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
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
      final url = await FirebaseStorage.instance
          .ref(storagePath)
          .getDownloadURL();
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

  Future<String> _resolveName(
    String uid,
    Map<String, dynamic> studentData,
  ) async {
    final inDoc =
        (studentData['studentName'] ??
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
      final dayStart = DateTime(now.year, now.month, now.day);
      final weekStart = dayStart.subtract(Duration(days: dayStart.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 7));

      int totalStudents = 0;
      int totalOngoing = 0;
      int examsToday = 0;
      int examsThisWeek = 0;
      int upcomingExams = 0;
      int totalFlagged = 0;

      final flaggedStudents = <_FlaggedStudent>[];
      final ongoingExamIds = <String>[];

      for (final exam in exams) {
        final examData = exam.data();
        final startTs = examData['startTime'];
        final endTs = examData['endTime'];
        final start = startTs is Timestamp ? startTs.toDate() : null;
        final end = endTs is Timestamp ? endTs.toDate() : null;
        final rawStatus = (examData['status'] ?? '').toString().toLowerCase();
        final isFinished =
            [
              'finished',
              'finish',
              'completed',
              'complete',
            ].contains(rawStatus) ||
            (end != null && !now.isBefore(end));
        final monitoringActive =
            !isFinished &&
            examData['monitoringEnabled'] == true &&
            start != null &&
            end != null &&
            !now.isBefore(start) &&
            now.isBefore(end);
        final isOngoing =
            start != null &&
            end != null &&
            !isFinished &&
            (['ongoing', 'on-going', 'on going'].contains(rawStatus) ||
                monitoringActive);
        if (isOngoing) totalOngoing++;
        if (!isOngoing && !isFinished && end != null && end.isAfter(now)) {
          upcomingExams++;
        }
        if (start != null && _isSameDay(start, now)) examsToday++;
        if (start != null &&
            !start.isBefore(weekStart) &&
            start.isBefore(weekEnd)) {
          examsThisWeek++;
        }
        if (monitoringActive) ongoingExamIds.add(exam.id);

        final studentSnap = await _db
            .collection('examResults')
            .doc(exam.id)
            .collection('students')
            .get();
        if (monitoringActive) totalStudents += studentSnap.size;

        final examTitle =
            (examData['title'] ??
                    examData['examTitle'] ??
                    examData['name'] ??
                    'Exam')
                .toString();

        final examFlagged = <_FlaggedStudent>[];
        for (final doc in studentSnap.docs) {
          final d = doc.data();
          final count = (d['cheatingCount'] as num?)?.toInt() ?? 0;
          if (count <= 0) continue;

          examFlagged.add(
            _FlaggedStudent(
              examId: exam.id,
              examTitle: examTitle,
              uid: doc.id,
              name: await _resolveName(doc.id, d),
              cheatingCount: count,
              status: (d['status'] ?? 'in-progress').toString(),
              isPc: examData['isPc'] is bool ? examData['isPc'] as bool : true,
            ),
          );
        }
        totalFlagged += examFlagged.length;
        flaggedStudents.addAll(examFlagged);
      }

      flaggedStudents.sort(
        (a, b) => b.cheatingCount.compareTo(a.cheatingCount),
      );

      yield _DashboardData(
        totalStudents: totalStudents,
        ongoingExams: totalOngoing,
        totalExams: exams.length,
        examsToday: examsToday,
        examsThisWeek: examsThisWeek,
        upcomingExams: upcomingExams,
        ongoingExamIds: ongoingExamIds,
        totalFlagged: totalFlagged,
        flagged: flaggedStudents,
      );

      await Future.delayed(const Duration(seconds: 5));
    }
  }

  bool _isSameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  Stream<Map<String, int>> _presenceCounts(List<String> examIds) {
    final ids = List<String>.of(examIds)..sort();
    if (_presenceStream != null &&
        ids.length == _presenceExamIds.length &&
        List.generate(
          ids.length,
          (index) => ids[index] == _presenceExamIds[index],
        ).every((same) => same)) {
      return _presenceStream!;
    }

    _presenceExamIds = ids;
    _presenceStream = _listenToPresence(ids);
    return _presenceStream!;
  }

  Stream<Map<String, int>> _listenToPresence(List<String> examIds) {
    final latest = <String, Object?>{};
    final subscriptions = <StreamSubscription<DatabaseEvent>>[];
    late final StreamController<Map<String, int>> controller;

    void emit() {
      final cutoff =
          DateTime.now().millisecondsSinceEpoch -
          const Duration(minutes: 3).inMilliseconds;
      var taking = 0;
      var offline = 0;
      var disconnected = 0;
      for (final examValue in latest.values) {
        if (examValue is! Map) continue;
        for (final student in examValue.values) {
          if (student is! Map) continue;
          if (student['status'] != 'in-progress') continue;
          final lastSeen = student['lastSeen'];
          final fresh = lastSeen is num && lastSeen >= cutoff;
          if (student['online'] == true && fresh) {
            taking++;
          } else if (student['online'] == false && fresh) {
            offline++;
          } else {
            disconnected++;
          }
        }
      }
      if (!controller.isClosed) {
        controller.add({
          'taking': taking,
          'offline': offline,
          'disconnected': disconnected,
        });
      }
    }

    controller = StreamController<Map<String, int>>.broadcast(
      onListen: () {
        for (final id in examIds) {
          subscriptions.add(
            FirebaseDatabase.instance
                .ref('examPresence/$id')
                .onValue
                .listen(
                  (event) {
                    latest[id] = event.snapshot.value;
                    emit();
                  },
                  onError: (Object error, StackTrace stackTrace) {
                    if (!controller.isClosed) {
                      controller.addError(error, stackTrace);
                    }
                  },
                ),
          );
        }
        if (examIds.isEmpty) emit();
      },
      onCancel: () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
        await controller.close();
      },
    );
    return controller.stream;
  }
}
