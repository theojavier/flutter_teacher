import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'dart:ui_web' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:firebase_database/firebase_database.dart'
    show DatabaseEvent, FirebaseDatabase;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web/web.dart' as web;

import '../../helpers/AppTheme.dart';
import '../../helpers/exam_result_cleanup.dart';
import '../../widgets/app_dialog.dart';

const Color _dashboardBlue = Color(0xFF153CFF);
// ============================================================
// SMALL HELPERS
// ============================================================

DateTime? _dateOf(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  if (value is String) return DateTime.tryParse(value);
  return null;
}

List<String> _examClassIds(Map<String, dynamic> data) {
  final ids = <String>{};
  final single = data['classId'];
  if (single != null && '$single'.trim().isNotEmpty) {
    ids.add('$single'.trim());
  }
  final many = data['classIds'];
  if (many is List) {
    for (final value in many) {
      if ('$value'.trim().isNotEmpty) ids.add('$value'.trim());
    }
  }
  return ids.take(30).toList();
}

enum _RowFilter { all, live, disconnected, notStarted, flagged, finished }

String _filterLabel(_RowFilter f) => switch (f) {
  _RowFilter.all => 'All',
  _RowFilter.live => 'Taking exam',
  _RowFilter.disconnected => 'Disconnected',
  _RowFilter.notStarted => 'Not started',
  _RowFilter.flagged => 'Flagged',
  _RowFilter.finished => 'Finished',
};

// ============================================================
// PAGE
// ============================================================

class TeacherMonitoringPage extends StatefulWidget {
  final String teacherId;
  const TeacherMonitoringPage({super.key, required this.teacherId});
  @override
  State<TeacherMonitoringPage> createState() => _TeacherMonitoringPageState();
}

class _TeacherMonitoringPageState extends State<TeacherMonitoringPage> {
  static const Color _ink = Color(0xFF171719);
  static const Color _muted = Color(0xFF77777A);
  static const Color _line = Color(0xFFDEDEDC);
  static const Color _live = Color(0xFF27865E);

  final _db = FirebaseFirestore.instance;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _examsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _programsStream = _db
      .collection('programs')
      .snapshots();
  Timer? _refreshTimer;
  String? _selectedExamId;
  String? _lastRequestedExam;

