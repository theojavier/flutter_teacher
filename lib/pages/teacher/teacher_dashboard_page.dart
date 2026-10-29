import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '/helpers/AppTheme.dart';
import '/widgets/exam_form_dialog.dart';

const Color _dashboardPaper = Color(0xFFF7F8F6);
const Color _dashboardInk = Color(0xFF111217);
const Color _dashboardBlue = Color(0xFF153CFF);
const Color _dashboardBlueDark = Color(0xFF0727C7);
const Color _dashboardBlueWash = Color(0xFFE9EDFF);
const Color _dashboardLine = Color(0xFFDCDDDC);
const Color _dashboardMuted = Color(0xFF777981);

enum _MetricTone { light, dark, wash }

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double dash;
  final double gap;

  const _DashedBorderPainter({
    this.color = const Color(0xFFCFD1D4),
    this.radius = 10,
    this.dash = 5,
    this.gap = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + dash), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
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
      ),
    );
  }

  Widget _panel({
    required String title,
    required String subtitle,
    required Widget trailing,
    required Widget child,
    bool expand = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _dashboardLine),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _dashboardInk,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: _dashboardMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                trailing,
              ],
            ),
          ),
          const Divider(height: 1, color: _dashboardLine),
          if (expand) Expanded(child: child) else child,
        ],
      ),
    );
  }

  Widget _emptyPanel({
    required IconData icon,
    required String title,
    required String message,
    required Widget action,
  }) {
    return CustomPaint(
      foregroundPainter: const _DashedBorderPainter(),
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Color(0xFFF6F7FB)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _dashboardBlueWash,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD5DCFF)),
              ),
              child: Icon(icon, color: _dashboardBlue, size: 22),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: _dashboardInk,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _dashboardMuted,
                fontSize: 12,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 18),
            action,
          ],
        ),
      ),
    );
  }

  Widget _outlineButton(String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: _dashboardInk,
        backgroundColor: Colors.white,
        side: const BorderSide(color: _dashboardLine),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }

  Widget _solidButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: _dashboardBlue,
        elevation: 0,
        minimumSize: const Size(0, 46),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
      child: Text(label),
    );
  }

  DateTime? _ts(Object? value) => value is Timestamp ? value.toDate() : null;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortedBySchedule(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> exams,
  ) {
    final now = DateTime.now();

    int group(Map<String, dynamic> data) {
      final start = _ts(data['startTime']);
      final end = _ts(data['endTime']);
      if (start == null) return 3;
      if (!start.isAfter(now) && end != null && end.isAfter(now)) return 0;
      if (start.isAfter(now)) return 1;
      return 2;
    }

    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.of(exams);
    sorted.sort((a, b) {
      final aData = a.data();
      final bData = b.data();
      final aGroup = group(aData);
      final bGroup = group(bData);
      if (aGroup != bGroup) return aGroup.compareTo(bGroup);
      final aStart = _ts(aData['startTime']);
      final bStart = _ts(bData['startTime']);
      if (aStart == null || bStart == null) return 0;
      return aGroup == 2 ? bStart.compareTo(aStart) : aStart.compareTo(bStart);
    });
    return sorted;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Not scheduled';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';
  }

  Widget _tableLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: _dashboardMuted,
      fontSize: 9,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
  );

  Widget _examTableHeader(bool wide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 0, 15, 10),
      child: Row(
        children: [
          const SizedBox(width: 48),
          Expanded(child: _tableLabel('EXAM')),
          const SizedBox(width: 12),
          if (wide) SizedBox(width: 150, child: _tableLabel('SCHEDULE')),
          SizedBox(width: 92, child: _tableLabel('STATUS')),
          const SizedBox(width: 27),
        ],
      ),
    );
  }

  Widget _buildRecentExams(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> exams, {
    bool wide = true,
    bool expand = false,
  }) {
    final visible = _sortedBySchedule(exams).take(5).toList();

    return _panel(
      expand: expand,
      title: 'Recent exams',
      subtitle: 'Nearest to start time first',
      trailing: _outlineButton('All exams', () => context.go('/teacher-exams')),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: visible.isEmpty
            ? _emptyPanel(
                icon: Icons.view_agenda_outlined,
                title: 'No exams added yet',
                message: 'Get started by creating a draft assessment.',
                action: _solidButton(
                  '+ Create your first exam',
                  () => context.go('/teacher-exams'),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _examTableHeader(wide),
                  for (var index = 0; index < visible.length; index++)
                    _recentExamRow(
                      visible[index],
                      wide: wide,
                      isLast: index == visible.length - 1,
                    ),
                ],
              ),
      ),
    );
  }

  Widget _recentExamRow(
    QueryDocumentSnapshot<Map<String, dynamic>> exam, {
    required bool wide,
    required bool isLast,
  }) {
    final data = exam.data();
    final subject = (data['subject'] ?? data['title'] ?? 'Untitled exam')
        .toString();
    final program = (data['program'] ?? '').toString();
    final yearBlock = (data['yearBlock'] ?? '').toString();
    final start = _ts(data['startTime']);
    final status = (data['approvalStatus'] ?? data['status'] ?? 'draft')
        .toString()
        .replaceAll('_', ' ');
    final statusColor = status.toLowerCase() == 'approved'
        ? const Color(0xFF27804A)
        : status.toLowerCase() == 'pending'
        ? const Color(0xFFB7791F)
        : _dashboardBlue;
    final details = [
      program,
      yearBlock,
    ].where((value) => value.isNotEmpty).join(' · ');

    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 0 : 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _dashboardLine),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _openExamDialog(exam.id, data),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _dashboardBlueWash,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.assignment_outlined,
                    color: _dashboardBlue,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _dashboardInk,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (details.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _dashboardMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                      if (!wide) ...[
                        const SizedBox(height: 3),
                        Text(
                          start == null
                              ? 'Not scheduled'
                              : '${_formatDate(start)} · ${_formatTime(start)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _dashboardBlue,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (wide)
                  SizedBox(
                    width: 150,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _formatDate(start),
                          style: const TextStyle(
                            color: _dashboardInk,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (start != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            _formatTime(start),
                            style: const TextStyle(
                              color: _dashboardMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                SizedBox(
                  width: 92,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: statusColor.withOpacity(0.28),
                        ),
                      ),
                      child: Text(
                        status.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
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
    return _panel(
      expand: expand,
      title: 'Live activity',
      subtitle: 'Secure session monitoring',
      trailing: Text(
        'LIVE / ${data.ongoingExams.toString().padLeft(2, '0')}',
        style: const TextStyle(
          color: _dashboardMuted,
          fontSize: 11,
          letterSpacing: 1,
          fontFamily: 'monospace',
        ),
      ),
      child: StreamBuilder<Map<String, int>>(
        stream: presenceStream,
        initialData: const {'taking': 0, 'offline': 0, 'disconnected': 0},
        builder: (context, snapshot) {
          final taking = snapshot.data?['taking'] ?? 0;
          final offline = snapshot.data?['offline'] ?? 0;
          final disconnected = snapshot.data?['disconnected'] ?? 0;

          if (data.ongoingExams == 0) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: _emptyPanel(
                icon: Icons.track_changes_rounded,
                title: 'Nothing live yet',
                message:
                    'Student connections and gaze monitoring\nalerts will appear here when an exam is active.',
                action: _outlineButton(
                  'Open monitoring',
                  () => context.go('/teacher-monitoring'),
                ),
              ),
            );
          }

          final total = taking + offline + disconnected;
          return Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.hasError
                      ? 'Could not load live student connections.'
                      : '$taking students taking an exam',
                  style: const TextStyle(
                    color: _dashboardInk,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                if (snapshot.hasError)
                  Text(
                    '${snapshot.error}',
                    style: const TextStyle(color: AppTheme.error, fontSize: 11),
                  )
                else ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: total == 0 ? 0 : taking / total,
                      backgroundColor: _dashboardLine,
                      valueColor: const AlwaysStoppedAnimation(_dashboardBlue),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 13,
                    runSpacing: 8,
                    children: [
                      _activityCount('Taking', taking, _dashboardBlue),
                      _activityCount(
                        'Offline',
                        offline,
                        const Color(0xFFB7791F),
                      ),
                      _activityCount(
                        'Disconnected',
                        disconnected,
                        _dashboardMuted,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: _outlineButton(
                    'Open monitoring',
                    () => context.go('/teacher-monitoring'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _activityCount(String label, int count, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        '$count $label',
        style: const TextStyle(color: _dashboardMuted, fontSize: 10),
      ),
    ],
  );

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
