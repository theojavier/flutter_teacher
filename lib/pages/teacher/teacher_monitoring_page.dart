import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'dart:ui_web' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../helpers/AppTheme.dart';

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
        await studentResult.delete();
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