  @override
  void initState() {
    super.initState();
    _examsStream = _watchExams(widget.teacherId);
    // Re-evaluates "ongoing" and the time-left label.
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant TeacherMonitoringPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teacherId != widget.teacherId) {
      _examsStream = _watchExams(widget.teacherId);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final requestedExam = GoRouterState.of(context).uri.queryParameters['exam'];
    if (requestedExam != null && requestedExam != _lastRequestedExam) {
      _lastRequestedExam = requestedExam;
      _selectedExamId = requestedExam;
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _watchExams(String teacherId) =>
      _db
          .collection('exams')
          .where('teacherId', isEqualTo: teacherId)
          .snapshots();

  Map<String, String> _programAcronyms(
    QuerySnapshot<Map<String, dynamic>>? snapshot,
  ) {
    final acronyms = <String, String>{};
    for (final program in snapshot?.docs ?? []) {
      final data = program.data();
      final name = (data['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;

      final ignoredWords = {'a', 'an', 'and', 'for', 'in', 'of', 'the', 'to'};
      final words = name
          .split(RegExp(r'\s+'))
          .map((word) => word.replaceAll(RegExp(r'[^A-Za-z0-9]'), ''))
          .where(
            (word) =>
                word.isNotEmpty && !ignoredWords.contains(word.toLowerCase()),
          );
      final acronym = words.map((word) => word[0].toUpperCase()).join();
      if (acronym.isEmpty) continue;

      acronyms[program.id] = acronym;
      final code = (data['code'] ?? '').toString().trim();
      if (code.isNotEmpty) acronyms[code] = acronym;
      acronyms[name] = acronym;
    }
    return acronyms;
  }

  String _programLabel(Object? rawProgram, Map<String, String> acronyms) {
    final value = (rawProgram ?? '').toString().trim();
    return acronyms[value] ?? value;
  }

  bool _isMonitoredAndOngoing(Map<String, dynamic> data) {
    if (data['monitoringEnabled'] != true) return false;
    final status = (data['status'] ?? '').toString().toLowerCase();
    if (['finished', 'finish', 'complete', 'completed'].contains(status)) {
      return false;
    }
    final now = DateTime.now();
    final start = _dateOf(data['startTime']);
    final end = _dateOf(data['endTime']);
    if (start == null || end == null) return false;
    return !now.isBefore(start) && now.isBefore(end);
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 600;

    final pagePadding = isNarrow ? 16.0 : 24.0;
    final pageTopPadding = isNarrow ? 24.0 : 24.0;
    final pageBottomPadding = 40.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F5),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _examsStream,
        builder: (context, examSnapshot) {
          if (examSnapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            );
          }

          if (examSnapshot.hasError) {
            return Center(
              child: _emptyState(
                Icons.error_outline,
                'Unable to load sessions',
                'Please check your connection and try again.',
              ),
            );
          }

          final active =
              (examSnapshot.data?.docs ?? [])
                  .where((doc) => _isMonitoredAndOngoing(doc.data()))
                  .toList()
                ..sort((a, b) {
                  final sa = _dateOf(a.data()['startTime']) ?? DateTime(0);
                  final sb = _dateOf(b.data()['startTime']) ?? DateTime(0);
                  return sa.compareTo(sb);
                });

          QueryDocumentSnapshot<Map<String, dynamic>>? picked;
          for (final doc in active) {
            if (doc.id == _selectedExamId) picked = doc;
          }
          picked ??= active.isEmpty ? null : active.first;
          final QueryDocumentSnapshot<Map<String, dynamic>>? sel = picked;

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _programsStream,
            builder: (context, programSnapshot) {
              final acronyms = _programAcronyms(programSnapshot.data);
              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  pagePadding,
                  pageTopPadding,
                  pagePadding,
                  pageBottomPadding,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1350),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _pageHead(isNarrow, active.length),
                        if (programSnapshot.hasError) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Unable to load program names: ${programSnapshot.error}',
                            style: const TextStyle(
                              color: AppTheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        if (sel == null)
                          _idleLayout(
                            examSnapshot.data?.docs ?? const [],
                            acronyms,
                          )
                        else ...[
                          if (active.length > 1) ...[
                            _examSelector(active, sel.id, acronyms),
                            const SizedBox(height: 14),
                          ],
                          _examHeader(sel, acronyms),
                          const SizedBox(height: 16),
                          _MonitoringStudentsTable(
                            key: ValueKey(sel.id),
                            examId: sel.id,
                            program: sel.data()['program'],
                            yearBlock: sel.data()['yearBlock'],
                            classIds: _examClassIds(sel.data()),
                            isPc: sel.data()['isPc'] != false,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------
  // PAGE HEAD
  // ------------------------------------------------------------

  Widget _pageHead(bool isNarrow, int liveCount) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '05 / LIVE PROCTORING',
                style: TextStyle(
                  color: _dashboardBlue,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Monitoring.',
                style: AppTheme.display(34, ls: -0.06, color: AppTheme.text),
              ),
              const SizedBox(height: 8),
              const Text(
                'Watch who is taking the exam, who dropped off, and who needs a closer look.',
                style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE0E0DE)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: liveCount == 0 ? const Color(0xFFB5B5B5) : _live,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                liveCount == 0 ? 'NO LIVE EXAMS' : '$liveCount LIVE',
                style: const TextStyle(
                  color: Color(0xFF626267),
                  fontFamily: 'monospace',
                  fontSize: 10,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------
  // EXAM SELECTOR (only when more than one exam is live)
  // ------------------------------------------------------------

  Widget _examSelector(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> exams,
    String selectedId,
    Map<String, String> acronyms,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final exam in exams) ...[
            _examTab(exam, exam.id == selectedId, acronyms),
            const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _examTab(
    QueryDocumentSnapshot<Map<String, dynamic>> exam,
    bool selected,
    Map<String, String> acronyms,
  ) {
    final data = exam.data();
    final program = _programLabel(data['program'], acronyms);
    final yearBlock = (data['yearBlock'] ?? '').toString();
    final sub = [
      if (program.isNotEmpty) program,
      if (yearBlock.isNotEmpty) yearBlock,
    ].join(' · ');

    return Material(
      color: selected ? AppTheme.accent.withValues(alpha: 0.07) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? AppTheme.accent : const Color(0xFFE0E0DE),
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        onTap: () => setState(() => _selectedExamId = exam.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (data['subject'] ?? 'Untitled exam').toString(),
                style: TextStyle(
                  color: selected ? AppTheme.accent : _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (sub.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(color: _muted, fontSize: 10)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // EXAM HEADER (live status, time left, progress, evidence link)
  // ------------------------------------------------------------

  String _timeLeft(DateTime end) {
    final left = end.difference(DateTime.now());
    if (left.isNegative) return 'Ending now';
    final h = left.inHours;
    final m = left.inMinutes.remainder(60);
    return h > 0 ? '${h}h ${m}m left' : '${left.inMinutes}m left';
  }

  Widget _chip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E0DE)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _muted),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF4A4A4F),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _examHeader(
    QueryDocumentSnapshot<Map<String, dynamic>> exam,
    Map<String, String> acronyms,
  ) {
    final data = exam.data();
    final subject = (data['subject'] ?? 'Untitled exam').toString();
    final program = _programLabel(data['program'], acronyms);
    final yearBlock = (data['yearBlock'] ?? '').toString();
    final isPc = data['isPc'] != false;
    final start = _dateOf(data['startTime']);
    final end = _dateOf(data['endTime']);
    final loc = MaterialLocalizations.of(context);

    final window = (start == null || end == null)
        ? ''
        : '${loc.formatTimeOfDay(TimeOfDay.fromDateTime(start))}'
              ' – ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(end))}';

    var progress = 0.0;
    if (start != null && end != null) {
      final total = end.difference(start).inSeconds;
      if (total > 0) {
        progress = (DateTime.now().difference(start).inSeconds / total).clamp(
          0.0,
          1.0,
        );
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: _live,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                'LIVE NOW',
                style: TextStyle(
                  color: _live,
                  fontFamily: 'monospace',
                  fontSize: 10,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (end != null)
                Text(
                  _timeLeft(end).toUpperCase(),
                  style: const TextStyle(
                    color: _muted,
                    fontFamily: 'monospace',
                    fontSize: 10,
                    letterSpacing: 0.6,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            subject,
            style: const TextStyle(
              color: _ink,
              fontSize: 24,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (program.isNotEmpty) _chip(Icons.school_outlined, program),
              if (yearBlock.isNotEmpty) _chip(Icons.groups_outlined, yearBlock),
              if (window.isNotEmpty) _chip(Icons.schedule, window),
              _chip(
                isPc ? Icons.desktop_windows_outlined : Icons.smartphone,
                isPc ? 'PC exam' : 'Mobile exam',
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              color: AppTheme.accent,
              backgroundColor: const Color(0xFFECECEA),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // STANDBY LAYOUT (no exam is live)
  // ------------------------------------------------------------

  String _untilLabel(DateTime target) {
    final d = target.difference(DateTime.now());
    if (d.isNegative) return 'now';
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }

  Widget _pill(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontFamily: 'monospace',
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
      ),
    ),
  );

  Widget _idleLayout(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> all,
    Map<String, String> acronyms,
  ) {
    final now = DateTime.now();
    final exams =
        <({Map<String, dynamic> data, DateTime start, DateTime end})>[];
    for (final doc in all) {
      final data = doc.data();
      if ((data['approvalStatus'] ?? '').toString() == 'rejected') continue;
      final s = _dateOf(data['startTime']);
      final e = _dateOf(data['endTime']);
      if (s == null || e == null) continue;
      exams.add((data: data, start: s, end: e));
    }

    final upcoming = exams.where((x) => x.end.isAfter(now)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final ended = exams.where((x) => x.end.isBefore(now)).toList()
      ..sort((a, b) => b.end.compareTo(a.end));
    final next = upcoming.isEmpty ? null : upcoming.first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _idleHeader(next, acronyms),
        const SizedBox(height: 16),
        _idleStatCards(),
        const SizedBox(height: 16),
        _idleToolbar(),
        const SizedBox(height: 12),
        _idleTable(),
        if (upcoming.isNotEmpty || ended.isNotEmpty) ...[
          const SizedBox(height: 16),
          _idleSchedule(
            upcoming.take(4).toList(),
            ended.take(3).toList(),
            acronyms,
          ),
        ],
      ],
    );
  }

  Widget _idleHeader(
    ({Map<String, dynamic> data, DateTime start, DateTime end})? next,
    Map<String, String> acronyms,
  ) {
    final loc = DateFormat('EEE, MMM d · h:mm a');
    final hasNext = next != null;
    final started = hasNext && !next.start.isAfter(DateTime.now());

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: Color(0xFFB5B5B5),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                hasNext ? 'STANDBY · NEXT EXAM' : 'STANDBY',
                style: const TextStyle(
                  color: _muted,
                  fontFamily: 'monospace',
                  fontSize: 10,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (hasNext && !started)
                Text(
                  'STARTS IN ${_untilLabel(next.start).toUpperCase()}',
                  style: const TextStyle(
                    color: _muted,
                    fontFamily: 'monospace',
                    fontSize: 10,
                    letterSpacing: 0.6,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            hasNext
                ? (next.data['subject'] ?? 'Untitled exam').toString()
                : 'No exam in session',
            style: const TextStyle(
              color: _ink,
              fontSize: 24,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hasNext
                ? (started
                      ? 'This exam is inside its scheduled time, but monitoring is turned off, so it is not shown live.'
                      : '${loc.format(next.start)} · ${_programLabel(next.data['program'], acronyms)} ${(next.data['yearBlock'] ?? '').toString()}'
                            .trim())
                : 'Nothing is scheduled right now. When an exam starts with monitoring on, students, flags, and clips appear here live.',
            style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(
              value: 0,
              minHeight: 5,
              backgroundColor: Color(0xFFECECEA),
            ),
          ),
        ],
      ),
    );
  }

  Widget _idleStatCards() {
    const labels = [
      'STUDENTS',
      'TAKING EXAM',
      'DISCONNECTED',
      'FINISHED',
      'FLAGGED',
      'WITH CLIPS',
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900
            ? 6
            : c.maxWidth >= 560
            ? 3
            : 2;
        const gap = 10.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols - 0.01;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final label in labels)
              SizedBox(
                width: w,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFDEDEDC)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF77777B),
                          fontFamily: 'monospace',
                          fontSize: 9.5,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '0',
                        style: TextStyle(
                          color: Color(0xFFB5B5B5),
                          fontSize: 26,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _idleToolbar() {
    OutlineInputBorder border() => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE0E0DE)),
    );
    return Opacity(
      opacity: 0.55,
      child: IgnorePointer(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              enabled: false,
              decoration: InputDecoration(
                hintText: 'Search student no. or name',
                hintStyle: const TextStyle(
                  color: Color(0xFF85858A),
                  fontSize: 13,
                ),
                prefixIcon: const Icon(Icons.search, size: 19),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 13,
                ),
                border: border(),
                enabledBorder: border(),
                disabledBorder: border(),
              ),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in _RowFilter.values) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE0E0DE)),
                      ),
                      child: Text(
                        '${_filterLabel(f)}  0',
                        style: const TextStyle(
                          color: Color(0xFF4A4A4F),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _idleTable() {
    const heads = [
      ('STUDENT', 3),
      ('ACTIVITY', 2),
      ('STATUS', 2),
      ('PROGRESS', 2),
      ('FLAGS', 1),
      ('CAMERA', 2),
      ('SCREEN', 2),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0DE)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Container(
            color: const Color(0xFFF7F8F6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                for (final h in heads)
                  Expanded(
                    flex: h.$2,
                    child: Text(
                      h.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE0E0DE)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 38, horizontal: 20),
            child: Column(
              children: [
                Icon(Icons.people_outline, size: 26, color: Color(0xFFB5B5B5)),
                SizedBox(height: 10),
                Text(
                  'Student rows will appear here once an exam goes live.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF85858A), fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _idleSchedule(
    List<({Map<String, dynamic> data, DateTime start, DateTime end})> upcoming,
    List<({Map<String, dynamic> data, DateTime start, DateTime end})> ended,
    Map<String, String> acronyms,
  ) {
    final dateFmt = DateFormat('EEE, MMM d · h:mm a');
    final now = DateTime.now();

    Widget row(
      ({Map<String, dynamic> data, DateTime start, DateTime end}) x,
      Widget trailing,
    ) {
      final program = _programLabel(x.data['program'], acronyms);
      final yearBlock = (x.data['yearBlock'] ?? '').toString();
      final meta = [
        if (program.isNotEmpty) program,
        if (yearBlock.isNotEmpty) yearBlock,
        dateFmt.format(x.start),
      ].join(' · ');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (x.data['subject'] ?? 'Untitled exam').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF29292C),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 10.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      );
    }

    Widget sectionTitle(String t) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        t,
        style: const TextStyle(
          color: Color(0xFF77777B),
          fontFamily: 'monospace',
          fontSize: 10,
          letterSpacing: 0.7,
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (upcoming.isNotEmpty) ...[
            sectionTitle('UPCOMING EXAMS'),
            for (var i = 0; i < upcoming.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: Color(0xFFECECEA)),
              row(
                upcoming[i],
                _pill(
                  (upcoming[i].data['approvalStatus'] ?? '').toString() !=
                          'approved'
                      ? 'PENDING APPROVAL'
                      : upcoming[i].start.isAfter(now)
                      ? 'IN ${_untilLabel(upcoming[i].start).toUpperCase()}'
                      : 'MONITORING OFF',
                  upcoming[i].start.isAfter(now) &&
                          (upcoming[i].data['approvalStatus'] ?? '')
                                  .toString() ==
                              'approved'
                      ? AppTheme.accent
                      : const Color(0xFFB7791F),
                ),
              ),
            ],
          ],
          if (upcoming.isNotEmpty && ended.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, color: Color(0xFFECECEA)),
            const SizedBox(height: 10),
          ],
          if (ended.isNotEmpty) ...[
            sectionTitle('RECENTLY ENDED'),
            for (var i = 0; i < ended.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: Color(0xFFECECEA)),
              row(ended[i], _pill('ENDED', AppTheme.mutedText)),
            ],
          ],
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
}

// ============================================================
// STUDENTS PANEL (stat cards + search + filters + table)
// ============================================================

class _MonitoringStudentsTable extends StatefulWidget {
  final String examId;
  final Object? program;
  final Object? yearBlock;
  final List<String> classIds;
  final bool isPc;

  const _MonitoringStudentsTable({
    super.key,
    required this.examId,
    required this.program,
    required this.yearBlock,
    required this.classIds,
    required this.isPc,
  });

  @override
  State<_MonitoringStudentsTable> createState() =>
      _MonitoringStudentsTableState();
}

class _MonitoringStudentsTableState extends State<_MonitoringStudentsTable> {
  static const _heartbeatTimeout = Duration(minutes: 5);
  static const Color _warn = Color(0xFFB7791F);
  static const Color _okay = Color(0xFF27865E);

  final _db = FirebaseFirestore.instance;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _rosterStream =
      _buildRosterQuery().snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _resultsStream = _db
      .collection('examResults')
      .doc(widget.examId)
      .collection('students')
      .snapshots();
  late final Stream<DatabaseEvent> _presenceStream = FirebaseDatabase.instance
      .ref('examPresence/${widget.examId}')
      .onValue;
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  _RowFilter _filter = _RowFilter.all;
  DateTime _now = DateTime.now();
  Timer? _clock;
  final Map<String, Map<String, dynamic>> _extraProfiles = {};
  final Set<String> _requestedProfiles = {};

  Query<Map<String, dynamic>> _buildRosterQuery() {
    Query<Map<String, dynamic>> query = _db.collection('users');
    if (widget.classIds.isNotEmpty) {
      return query.where('classIds', arrayContainsAny: widget.classIds);
    }
    if (widget.yearBlock != null) {
      query = query.where('yearBlock', isEqualTo: widget.yearBlock);
    }
    return query;
  }

  /// Program is matched here because exams store the program CODE
  /// while student profiles may store it in `programCode` or `program`.
  bool _belongsToExam(Map<String, dynamic> profile) {
    final role = '${profile['role'] ?? ''}'.toLowerCase();
    if (role == 'teacher' || role == 'admin') return false;
    if (widget.classIds.isNotEmpty) return true;

    final wanted = '${widget.program ?? ''}'.trim().toLowerCase();
    if (wanted.isEmpty) return true;

    final have = {
      '${profile['programCode'] ?? ''}',
      '${profile['program'] ?? ''}',
    }.map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty);
    return have.contains(wanted);
  }

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  static DateTime? _asDateTime(dynamic value) => _dateOf(value);

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map((key, value) => MapEntry('$key', value));
    }
    return {};
  }

  static String _studentName(Map<String, dynamic> data) {
    final fullName = data['fullName'] ?? data['name'] ?? data['displayName'];
    if (fullName != null && '$fullName'.trim().isNotEmpty) {
      return '$fullName'.trim();
    }
    final names = [data['firstName'], data['lastName']]
        .where((part) => part != null && '$part'.trim().isNotEmpty)
        .join(' ')
        .trim();
    return names.isEmpty ? 'Unknown student' : names;
  }

  static String? _studentPhotoUrl(Map<String, dynamic> data) {
    final value = data['profileImage'];
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }

  static int _intOrZero(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static int? _intOrNull(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  void _loadMissingProfiles(Iterable<String> uids) {
    final missing = uids
        .where((uid) => !_requestedProfiles.contains(uid))
        .toList();
    if (missing.isEmpty) return;
    _requestedProfiles.addAll(missing);

    Future.microtask(() async {
      final found = <String, Map<String, dynamic>>{};
      for (var i = 0; i < missing.length; i += 30) {
        final end = i + 30 > missing.length ? missing.length : i + 30;
        final chunk = missing.sublist(i, end);
        try {
          final byId = await _db
              .collection('users')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
          for (final doc in byId.docs) {
            found[doc.id] = doc.data();
          }
          final notFound = chunk
              .where((uid) => !found.containsKey(uid))
              .toList();
          if (notFound.isNotEmpty) {
            final byUid = await _db
                .collection('users')
                .where('UID', whereIn: notFound)
                .get();
            for (final doc in byUid.docs) {
              final uid = doc.data()['UID'];
              if (uid != null) found['$uid'] = doc.data();
            }
          }
        } catch (error) {
          debugPrint('Profile lookup failed: $error');
        }
      }
      if (!mounted || found.isEmpty) return;
      setState(() => _extraProfiles.addAll(found));
    });
  }

  // ------------------------------------------------------------
  // DATA MERGE
  // ------------------------------------------------------------

  List<_MonitoringStudent> _mergeRows(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> roster,
    QuerySnapshot<Map<String, dynamic>> results,
    Map<String, dynamic> presence,
  ) {
    final resultsByUid = {for (final doc in results.docs) doc.id: doc.data()};
    final known = {for (final doc in roster) '${doc.data()['UID'] ?? doc.id}'};
    _loadMissingProfiles(
      resultsByUid.keys.where((uid) => !known.contains(uid)),
    );

    _MonitoringStudent build(
      String uid,
      String docId,
      Map<String, dynamic> profile,
    ) {
      final result = resultsByUid[uid] ?? <String, dynamic>{};
      final studentPresence = _asMap(presence[uid]);
      final status = (result['status'] ?? '').toString().toLowerCase();
      final finished = status == 'completed' || status == 'incomplete';
      final heartbeat = _asDateTime(
        result['lastHeartbeatAt'] ?? result['lastSeenAt'],
      );
      final presenceLastSeen = _asDateTime(studentPresence['lastSeen']);
      final heartbeatFresh =
          heartbeat != null &&
          !_now.subtract(_heartbeatTimeout).isAfter(heartbeat);
      final presenceFresh =
          presenceLastSeen == null ||
          !_now.subtract(const Duration(minutes: 3)).isAfter(presenceLastSeen);
      final isOnline =
          !finished &&
          (studentPresence.isEmpty
              ? result['isActive'] == true && heartbeatFresh
              : studentPresence['online'] == true &&
                    presenceFresh &&
                    result['isActive'] == true &&
                    heartbeatFresh);
      final lastSeen = [heartbeat, presenceLastSeen]
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (latest, value) =>
                latest == null || value.isAfter(latest) ? value : latest,
          );
      final rawIndex = result['currentIndex'];
      final currentIndex = rawIndex is num
          ? rawIndex.toInt()
          : int.tryParse('$rawIndex');
      final hasStarted =
          result['status'] != null ||
          heartbeat != null ||
          _asDateTime(result['startedAt']) != null ||
          currentIndex != null;

      return _MonitoringStudent(
        uid: uid,
        name: _studentName(profile),
        studentNo: '${profile['studentId'] ?? profile['studentNo'] ?? docId}',
        photoUrl: _studentPhotoUrl(profile),
        status: status,
        hasStarted: hasStarted,
        hasResultDocument: resultsByUid.containsKey(uid),
        isOnline: isOnline,
        currentIndex: currentIndex,
        lastSeen: lastSeen,
        flags: _intOrZero(result['cheatingCount'] ?? result['cheatCount']),
        score: _intOrNull(result['score']),
        total: _intOrNull(result['total']),
        startedAt: _asDateTime(result['startedAt']),
        submittedAt: _asDateTime(result['submittedAt']),
        lastFlagAt: _asDateTime(result['lastCheatingUpdate']),
        clipCount: _intOrZero(result['cheatClipCount']),
        incompleteReason: result['incompleteReason']?.toString(),
      );
    }

    // Every profile we loaded, keyed by auth uid (UID field, else doc id).
    final profiles = {
      for (final entry in _extraProfiles.entries)
        entry.key: (entry.key, entry.value),
      for (final doc in roster)
        '${doc.data()['UID'] ?? doc.id}': (doc.id, doc.data()),
    };

    final rows = <_MonitoringStudent>[];
    final seen = <String>{};

    for (final entry in profiles.entries) {
      if (!_belongsToExam(entry.value.$2)) continue;
      if (seen.add(entry.key)) {
        rows.add(build(entry.key, entry.value.$1, entry.value.$2));
      }
    }

    // Safety net: anyone with a result document is always shown.
    for (final uid in resultsByUid.keys) {
      if (!seen.add(uid)) continue;
      final p = profiles[uid];
      rows.add(build(uid, p?.$1 ?? uid, p?.$2 ?? const <String, dynamic>{}));
    }

    rows.sort((a, b) {
      final flagged = b.flags.compareTo(a.flags);
      return flagged != 0 ? flagged : a.name.compareTo(b.name);
    });
    return rows;
  }

  bool _isFinished(_MonitoringStudent r) =>
      r.status == 'completed' || r.status == 'incomplete';

  bool _matches(_MonitoringStudent r, _RowFilter f) => switch (f) {
    _RowFilter.all => true,
    _RowFilter.live => r.isOnline,
    _RowFilter.disconnected => r.hasStarted && !r.isOnline && !_isFinished(r),
    _RowFilter.notStarted => !r.hasStarted,
    _RowFilter.flagged => r.flags > 0,
    _RowFilter.finished => _isFinished(r),
  };

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _rosterStream,
      builder: (context, rosterSnapshot) {
        if (rosterSnapshot.hasError) {
          return _message(
            'Unable to load student roster: ${rosterSnapshot.error}',
          );
        }
        if (!rosterSnapshot.hasData) return _loading();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _resultsStream,
          builder: (context, resultsSnapshot) {
            if (resultsSnapshot.hasError) {
              return _message(
                'Unable to load exam results: ${resultsSnapshot.error}',
              );
            }
            if (!resultsSnapshot.hasData) return _loading();

            return StreamBuilder<DatabaseEvent>(
              stream: _presenceStream,
              builder: (context, presenceSnapshot) {
                if (presenceSnapshot.hasError) {
                  return _message(
                    'Unable to load realtime presence: ${presenceSnapshot.error}',
                  );
                }
                final rows = _mergeRows(
                  rosterSnapshot.data!.docs,
                  resultsSnapshot.data!,
                  _asMap(presenceSnapshot.data?.snapshot.value),
                );

                final q = _query.trim().toLowerCase();
                final visible = rows.where((r) {
                  if (!_matches(r, _filter)) return false;
                  if (q.isEmpty) return true;
                  return r.name.toLowerCase().contains(q) ||
                      r.studentNo.toLowerCase().contains(q);
                }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _statCards(rows),
                    const SizedBox(height: 16),
                    _toolbar(rows),
                    const SizedBox(height: 12),
                    _buildTable(visible, totalCount: rows.length),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _loading() => const Padding(
    padding: EdgeInsets.all(24),
    child: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
  );

  Widget _message(String message) => Padding(
    padding: const EdgeInsets.all(18),
    child: Text(
      message,
      style: const TextStyle(color: AppTheme.error, fontSize: 12),
    ),
  );

  // ------------------------------------------------------------
  // STAT CARDS
  // ------------------------------------------------------------

  Widget _statCards(List<_MonitoringStudent> rows) {
    final items = <({String label, int value, Color color})>[
      (label: 'STUDENTS', value: rows.length, color: const Color(0xFF29292C)),
      (
        label: 'TAKING EXAM',
        value: rows.where((r) => r.isOnline).length,
        color: _okay,
      ),
      (
        label: 'DISCONNECTED',
        value: rows.where((r) => _matches(r, _RowFilter.disconnected)).length,
        color: _warn,
      ),
      (
        label: 'FINISHED',
        value: rows.where(_isFinished).length,
        color: AppTheme.accent,
      ),
      (
        label: 'FLAGGED',
        value: rows.where((r) => r.flags > 0).length,
        color: AppTheme.error,
      ),
      (
        label: 'WITH CLIPS',
        value: rows.where((r) => r.clipCount > 0).length,
        color: const Color(0xFF5368B1),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900
            ? 6
            : c.maxWidth >= 560
            ? 3
            : 2;
        const gap = 10.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols - 0.01;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: w,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFDEDEDC)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF77777B),
                          fontFamily: 'monospace',
                          fontSize: 9.5,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${item.value}',
                        style: TextStyle(
                          color: item.color,
                          fontSize: 26,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.8,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------
  // SEARCH + FILTER CHIPS
  // ------------------------------------------------------------

  Widget _toolbar(List<_MonitoringStudent> rows) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontSize: 13, color: Color(0xFF29292C)),
          decoration: InputDecoration(
            hintText: 'Search student no. or name',
            hintStyle: const TextStyle(color: Color(0xFF85858A), fontSize: 13),
            prefixIcon: const Icon(
              Icons.search,
              size: 19,
              color: Color(0xFF85858A),
            ),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            border: border(const Color(0xFFE0E0DE)),
            enabledBorder: border(const Color(0xFFE0E0DE)),
            focusedBorder: border(AppTheme.accent),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final f in _RowFilter.values) ...[
                _filterChip(f, rows.where((r) => _matches(r, f)).length),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(_RowFilter f, int count) {
    final selected = _filter == f;
    return Material(
      color: selected ? AppTheme.accent : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? AppTheme.accent : const Color(0xFFE0E0DE),
        ),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        onTap: () => setState(() => _filter = f),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            '${_filterLabel(f)}  $count',
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF4A4A4F),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // TABLE
  // ------------------------------------------------------------

  Widget _buildTable(List<_MonitoringStudent> rows, {required int totalCount}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final showLastSeen = constraints.maxWidth >= 900;
        if (rows.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE0E0DE)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                totalCount == 0
                    ? 'No students found for this program and year block.'
                    : 'No students match this search or filter.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
              ),
            ),
          );
        }

        const headingHeight = 38.0;
        final rowHeight = compact ? 48.0 : 52.0;
        final tableHeight = headingHeight + rows.length * rowHeight + 8;
        const compactSpacing = 2.0;
        const compactMargin = 4.0;
        const compactStudentMin = 96.0;
        final compactColumnWidths =
            32.0 + 34 + 40 + 34 + 36 + (widget.isPc ? 36 : 0);
        final compactColumns = widget.isPc ? 7 : 6;
        final compactMinWidth =
            compactStudentMin +
            compactColumnWidths +
            compactMargin * 2 +
            compactSpacing * (compactColumns - 1) +
            2;

        DataColumn2 column(
          String label, {
          ColumnSize size = ColumnSize.M,
          double? width,
          bool centered = false,
        }) => DataColumn2(
          size: size,
          fixedWidth: width,
          label: Align(
            alignment: centered ? Alignment.center : Alignment.centerLeft,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.mutedText,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
        );

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE0E0DE)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SizedBox(
            height: tableHeight,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context).copyWith(
                scrollbars: false,
                dragDevices: {
                  PointerDeviceKind.touch,
                  PointerDeviceKind.mouse,
                  PointerDeviceKind.trackpad,
                  PointerDeviceKind.stylus,
                },
              ),
              child: DataTable2(
                minWidth: compact ? compactMinWidth : constraints.maxWidth,
                columnSpacing: compact ? compactSpacing : 4,
                horizontalMargin: compact ? compactMargin : 8,
                headingRowHeight: headingHeight,
                dataRowHeight: rowHeight,
                fixedLeftColumns: 1,
                fixedColumnsColor: Colors.white,
                fixedCornerColor: const Color(0xFFF7F8F6),
                isHorizontalScrollBarVisible: compact,
                isVerticalScrollBarVisible: false,
                headingRowColor: WidgetStateProperty.all(
                  const Color(0xFFF7F8F6),
                ),
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: const Color(0xFFE0E0DE).withValues(alpha: 0.7),
                  ),
                ),
                columns: [
                  column('STUDENT', size: ColumnSize.L),
                  column(
                    compact ? 'LIVE' : 'ACTIVITY',
                    size: ColumnSize.S,
                    centered: true,
                    width: compact ? 32 : null,
                  ),
                  column(
                    compact ? 'EXAM' : 'STATUS',
                    centered: true,
                    width: compact ? 34 : null,
                  ),
                  column(
                    'PROGRESS',
                    centered: true,
                    width: compact ? 40 : null,
                  ),
                  if (showLastSeen)
                    column('LAST SEEN', size: ColumnSize.S, centered: true),
                  column(
                    compact ? '!' : 'FLAGS',
                    centered: true,
                    width: compact ? 34 : null,
                  ),
                  column(
                    compact ? 'CAM' : 'CAMERA',
                    centered: true,
                    width: compact ? 36 : null,
                  ),
                  if (widget.isPc)
                    column(
                      compact ? 'SCR' : 'SCREEN',
                      centered: true,
                      width: compact ? 36 : null,
                    ),
                ],
                rows: rows.map((row) {
                  final progress = row.currentIndex == null
                      ? (row.status == 'incomplete' ? 'Stopped' : '—')
                      : 'Q${row.currentIndex}';
                  return DataRow2(
                    key: ValueKey(row.uid),
                    specificRowHeight: rowHeight,
                    onTap: row.hasStarted && row.hasResultDocument
                        ? () => _showStudentDetails(row)
                        : null,
                    cells: [
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF29292C),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              row.studentNo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF85858A),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(Center(child: _activityCell(row, compact))),
                      DataCell(Center(child: _statusCell(row, compact))),
                      DataCell(
                        Center(
                          child: Text(
                            progress,
                            style: const TextStyle(
                              color: Color(0xFF29292C),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (showLastSeen)
                        DataCell(Center(child: _lastSeenCell(row.lastSeen))),
                      DataCell(Center(child: _flagsCell(row.flags, compact))),
                      DataCell(
                        Center(child: _clipCell(row, 'camera', compact)),
                      ),
                      if (widget.isPc)
                        DataCell(
                          Center(child: _clipCell(row, 'screen', compact)),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _activityCell(_MonitoringStudent row, bool compact) {
    final text = _isFinished(row)
        ? 'Finished'
        : row.isOnline
        ? 'Taking exam'
        : row.hasStarted
        ? 'Disconnected'
        : 'Not started';
    final color = _isFinished(row)
        ? const Color(0xFF85858A)
        : row.isOnline
        ? _okay
        : row.hasStarted
        ? _warn
        : const Color(0xFF85858A);
    final icon = _isFinished(row)
        ? Icons.check_circle_outline
        : row.isOnline
        ? Icons.edit_note_outlined
        : row.hasStarted
        ? Icons.link_off_outlined
        : Icons.remove_circle_outline;
    return compact
        ? Tooltip(
            message: text,
            child: Icon(icon, size: 15, color: color),
          )
        : _statusPill(text, icon, color);
  }

  Widget _statusCell(_MonitoringStudent row, bool compact) {
    final label = row.status.isEmpty
        ? 'Pending'
        : row.status == 'in-progress'
        ? 'In progress'
        : row.status[0].toUpperCase() + row.status.substring(1);
    final color = row.status == 'completed'
        ? _okay
        : row.status == 'incomplete' || row.status == 'stopped'
        ? AppTheme.error
        : row.status == 'in-progress'
        ? AppTheme.accent
        : AppTheme.mutedText;
    final icon = row.status == 'completed'
        ? Icons.check_circle_outline
        : row.status == 'incomplete' || row.status == 'stopped'
        ? Icons.stop_circle_outlined
        : Icons.pending_outlined;
    return compact
        ? Tooltip(
            message: label,
            child: Icon(icon, size: 15, color: color),
          )
        : _statusPill(label, icon, color);
  }

  Widget _flagsCell(int flags, bool compact) {
    final color = flags == 0 ? AppTheme.mutedText : AppTheme.error;
    final icon = flags == 0
        ? Icons.verified_outlined
        : Icons.warning_amber_outlined;
    return compact
        ? Tooltip(
            message: '$flags flags',
            child: Icon(icon, size: 15, color: color),
          )
        : _statusPill('$flags ${flags == 1 ? 'flag' : 'flags'}', icon, color);
  }

  Widget _clipCell(_MonitoringStudent row, String kind, bool compact) {
    return _ClipCell(
      examId: widget.examId,
      uid: row.uid,
      kind: kind,
      compact: compact,
      clipCount: row.clipCount,
      status: row.status,
      onOpen: () => _openClips(row, kind),
    );
  }

  Future<void> _openClips(_MonitoringStudent row, String kind) {
    return showDialog<void>(
      context: context,
      builder: (_) => _ClipsDialog(
        examId: widget.examId,
        student: row,
        isPc: widget.isPc,
        initialKind: kind,
      ),
    );
  }

  Widget _statusPill(String label, IconData icon, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _lastSeenCell(DateTime? time) {
    if (time == null) {
      return const Text(
        '—',
        style: TextStyle(color: AppTheme.mutedText, fontSize: 10),
      );
    }
    final age = _now.difference(time);
    final label = age.inSeconds < 60
        ? 'now'
        : age.inMinutes < 60
        ? '${age.inMinutes}m ago'
        : '${age.inHours}h ago';
    return Text(
      label,
      style: const TextStyle(color: AppTheme.mutedText, fontSize: 10),
    );
  }

  // ------------------------------------------------------------
  // STUDENT DETAILS DIALOG
  // ------------------------------------------------------------

  static const _detailInk = Color(0xFF29292C);
  static const _detailMuted = Color(0xFF85858A);
  static const _detailBorder = Color(0xFFE0E0DE);

  Future<void> _showStudentDetails(_MonitoringStudent row) {
    String when(DateTime? date) {
      if (date == null) return 'Not recorded';
      final localizations = MaterialLocalizations.of(context);
      final dateLabel = localizations.formatFullDate(date);
      final timeLabel = localizations.formatTimeOfDay(
        TimeOfDay.fromDateTime(date),
      );
      return '$dateLabel · $timeLabel';
    }

    final score = row.score == null
        ? 'Not recorded'
        : '${row.score}${row.total == null ? '' : ' / ${row.total}'}';
    final flagColor = row.flags == 0
        ? _okay
        : row.flags < 3
        ? _warn
        : AppTheme.error;
    final initials = row.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    Widget section(String title, List<Widget> rows) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(
              color: _detailMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8F6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _detailBorder),
          ),
          child: Column(
            children: [
              for (var index = 0; index < rows.length; index++) ...[
                if (index > 0) const Divider(height: 1, color: _detailBorder),
                rows[index],
              ],
            ],
          ),
        ),
      ],
    );

    Widget detailLine(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: _detailMuted, fontSize: 12),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color ?? _detailInk,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: _detailBorder),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.88,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFFEEF0FF),
                      foregroundImage: row.photoUrl == null
                          ? null
                          : NetworkImage(row.photoUrl!),
                      child: Text(
                        initials.isEmpty ? '?' : initials,
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _detailInk,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            row.studentNo,
                            style: const TextStyle(
                              color: _detailMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close, color: _detailMuted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _detailBorder),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      section('EXAM ATTEMPT', [
                        detailLine(
                          'Current question',
                          row.currentIndex?.toString() ??
                              (row.status == 'incomplete'
                                  ? 'Stopped'
                                  : 'Not recorded'),
                        ),
                        detailLine('Score', score),
                        detailLine('Started', when(row.startedAt)),
                        detailLine('Last seen', when(row.lastSeen)),
                        detailLine('Submitted', when(row.submittedAt)),
                      ]),
                      const SizedBox(height: 14),
                      section('INTEGRITY', [
                        detailLine(
                          'Cheating flags',
                          '${row.flags}',
                          color: flagColor,
                        ),
                        detailLine('Latest flag', when(row.lastFlagAt)),
                        detailLine('Evidence clips', '${row.clipCount}'),
                      ]),
                      if (row.incompleteReason?.isNotEmpty == true) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTheme.error.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Text(
                            'Incomplete reason: ${row.incompleteReason}',
                            style: const TextStyle(
                              color: _detailInk,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      if (row.clipCount > 0) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.of(dialogContext).pop();
                              _openClips(row, 'camera');
                            },
                            icon: const Icon(Icons.videocam_outlined, size: 18),
                            label: const Text('View camera & screen clips'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _detailInk,
                              side: const BorderSide(color: _detailBorder),
                              minimumSize: const Size(0, 44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: _detailBorder),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmAction(
                          dialogContext,
                          row,
                          allowRetake: false,
                        ),
                        icon: const Icon(Icons.stop_circle_outlined, size: 18),
                        label: const Text('Stop Exam'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.error,
                          minimumSize: const Size(0, 44),
                          side: BorderSide(
                            color: AppTheme.error.withValues(alpha: 0.6),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _confirmAction(
                          dialogContext,
                          row,
                          allowRetake: true,
                        ),
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('Allow Retake'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmAction(
    BuildContext dialogContext,
    _MonitoringStudent row, {
    required bool allowRetake,
  }) async {
    final action = allowRetake ? 'Allow Retake' : 'Stop Exam';
    final confirmed = await AppDialog.confirm(
      dialogContext,
      tone: allowRetake ? AppTone.info : AppTone.warning,
      icon: allowRetake ? Icons.restart_alt : Icons.stop_circle_outlined,
      title: allowRetake ? 'Allow a retake?' : 'Stop this exam?',
      detail: row.studentNo,
      message: allowRetake
          ? 'This will remove the current exam result and allow a new attempt.'
          : 'This will stop the exam session.',
      confirmLabel: action,
    );
    if (!confirmed) return;

    try {
      final studentResult = _db
          .collection('examResults')
          .doc(widget.examId)
          .collection('students')
          .doc(row.uid);
      if (allowRetake) {
        await deleteStudentExamResult(
          examId: widget.examId,
          studentId: row.uid,
        );
      } else {
        await studentResult.update({
          'currentIndex': 'stopped',
          'status': 'incomplete',
        });
      }
      if (!dialogContext.mounted) return;
      Navigator.of(dialogContext).pop();
      if (!mounted) return;
      AppToast.show(
        context,
        allowRetake
            ? 'Student is now allowed to retake the exam.'
            : 'Student exam session stopped.',
        title: allowRetake ? 'Retake allowed' : 'Exam stopped',
        tone: AppTone.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        'Unable to $action for this student: $error',
        title: 'Action failed',
        tone: AppTone.error,
      );
    }
  }
}

class _MonitoringStudent {
  final String uid;
  final String name;
  final String studentNo;
  final String? photoUrl;
  final String status;
  final bool hasStarted;
  final bool hasResultDocument;
  final bool isOnline;
  final int? currentIndex;
  final DateTime? lastSeen;
  final int flags;
  final int? score;
  final int? total;
  final DateTime? startedAt;
  final DateTime? submittedAt;
  final DateTime? lastFlagAt;
  final int clipCount;
  final String? incompleteReason;

  const _MonitoringStudent({
    required this.uid,
    required this.name,
    required this.studentNo,
    required this.photoUrl,
    required this.status,
    required this.hasStarted,
    required this.hasResultDocument,
    required this.isOnline,
    required this.currentIndex,
    required this.lastSeen,
    required this.flags,
    required this.score,
    required this.total,
    required this.startedAt,
    required this.submittedAt,
    required this.lastFlagAt,
    required this.clipCount,
    required this.incompleteReason,
  });
}

// ============================================================
// CLIPS POPUP (camera / screen recordings)
// ============================================================

class _Clip {
  final int number;
  final int startCount;
  final int endCount;
  final DateTime? occurredAt;
  final String fileName;
  final String? url;
  _Clip({
    required this.number,
    required this.startCount,
    required this.endCount,
    required this.occurredAt,
    required this.fileName,
    required this.url,
  });
}

class _ClipsDialog extends StatefulWidget {
  final String examId;
  final _MonitoringStudent student;
  final bool isPc;
  final String initialKind; // 'camera' | 'screen'

  const _ClipsDialog({
    required this.examId,
    required this.student,
    required this.isPc,
    required this.initialKind,
  });

  @override
  State<_ClipsDialog> createState() => _ClipsDialogState();
}

class _ClipsDialogState extends State<_ClipsDialog> {
  static const Color _ink = Color(0xFF29292C);
  static const Color _muted = Color(0xFF85858A);
  static const Color _border = Color(0xFFE0E0DE);

  final _db = FirebaseFirestore.instance;
  late String _kind = widget.initialKind == 'screen' && widget.isPc
      ? 'screen'
      : 'camera';
  late Stream<List<_Clip>> _stream = _clipsStream(_kind);

  Stream<List<_Clip>> _clipsStream(String kind) {
    return _db
        .collection('examResults')
        .doc(widget.examId)
        .collection('students')
        .doc(widget.student.uid)
        .collection('cheatClips')
        .snapshots()
        .asyncMap((snapshot) async {
          final futures = snapshot.docs.map((d) async {
            final m = d.data();
            final file = (m['files'] as Map?)?[kind] as Map?;
            if (file == null || file['path'] == null) return null;

            String? url;
            try {
              url = await FirebaseStorage.instance
                  .ref('${file['path']}')
                  .getDownloadURL();
            } on FirebaseException catch (error) {
              if (error.code != 'object-not-found') rethrow;
            }

            return _Clip(
              number: (m['number'] as num?)?.toInt() ?? int.tryParse(d.id) ?? 0,
              startCount:
                  (m['startCheatCount'] as num?)?.toInt() ??
                  (m['cheatCount'] as num?)?.toInt() ??
                  0,
              endCount:
                  (m['endCheatCount'] as num?)?.toInt() ??
                  (m['cheatCount'] as num?)?.toInt() ??
                  0,
              occurredAt: (m['occurredAt'] as Timestamp?)?.toDate(),
              fileName: '${file['fileName'] ?? ''}',
              url: url,
            );
          });
          final clips = (await Future.wait(
            futures,
          )).whereType<_Clip>().toList();
          clips.sort((a, b) => a.number.compareTo(b.number));
          return clips;
        });
  }

  void _setKind(String kind) {
    if (kind == _kind) return;
    setState(() {
      _kind = kind;
      _stream = _clipsStream(kind);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.video_library_outlined,
                      size: 20,
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Evidence clips',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.student.studentNo} · ${widget.student.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: _muted),
                  ),
                ],
              ),
            ),
            if (widget.isPc)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    _kindChip('camera', 'Camera', Icons.videocam_outlined),
                    const SizedBox(width: 8),
                    _kindChip(
                      'screen',
                      'Screen recording',
                      Icons.desktop_windows_outlined,
                    ),
                  ],
                ),
              ),
            const Divider(height: 1, color: _border),
            Flexible(
              child: StreamBuilder<List<_Clip>>(
                stream: _stream,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return _note(
                      Icons.error_outline,
                      "Couldn't load clips.\n${snap.error}",
                      AppTheme.error,
                    );
                  }
                  if (!snap.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.accent,
                        ),
                      ),
                    );
                  }
                  final clips = snap.data!;
                  if (clips.isEmpty) {
                    return _note(
                      Icons.videocam_off_outlined,
                      _kind == 'camera'
                          ? 'No camera clips'
                          : 'No screen recordings',
                      _muted,
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(16),
                    itemCount: clips.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _clipTile(clips[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kindChip(String kind, String label, IconData icon) {
    final selected = _kind == kind;
    return Material(
      color: selected ? AppTheme.accent : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: selected ? AppTheme.accent : _border),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        onTap: () => _setKind(kind),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : const Color(0xFF4A4A4F),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF4A4A4F),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _note(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: color),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clipTile(_Clip clip) {
    final range = clip.startCount == clip.endCount
        ? 'Flag #${clip.endCount}'
        : 'Flags #${clip.startCount}–#${clip.endCount}';
    final time = clip.occurredAt == null
        ? null
        : DateFormat('MMM d, h:mm:ss a').format(clip.occurredAt!);
    final isPhoto = clip.fileName.toLowerCase().endsWith('.jpg');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Clip ${clip.number}',
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  range,
                  style: const TextStyle(
                    color: AppTheme.error,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (time != null)
                Text(time, style: const TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 10),
          if (clip.url == null)
            const Row(
              children: [
                Icon(Icons.videocam_off_outlined, size: 15, color: _muted),
                SizedBox(width: 6),
                Text(
                  'No video (file unavailable)',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            )
          else ...[
            if (isPhoto) ...[
              const Row(
                children: [
                  Icon(Icons.photo_camera_outlined, size: 14, color: _muted),
                  SizedBox(width: 6),
                  Text(
                    'Photo (video was interrupted)',
                    style: TextStyle(color: _muted, fontSize: 11.5),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ColoredBox(
                      color: Colors.black,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network(
                          clip.url!,
                          fit: BoxFit.contain,
                          webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ] else
              _ClipPreview(key: ValueKey(clip.url), url: clip.url!),
            const SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(clip.url!),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('Open'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: clip.url!));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 15),
                  label: const Text('Copy link'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: _border),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ClipPreview extends StatefulWidget {
  final String url;
  const _ClipPreview({super.key, required this.url});

  @override
  State<_ClipPreview> createState() => _ClipPreviewState();
}

class _ClipPreviewState extends State<_ClipPreview> {
  late final String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType =
        'clip-video-${identityHashCode(this)}-${DateTime.now().microsecondsSinceEpoch}';

    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final video = web.HTMLVideoElement()
        ..src = '${widget.url}#t=0.1'
        ..controls = true
        ..preload = 'metadata'
        ..muted = true
        ..setAttribute('playsinline', 'true')
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'contain'
        ..style.backgroundColor = '#000'
        ..style.border = 'none';
      return video;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: HtmlElementView(viewType: _viewType),
          ),
        ),
      ),
    );
  }
}

class _ClipCell extends StatefulWidget {
  final String examId, uid, kind, status;
  final bool compact;
  final int clipCount;
  final VoidCallback onOpen;

  const _ClipCell({
    required this.examId,
    required this.uid,
    required this.kind,
    required this.status,
    required this.compact,
    required this.clipCount,
    required this.onOpen,
  });

  @override
  State<_ClipCell> createState() => _ClipCellState();
}

class _ClipCellState extends State<_ClipCell> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  int? _count;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant _ClipCell old) {
    super.didUpdateWidget(old);
    if (old.examId != widget.examId ||
        old.uid != widget.uid ||
        old.clipCount != widget.clipCount ||
        old.status != widget.status) {
      _listen();
    }
  }

  void _listen() {
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('examResults')
        .doc(widget.examId)
        .collection('students')
        .doc(widget.uid)
        .collection('cheatClips')
        .snapshots()
        .listen(
          (snap) {
            var n = 0;
            for (final doc in snap.docs) {
              final files = doc.data()['files'];
              final file = files is Map ? files[widget.kind] : null;
              if (file is Map && '${file['path'] ?? ''}'.isNotEmpty) n++;
            }
            if (mounted) {
              setState(() {
                _count = n;
                _error = null;
              });
            }
          },
          onError: (Object error) {
            if (mounted) {
              setState(() => _error = error);
            }
          },
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    if (_error != null) {
      return Tooltip(
        message: 'Unable to load $kind clips: $_error',
        child: const Icon(Icons.error_outline, color: AppTheme.error, size: 15),
      );
    }
    if (_count == null) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.5),
      );
    }
    if (_count == 0) {
      return const Icon(
        Icons.remove_rounded,
        color: AppTheme.mutedText,
        size: 16,
      );
    }
    return Tooltip(
      message:
          'View $_count $kind ${kind == 'screen' ? 'recording(s)' : 'clip(s)'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: widget.onOpen,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 0 : 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                kind == 'camera'
                    ? Icons.videocam_outlined
                    : Icons.desktop_windows_outlined,
                color: AppTheme.accent,
                size: widget.compact ? 13 : 16,
              ),
              const SizedBox(width: 3),
              Text(
                '$_count',
                style: const TextStyle(
                  color: Color(0xFF29292C),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
