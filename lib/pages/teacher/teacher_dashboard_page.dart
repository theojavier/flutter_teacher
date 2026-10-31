import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '/helpers/AppTheme.dart';

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

  const _DashboardData({
    required this.totalStudents,
    required this.ongoingExams,
    required this.totalExams,
    required this.examsToday,
    required this.examsThisWeek,
    required this.upcomingExams,
    required this.ongoingExamIds,
  });
}

class TeacherDashboardPage extends StatefulWidget {
  final String teacherId;

  const TeacherDashboardPage({super.key, required this.teacherId});

  @override
  State<TeacherDashboardPage> createState() => _TeacherDashboardPageState();
}

class _TeacherDashboardPageState extends State<TeacherDashboardPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<String> _presenceExamIds = const [];
  Stream<Map<String, int>>? _presenceStream;

  Future<void> _openExamDialog(String examId, Map<String, dynamic> data) async {
    final result = await ExamFormDialog.show(
      context,
      docId: examId,
      existing: data,
    );
    if (!mounted || result == null) return;
    if (result.openQuestions) {
      context.go('/edit-question/${result.examId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dashboardPaper,
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
              child: CircularProgressIndicator(color: _dashboardBlue),
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
                  child: CircularProgressIndicator(color: _dashboardBlue),
                );
              }
              final data = snapshot.data!;
              return _buildMainContent(
                exams,
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
    List<QueryDocumentSnapshot<Map<String, dynamic>>> exams,
    _DashboardData data,
    Stream<Map<String, int>> presenceStream,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final pad = constraints.maxWidth >= 920
            ? 40.0
            : constraints.maxWidth < 500
            ? 16.0
            : 24.0;
        final contentWidth = constraints.maxWidth - pad * 2;
        final recentWidth = compact ? contentWidth : (contentWidth - 16) * 0.64;
        final wideTable = recentWidth >= 560;

        return AppTheme.noScrollbars(
          context,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1500),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, compact ? 24 : 38, pad, 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPageHeading(compact),
                    const SizedBox(height: 24),
                    _buildHero(constraints.maxWidth - pad * 2),
                    const SizedBox(height: 16),
                    _buildMetricCards(contentWidth, data, presenceStream),
                    const SizedBox(height: 16),
                    if (compact) ...[
                      _buildRecentExams(exams, wide: wideTable),
                      const SizedBox(height: 16),
                      _buildLiveActivity(data, presenceStream),
                    ] else
                      SizedBox(
                        height: 520,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 64,
                              child: _buildRecentExams(
                                exams,
                                wide: wideTable,
                                expand: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 36,
                              child: _buildLiveActivity(
                                data,
                                presenceStream,
                                expand: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPageHeading(bool compact) {
    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _dashboardButton(
          label: 'View exams',
          icon: Icons.arrow_outward_rounded,
          onPressed: () => context.go('/teacher-exams'),
        ),
        _dashboardButton(
          label: 'Live monitoring',
          icon: Icons.sensors_outlined,
          primary: true,
          onPressed: () => context.go('/teacher-monitoring'),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '01 / FACULTY WORKSPACE',
          style: TextStyle(
            color: _dashboardBlue,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Your teaching workspace.',
          style: TextStyle(
            color: _dashboardInk,
            fontSize: compact ? 34 : 46,
            fontWeight: FontWeight.w800,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 9),
        const Text(
          'Create assessments, follow exam activity, and review student flags.',
          style: TextStyle(color: _dashboardMuted, fontSize: 13, height: 1.6),
        ),
        const SizedBox(height: 17),
        actions,
      ],
    );
  }

  Widget _buildHero(double width) {
    final compact = width < 720;
    final copy = Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 22 : 34,
        25,
        compact ? 22 : 34,
        26,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, color: _dashboardBlue),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'FOTS PLATFORM',
                  style: TextStyle(
                    color: _dashboardInk,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
              ),
              const Text(
                'TEACHER / 2026',
                style: TextStyle(color: _dashboardMuted, fontSize: 9),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(height: 1, color: _dashboardInk),
          SizedBox(height: compact ? 24 : 36),
          const Text(
            'A SMARTER WAY TO TEACH',
            style: TextStyle(
              color: _dashboardBlue,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Create better.\nAssess smarter.',
            style: TextStyle(
              color: _dashboardInk,
              fontSize: compact ? 42 : 58,
              fontWeight: FontWeight.w800,
              height: 1.02,
            ),
          ),
          const SizedBox(height: 17),
          const Text(
            'Design assessments, keep an eye on sessions, and make informed decisions from your faculty workspace.',
            style: TextStyle(
              color: _dashboardMuted,
              fontSize: 13,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _dashboardButton(
                label: 'Create new exam',
                icon: Icons.add_rounded,
                primary: true,
                onPressed: () => context.go('/teacher-exams'),
              ),
              _dashboardButton(
                label: 'Open monitoring',
                icon: Icons.arrow_forward_rounded,
                onPressed: () => context.go('/teacher-monitoring'),
              ),
            ],
          ),
          const SizedBox(height: 23),
          const Divider(height: 1, color: _dashboardLine),
          const SizedBox(height: 13),
          const Row(
            children: [
              Text(
                'FACULTY ENGINE',
                style: TextStyle(
                  color: _dashboardInk,
                  fontSize: 9,
                  letterSpacing: 0.7,
                ),
              ),
              Spacer(),
              Text(
                'ASSESSMENT / MONITORING',
                style: TextStyle(color: _dashboardMuted, fontSize: 9),
              ),
            ],
          ),
        ],
      ),
    );

    final poster = Container(
      
      height: compact ? 320 : null,
       constraints: BoxConstraints(minHeight: compact ? 300 : 420),
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: _dashboardBlue,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_dashboardBlue, Color(0xFF0B2ABF)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Text(
                'FOTS / TEACHER SPACE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  letterSpacing: 0.7,
                ),
              ),
              Spacer(),
              Text(
                '[ FACULTY ]',
                style: TextStyle(color: Colors.white70, fontSize: 9),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0x80FFFFFF)),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: Transform.rotate(
              angle: 0.07,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                color: _dashboardInk,
                child: const Text(
                  'TEACH WITH\nCONFIDENCE.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          const Divider(height: 1, color: Color(0x80FFFFFF)),
          const SizedBox(height: 15),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  'MAKE EVERY\nEXAM COUNT.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 31 : 43,
                    fontWeight: FontWeight.w900,
                    height: 0.98,
                  ),
                ),
              ),
              const Text(
                '2026\n002 / 003',
                textAlign: TextAlign.right,
                style: TextStyle(color: Colors.white, fontSize: 9, height: 1.6),
              ),
            ],
          ),
        ],
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFD6D9D7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: compact
          ? Column(children: [copy, poster])
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 55, child: copy),
                  Expanded(flex: 45, child: poster),
                ],
              ),
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
        const spacing = 12.0;
        final columns = width >= 950
            ? 4
            : width >= 580
            ? 2
            : 1;
        final cardWidth = (width - spacing * (columns - 1)) / columns;
        final cards = [
          _metricCard(
            title: 'Your exams',
            value: '${data.totalExams}',
            caption: '${data.upcomingExams} upcoming',
            icon: Icons.assignment_outlined,
          ),
          _metricCard(
            title: 'Active exams',
            value: '${data.ongoingExams}',
            caption: 'Running now',
            icon: Icons.view_agenda_outlined,
            tone: _MetricTone.dark,
          ),
          _metricCard(
            title: 'Taking exam now',
            value: taking?.toString() ?? '--',
            caption: 'Live student presence',
            icon: Icons.track_changes_rounded,
            tone: _MetricTone.wash,
          ),
          _metricCard(
            title: 'Active attempts',
            value: '${data.totalStudents}',
            caption: 'Across active exams',
            icon: Icons.edit_note_rounded,
          ),
        ];

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
                for (final card in cards)
                  SizedBox(width: cardWidth, child: card),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String caption,
    required IconData icon,
    _MetricTone tone = _MetricTone.light,
  }) {
    final dark = tone == _MetricTone.dark;
    final wash = tone == _MetricTone.wash;
    final background = dark
        ? _dashboardInk
        : wash
        ? _dashboardBlueWash
        : Colors.white;
    final border = dark
        ? _dashboardInk
        : wash
        ? const Color(0xFFD5DCFF)
        : _dashboardLine;
    final titleColor = dark ? Colors.white70 : _dashboardMuted;
    final valueColor = dark ? Colors.white : _dashboardInk;
    final captionColor = dark ? Colors.white54 : _dashboardMuted;
    final iconBackground = dark
        ? Colors.white.withOpacity(0.14)
        : wash
        ? Colors.white
        : _dashboardBlueWash;
    final iconColor = dark ? Colors.white : _dashboardBlue;

    return Container(
      constraints: const BoxConstraints(minHeight: 146),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: titleColor, fontSize: 12),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 17),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              height: 1.05,
            ),
          ),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: captionColor, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _dashboardButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    final foreground = primary ? Colors.white : _dashboardInk;
    return Material(
      color: primary ? _dashboardBlue : Colors.white,
      borderRadius: BorderRadius.circular(7),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: primary ? _dashboardBlue : _dashboardLine,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 9),
              Icon(
                icon,
                color: primary ? Colors.white : _dashboardBlue,
                size: 16,
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _dashboardInk,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
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
                    color: AppTheme.accent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.accent.withOpacity(0.25),
                    ),
                  ),
                  child: const Text(
                    'Each clip is about 3 seconds long. The strike number(s) '
                    'shown on a clip are the cheat count(s) that happened '
                    'during that clip (e.g. "#3 – #5").',
                    style: TextStyle(color: AppTheme.text, fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _dashboardMuted,
                  size: 19,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveActivity(
    _DashboardData data,
    Stream<Map<String, int>> presenceStream, {
    bool expand = false,
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
              ? AppTheme.accent.withOpacity(0.15)
              : Colors.transparent,
          side: BorderSide(
            color: selected
                ? AppTheme.accent.withOpacity(0.45)
                : Colors.white.withOpacity(0.12),
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
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => _buildClipTile(clips[i].data(), kind),
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

        if (monitoringActive) {
          final studentSnapshot = await _db
              .collection('examResults')
              .doc(exam.id)
              .collection('students')
              .get();
          totalStudents += studentSnapshot.size;
        }
      }

      yield _DashboardData(
        totalStudents: totalStudents,
        ongoingExams: totalOngoing,
        totalExams: exams.length,
        examsToday: examsToday,
        examsThisWeek: examsThisWeek,
        upcomingExams: upcomingExams,
        ongoingExamIds: ongoingExamIds,
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
