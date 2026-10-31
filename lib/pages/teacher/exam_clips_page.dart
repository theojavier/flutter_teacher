// lib/pages/exam_clips_page.dart
import 'dart:async';
import 'dart:math' as math;
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
import '../../widgets/app_dialog.dart';

// ---------------------------------------------------------------------------
// DATA CONFIG: change these if your field names differ
// ---------------------------------------------------------------------------
const String kStudentsCollection = 'users'; // where student profiles live
const String kRoleField = ''; // set to '' to skip the role filter
const String kRoleValue = 'student';
const String kProgramField = 'program'; // field on BOTH exam and student docs
const String kYearBlockField =
    'yearBlock'; // field on BOTH exam and student docs

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------
class ExamClipsPage extends StatefulWidget {
  final String examId;
  const ExamClipsPage({super.key, required this.examId});

  @override
  State<ExamClipsPage> createState() => _ExamClipsPageState();
}

class _ExamClipsPageState extends State<ExamClipsPage> {
  // Shared theme palette (same as TakeExamPage / ProfilePage)
  static const Color _bgColor = Color(0xFF0B1220);
  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);
  static const Color _successColor = Color(0xFF4ADE80);
  static const Color _errorColor = Color(0xFFF87171);
  static const Color _warnColor = Color(0xFFFBBF24);
  static const int _heartbeatTimeoutSeconds = 300;

  final _db = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _examStream = _db
      .collection('exams')
      .doc(widget.examId)
      .snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _resultsStream = _db
      .collection('examResults')
      .doc(widget.examId)
      .collection('students')
      .snapshots();
  late final Stream<DatabaseEvent> _presenceStream = FirebaseDatabase.instance
      .ref('examPresence/${widget.examId}')
      .onValue;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _cachedStudentsStream;
  Object? _cachedProgram;
  Object? _cachedYearBlock;
  String _query = '';
  DateTime _now = DateTime.now();
  Timer? _clock;

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

  // -------------------------------------------------------------------------
  // Data
  // -------------------------------------------------------------------------
  Stream<QuerySnapshot<Map<String, dynamic>>> _studentsStream(
    Map<String, dynamic> exam,
  ) {
    final program = exam[kProgramField];
    final yearBlock = exam[kYearBlockField];
    if (_cachedStudentsStream != null &&
        _cachedProgram == program &&
        _cachedYearBlock == yearBlock) {
      return _cachedStudentsStream!;
    }

    Query<Map<String, dynamic>> q = _db.collection(kStudentsCollection);
    if (kRoleField.isNotEmpty) q = q.where(kRoleField, isEqualTo: kRoleValue);
    if (program != null) q = q.where(kProgramField, isEqualTo: program);
    if (yearBlock != null) q = q.where(kYearBlockField, isEqualTo: yearBlock);
    _cachedProgram = program;
    _cachedYearBlock = yearBlock;
    return _cachedStudentsStream = q.snapshots();
  }

  Future<void> _setPlatform(bool isPc) async {
    try {
      await _db.collection('exams').doc(widget.examId).update({
        'isPc': isPc,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to change platform: $e')));
    }
  }

  static int? _asInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static DateTime? _asDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map((key, value) => MapEntry('$key', value));
    }
    return {};
  }

  static String _nameOf(Map<String, dynamic> m) {
    final full = m['fullName'] ?? m['name'] ?? m['displayName'];
    if (full != null && '$full'.trim().isNotEmpty) return '$full';
    final parts = [
      m['firstName'],
      m['lastName'],
    ].where((e) => e != null && '$e'.trim().isNotEmpty).join(' ');
    return parts.isEmpty ? 'Unknown student' : parts;
  }

  static String? _photoOf(Map<String, dynamic> student) {
    final value = student['profileImage'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  List<_Row> _mergeRows(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> roster,
    QuerySnapshot<Map<String, dynamic>>? results,
    Map<String, dynamic> presence,
  ) {
    final byUid = {for (final d in results?.docs ?? []) d.id: d.data()};
    final rows = roster.map((d) {
      final studentData = d.data();
      final student = _Student(
        uid: d.id,
        studentNo:
            '${studentData['studentId'] ?? studentData['studentNo'] ?? d.id}',
        name: _nameOf(studentData),
        photoUrl: _photoOf(studentData),
      );
      final result = byUid[student.uid] ?? <String, dynamic>{};
      final hasResultDocument = byUid.containsKey(student.uid);
      final studentPresence = _asMap(presence[student.uid]);
      final status = result['status']?.toString();
      final isFinished = status == 'completed' || status == 'incomplete';
      final heartbeat = _asDateTime(
        result['lastHeartbeatAt'] ?? result['lastSeenAt'],
      );
      final heartbeatIsFresh =
          heartbeat != null &&
          !heartbeat.isBefore(
            _now.subtract(const Duration(seconds: _heartbeatTimeoutSeconds)),
          );
      final presenceLastSeen = _asDateTime(studentPresence['lastSeen']);
      final presenceIsFresh =
          presenceLastSeen == null ||
          !presenceLastSeen.isBefore(
            _now.subtract(const Duration(seconds: 180)),
          );
      final presenceOnline = studentPresence['online'] == true;
      final isOnline =
          !isFinished &&
          (studentPresence.isEmpty
              ? result['isActive'] == true && heartbeatIsFresh
              : presenceOnline &&
                    presenceIsFresh &&
                    result['isActive'] == true &&
                    heartbeatIsFresh);
      final lastSeen = [heartbeat, presenceLastSeen]
          .whereType<DateTime>()
          .fold<DateTime?>(
            null,
            (latest, value) =>
                latest == null || value.isAfter(latest) ? value : latest,
          );
      final currentIndex = _asInt(result['currentIndex']);
      final startedAt = _asDateTime(result['startedAt']);
      final submittedAt = _asDateTime(result['submittedAt']);
      final hasStarted =
          status != null ||
          heartbeat != null ||
          startedAt != null ||
          currentIndex != null;

      return _Row(
        student: student,
        cheatCount:
            _asInt(result['cheatingCount']) ??
            _asInt(result['cheatCount']) ??
            0,
        clipCount: _asInt(result['cheatClipCount']) ?? 0,
        status: status,
        isOnline: isOnline,
        hasStarted: hasStarted,
        hasResultDocument: hasResultDocument,
        currentIndex: currentIndex,
        score: _asInt(result['score']),
        total: _asInt(result['total']),
        startedAt: startedAt,
        lastSeenAt: lastSeen,
        submittedAt: submittedAt,
        incompleteReason: result['incompleteReason']?.toString(),
        lastFlagAt: _asDateTime(result['lastCheatingUpdate']),
      );
    }).toList();

    rows.sort((a, b) {
      final c = b.cheatCount.compareTo(a.cheatCount);
      return c != 0 ? c : a.student.name.compareTo(b.student.name);
    });
    return rows;
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTitleBar(),
              const SizedBox(height: 10),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _examStream,
                builder: (context, examSnapshot) {
                  if (examSnapshot.hasError) {
                    return _emptyState(
                      Icons.error_outline,
                      "Couldn't load exam details\n${examSnapshot.error}",
                    );
                  }
                  if (!examSnapshot.hasData) return _loading();
                  if (!examSnapshot.data!.exists) {
                    return _emptyState(Icons.error_outline, 'Exam not found');
                  }

                  final exam = examSnapshot.data!.data() ?? {};
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _studentsStream(exam),
                    builder: (context, rosterSnapshot) {
                      if (rosterSnapshot.hasError) {
                        return _emptyState(
                          Icons.error_outline,
                          "Couldn't load student roster\n${rosterSnapshot.error}",
                        );
                      }
                      if (!rosterSnapshot.hasData) return _loading();
                      return _buildContent(exam, rosterSnapshot.data!.docs);
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loading() => const Padding(
    padding: EdgeInsets.symmetric(vertical: 48),
    child: Center(child: CircularProgressIndicator(color: _accentColor)),
  );

  Widget _buildContent(
    Map<String, dynamic> exam,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> roster,
  ) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _resultsStream,
      builder: (context, resultsSnapshot) {
        if (resultsSnapshot.hasError) {
          return _emptyState(
            Icons.error_outline,
            "Couldn't load exam results\n${resultsSnapshot.error}",
          );
        }
        return StreamBuilder<DatabaseEvent>(
          stream: _presenceStream,
          builder: (context, presenceSnapshot) {
            final presence = _asMap(presenceSnapshot.data?.snapshot.value);
            final rows = _mergeRows(roster, resultsSnapshot.data, presence);
            final query = _query.trim().toLowerCase();
            final filtered = query.isEmpty
                ? rows
                : rows
                      .where(
                        (row) =>
                            row.student.name.toLowerCase().contains(query) ||
                            row.student.studentNo.toLowerCase().contains(query),
                      )
                      .toList();

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildExamCard(exam, rows),
                if (presenceSnapshot.hasError) ...[
                  const SizedBox(height: 6),
                  _buildPresenceWarning(presenceSnapshot.error),
                ],
                const SizedBox(height: 8),
                _buildInstructionsCard(),
                const SizedBox(height: 8),
                _buildSearchField(),
                const SizedBox(height: 8),
                _buildTable(
                  filtered,
                  isPc: exam['isPc'] is bool ? exam['isPc'] as bool : true,
                  loading:
                      !resultsSnapshot.hasData && !resultsSnapshot.hasError,
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPresenceWarning(Object? error) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _warnColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _warnColor.withValues(alpha: 0.45)),
      ),
      child: Text(
        'Realtime presence is unavailable. Showing the latest heartbeat where available.\n$error',
        style: const TextStyle(color: _warnColor, fontSize: 12),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Title bar
  // -------------------------------------------------------------------------
  Widget _buildTitleBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_headerColorLight, _headerColor],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          if (context.canPop())
            IconButton(
              tooltip: 'Back',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => context.pop(),
            ),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _accentColor.withValues(alpha: 0.9),
                  _accentColor.withValues(alpha: 0.25),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _accentColor.withValues(alpha: 0.35),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.video_library_outlined,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Live Exam Monitor',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              _tag('REALTIME STUDENT ACTIVITY'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _doubleBorder({
    required Color color,
    required double innerRadius,
    required Widget child,
    bool shadow = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(innerRadius + 3),
        border: Border.all(color: color, width: 1.5),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }

  // -------------------------------------------------------------------------
  // Exam info card
  // -------------------------------------------------------------------------
  Widget _buildExamCard(Map<String, dynamic> exam, List<_Row> rows) {
    final isPc = exam['isPc'] is bool ? exam['isPc'] as bool : true;
    final start = _asDateTime(exam['startTime']);
    final end = _asDateTime(exam['endTime']);
    final teacher =
        '${exam['creator'] ?? exam['teacher'] ?? exam['createdBy'] ?? 'Unknown teacher'}';
    final subtitle = [
      if (exam[kProgramField] != null) '${exam[kProgramField]}',
      if (exam[kYearBlockField] != null) '${exam[kYearBlockField]}',
    ].join('  ·  ');
    final examTime = [
      if (start != null) 'Starts ${DateFormat('MMM d, h:mm a').format(start)}',
      if (end != null) 'Ends ${DateFormat('MMM d, h:mm a').format(end)}',
    ].join('  ·  ');
    final meta = [
      subtitle,
      examTime,
    ].where((value) => value.isNotEmpty).join('  ·  ');
    final flagged = rows.where((row) => row.cheatCount > 0).length;
    final withClips = rows.where((row) => row.clipCount > 0).length;
    final online = rows.where((row) => row.isOnline).length;
    final offline = rows
        .where((row) => row.hasStarted && !row.isOnline && !_isFinished(row))
        .length;
    final completed = rows.where((row) => row.status == 'completed').length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final xl = width >= 1300;
        final large = width >= 900;
        final medium = width >= 600;
        final scale = xl
            ? 1.45
            : large
            ? 1.25
            : medium
            ? 1.1
            : 1.0;
        final titleSize = xl
            ? 34.0
            : large
            ? 26.0
            : medium
            ? 20.0
            : 16.0;
        final teacherSize = xl
            ? 17.0
            : large
            ? 14.0
            : medium
            ? 12.5
            : 10.5;
        final metaSize = xl
            ? 15.0
            : large
            ? 13.0
            : medium
            ? 12.0
            : 10.5;
        final padH = xl
            ? 32.0
            : large
            ? 24.0
            : medium
            ? 16.0
            : 12.0;
        final padV = xl
            ? 26.0
            : large
            ? 18.0
            : medium
            ? 12.0
            : 8.0;
        final labels = medium;
        String statText(int value, String label) =>
            labels ? '$value $label' : '$value';
        final stats = [
          _statChip(
            Icons.people_outline,
            statText(rows.length, 'students'),
            _accentColor,
            size: scale,
          ),
          _statChip(
            Icons.edit_note_rounded,
            statText(online, 'taking exam'),
            _successColor,
            size: scale,
          ),
          _statChip(
            Icons.link_off_rounded,
            statText(offline, 'disconnected'),
            offline > 0 ? _warnColor : _mutedTextColor,
            size: scale,
          ),
          _statChip(
            Icons.task_alt_rounded,
            statText(completed, 'completed'),
            _accentColor,
            size: scale,
          ),
          _statChip(
            Icons.flag_outlined,
            statText(flagged, 'flagged'),
            flagged > 0 ? _errorColor : _successColor,
            size: scale,
          ),
          _statChip(
            Icons.videocam_outlined,
            statText(withClips, 'with clips'),
            _warnColor,
            size: scale,
          ),
        ];

        return _doubleBorder(
          color: _accentColor.withValues(alpha: 0.55),
          innerRadius: 12,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_headerColorLight, _headerColor],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${exam['subject'] ?? 'Exam'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _textColor,
                      fontSize: titleSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 2 * scale),
                  Text(
                    'Teacher: $teacher',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _mutedTextColor,
                      fontSize: teacherSize,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    SizedBox(height: 2 * scale),
                    Text(
                      meta,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _mutedTextColor,
                        fontSize: metaSize,
                      ),
                    ),
                  ],
                  SizedBox(height: 8 * scale),
                  Wrap(
                    spacing: 6 * scale,
                    runSpacing: 5 * scale,
                    children: stats,
                  ),
                  SizedBox(height: 8 * scale),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPc
                            ? Icons.desktop_windows_outlined
                            : Icons.smartphone_outlined,
                        size: 16,
                        color: _mutedTextColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isPc ? 'PC exam' : 'Mobile exam',
                        style: TextStyle(color: _textColor, fontSize: metaSize),
                      ),
                      const SizedBox(width: 6),
                      Switch(
                        value: isPc,
                        activeThumbColor: _accentColor,
                        onChanged: (value) => _setPlatform(value),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statChip(
    IconData icon,
    String text,
    Color color, {
    double size = 1.0,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 7 * size, vertical: 4 * size),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12 * size, color: color),
          SizedBox(width: 4 * size),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 10 * size,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Instructions (top of the table)
  // -------------------------------------------------------------------------
  Widget _buildInstructionsCard() {
    const items = <String>[
      'Taking exam means the student has a live exam connection and a recent heartbeat. A stale heartbeat shows as Disconnected.',
      'Progress shows the last saved question. Select a student row for score, timestamps, and exam details.',
      'Select a camera or screen clip to review evidence. Check clips before acting; flags can be false positives.',
      'Use Stop Exam or Allow Retake in the student details popup to manage an attempt.',
    ];

    return _doubleBorder(
      color: _warnColor.withValues(alpha: 0.55),
      innerRadius: 12,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 4),
        decoration: BoxDecoration(
          color: _warnColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _warnColor.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: _warnColor,
                  size: 16,
                ),
                const SizedBox(width: 6),
                const Text(
                  'MONITORING GUIDE',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Icon(Icons.circle, size: 5, color: _warnColor),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: _textColor,
                          fontSize: 10.5,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Search + table
  // -------------------------------------------------------------------------
  Widget _buildSearchField() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _query = v),
      style: const TextStyle(color: _textColor),
      decoration: InputDecoration(
        hintText: 'Search student no. or name',
        hintStyle: const TextStyle(color: _mutedTextColor),
        prefixIcon: const Icon(Icons.search, color: _mutedTextColor),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, color: _mutedTextColor),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: _cardColor.withValues(alpha: 0.6),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accentColor),
        ),
      ),
    );
  }

  Widget _buildTable(
    List<_Row> rows, {
    required bool isPc,
    required bool loading,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accentColor.withValues(alpha: 0.35)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final showLastSeen = constraints.maxWidth >= 900;
          if (loading) {
            return _loading();
          }
          if (rows.isEmpty) {
            return _emptyState(
              Icons.people_outline,
              'No students found for this program and year block.',
            );
          }

          const headingHeight = 38.0;
          final rowHeight = compact ? 48.0 : 52.0;
          final tableHeight = headingHeight + rows.length * rowHeight + 8;
          const compactSpacing = 2.0;
          const compactMargin = 4.0;
          const compactStudentMin = 96.0;
          final compactOthers = isPc ? 212.0 : 176.0;
          final compactColumns = isPc ? 7 : 6;
          final compactMinWidth =
              compactStudentMin +
              compactOthers +
              compactMargin * 2 +
              compactSpacing * (compactColumns - 1) +
              2;

          DataColumn2 column(
            String label, {
            ColumnSize size = ColumnSize.M,
            bool centered = false,
            double? fixedWidth,
          }) {
            return DataColumn2(
              size: size,
              fixedWidth: fixedWidth,
              label: Align(
                alignment: centered ? Alignment.center : Alignment.centerLeft,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            );
          }

          return SizedBox(
            height: tableHeight,
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(
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
                fixedColumnsColor: _cardColor,
                fixedCornerColor: _headerColor,
                isHorizontalScrollBarVisible: false,
                isVerticalScrollBarVisible: false,
                headingRowColor: WidgetStateProperty.all(_headerColor),
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                columns: [
                  column('STUDENT', size: ColumnSize.L),
                  column(
                    compact ? 'LIVE' : 'ACTIVITY',
                    size: ColumnSize.S,
                    centered: true,
                    fixedWidth: compact ? 32 : null,
                  ),
                  column(
                    compact ? 'EXAM' : 'STATUS',
                    size: ColumnSize.M,
                    centered: true,
                    fixedWidth: compact ? 34 : null,
                  ),
                  column(
                    'PROGRESS',
                    size: ColumnSize.M,
                    centered: true,
                    fixedWidth: compact ? 40 : null,
                  ),
                  if (showLastSeen)
                    column('LAST SEEN', size: ColumnSize.S, centered: true),
                  column(
                    compact ? '!' : 'FLAGS',
                    size: ColumnSize.S,
                    centered: true,
                    fixedWidth: compact ? 34 : null,
                  ),
                  column(
                    compact ? 'CAM' : 'CAMERA',
                    size: ColumnSize.S,
                    centered: true,
                    fixedWidth: compact ? 36 : null,
                  ),
                  if (isPc)
                    column(
                      compact ? 'SCR' : 'SCREEN',
                      size: ColumnSize.S,
                      centered: true,
                      fixedWidth: compact ? 36 : null,
                    ),
                ],
                rows: rows.map((row) {
                  final progress = row.currentIndex != null
                      ? 'Q${row.currentIndex}'
                      : row.status == 'incomplete'
                      ? 'Stopped'
                      : '—';
                  final elapsed = row.startedAt == null
                      ? (row.hasStarted ? 'Started' : 'Not started')
                      : _durationLabel(_now.difference(row.startedAt!));
                  return DataRow2(
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
                              row.student.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _textColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              row.student.studentNo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _mutedTextColor,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Center(child: _presenceBadge(row, compact: compact)),
                      ),
                      DataCell(
                        Center(child: _statusBadge(row, compact: compact)),
                      ),
                      DataCell(
                        SizedBox(
                          width: double.infinity,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                progress,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: _textColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (!compact)
                                Text(
                                  elapsed,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _mutedTextColor,
                                    fontSize: 9,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (showLastSeen)
                        DataCell(
                          Center(
                            child: Text(
                              _relativeTime(row.lastSeenAt),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _mutedTextColor,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      DataCell(
                        Center(
                          child: _countBadge(row.cheatCount, compact: compact),
                        ),
                      ),
                      DataCell(
                        Center(
                          child: _clipCell(
                            row,
                            _ClipKind.camera,
                            Icons.videocam_outlined,
                            compact: compact,
                          ),
                        ),
                      ),
                      if (isPc)
                        DataCell(
                          Center(
                            child: _clipCell(
                              row,
                              _ClipKind.screen,
                              Icons.desktop_windows_outlined,
                              compact: compact,
                            ),
                          ),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _clipCell(
    _Row row,
    _ClipKind kind,
    IconData icon, {
    required bool compact,
  }) {
    if (row.clipCount == 0) {
      return const Icon(Icons.remove_rounded, color: _mutedTextColor, size: 16);
    }
    return Tooltip(
      message: 'View ${kind.label.toLowerCase()} clips (${row.clipCount})',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openClipsDialog(row, kind),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 0 : 5,
            vertical: 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _accentColor, size: compact ? 12 : 16),
              SizedBox(width: compact ? 1 : 3),
              Text(
                '${row.clipCount}',
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static bool _isFinished(_Row row) =>
      row.status == 'completed' || row.status == 'incomplete';

  Widget _presenceBadge(_Row row, {bool compact = false}) {
    final String label;
    final Color color;
    final IconData icon;

    if (_isFinished(row)) {
      label = 'Finished';
      color = _mutedTextColor;
      icon = Icons.check_circle_outline_rounded;
    } else if (row.isOnline) {
      label = 'Taking exam';
      color = _successColor;
      icon = Icons.edit_note_rounded;
    } else if (row.hasStarted) {
      label = 'Disconnected';
      color = _warnColor;
      icon = Icons.link_off_rounded;
    } else {
      label = 'Not started';
      color = _mutedTextColor;
      icon = Icons.remove_circle_outline;
    }

    if (compact) {
      return Tooltip(
        message: label,
        child: Icon(icon, size: 15, color: color),
      );
    }
    return _smallBadge(label, color, icon: icon);
  }

  Widget _statusBadge(_Row row, {bool compact = false}) {
    final status = row.status;
    final color = status == 'completed'
        ? _successColor
        : status == 'incomplete'
        ? _errorColor
        : status == 'in-progress'
        ? _accentColor
        : _mutedTextColor;
    final label = status == null ? 'Pending' : _statusLabel(status);
    final icon = status == 'completed'
        ? Icons.check_circle_rounded
        : status == 'incomplete'
        ? Icons.error_rounded
        : status == 'in-progress'
        ? Icons.play_circle_fill_rounded
        : Icons.hourglass_empty_rounded;
    if (compact) {
      return Tooltip(
        message: label,
        child: Icon(icon, color: color, size: 16),
      );
    }
    return _smallBadge(label, color, icon: icon);
  }

  Widget _smallBadge(String label, Color color, {required IconData icon}) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _relativeTime(DateTime? time) {
    if (time == null) return 'No heartbeat';
    final age = DateTime.now().difference(time);
    if (age.isNegative || age.inSeconds < 10) return 'Just now';
    if (age.inMinutes < 1) return '${age.inSeconds}s ago';
    if (age.inHours < 1) return '${age.inMinutes}m ago';
    if (age.inDays < 1) return '${age.inHours}h ago';
    return '${age.inDays}d ago';
  }

  static String _durationLabel(Duration duration) {
    if (duration.isNegative) return 'Started recently';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '${hours}h ${minutes}m elapsed';
    return '${duration.inMinutes}m elapsed';
  }

  Future<void> _showStudentDetails(_Row row) {
    if (!row.hasStarted || !row.hasResultDocument) {
      return Future<void>.value();
    }

    final dateFormat = DateFormat('MMM d, yyyy · h:mm a');
    String dateLabel(DateTime? value) =>
        value == null ? 'Not recorded' : dateFormat.format(value);
    final score = row.score == null
        ? 'Not recorded'
        : '${row.score}${row.total == null ? '' : ' / ${row.total}'}';
    final flagColor = row.cheatCount == 0
        ? _successColor
        : row.cheatCount < 3
        ? _warnColor
        : _errorColor;

    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 460,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.88,
          ),
          child: CustomPaint(
            painter: _HumpCardPainter(
              fillTop: _headerColorLight,
              fill: _cardColor,
              border: _accentColor.withValues(alpha: 0.55),
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: _kHumpRadius * 2,
                      child: Center(child: _studentAvatar(row.student)),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Column(
                        children: [
                          Text(
                            row.student.name,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _textColor,
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            row.student.studentNo,
                            style: const TextStyle(
                              color: _mutedTextColor,
                              fontSize: 12.5,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 6,
                            children: [_presenceBadge(row), _statusBadge(row)],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _detailSection('EXAM ATTEMPT', [
                              _detailRow(
                                Icons.help_outline_rounded,
                                'Current question',
                                row.currentIndex?.toString() ??
                                    (row.status == 'incomplete'
                                        ? 'Stopped'
                                        : 'Not recorded'),
                              ),
                              _detailRow(Icons.grade_outlined, 'Score', score),
                              _detailRow(
                                Icons.play_arrow_rounded,
                                'Started',
                                dateLabel(row.startedAt),
                              ),
                              _detailRow(
                                Icons.visibility_outlined,
                                'Last seen',
                                dateLabel(row.lastSeenAt),
                              ),
                              _detailRow(
                                Icons.task_alt_rounded,
                                'Submitted',
                                dateLabel(row.submittedAt),
                              ),
                            ]),
                            const SizedBox(height: 14),
                            _detailSection('INTEGRITY', [
                              _detailRow(
                                Icons.flag_outlined,
                                'Cheating flags',
                                '${row.cheatCount}',
                                valueColor: flagColor,
                              ),
                              _detailRow(
                                Icons.schedule_rounded,
                                'Latest flag',
                                dateLabel(row.lastFlagAt),
                              ),
                              _detailRow(
                                Icons.videocam_outlined,
                                'Evidence clips',
                                '${row.clipCount}',
                              ),
                            ]),
                            if (row.incompleteReason?.isNotEmpty == true) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _errorColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _errorColor.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.error_outline_rounded,
                                      size: 16,
                                      color: _errorColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Incomplete reason: ${row.incompleteReason}',
                                        style: const TextStyle(
                                          color: _textColor,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _confirmStudentAction(
                                dialogContext,
                                row,
                                allowRetake: false,
                              ),
                              icon: const Icon(
                                Icons.stop_circle_outlined,
                                size: 18,
                              ),
                              label: const Text('Stop Exam'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _errorColor,
                                minimumSize: const Size(0, 44),
                                side: BorderSide(
                                  color: _errorColor.withValues(alpha: 0.6),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _confirmStudentAction(
                                dialogContext,
                                row,
                                allowRetake: true,
                              ),
                              icon: const Icon(Icons.restart_alt, size: 18),
                              label: const Text('Allow Retake'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _accentColor,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                minimumSize: const Size(0, 44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: _kHumpBoxTop + 6,
                  right: 6,
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close, color: _mutedTextColor),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _studentAvatar(_Student student) {
    const diameter = 84.0;
    final initials = student.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    final fallback = Container(
      width: diameter,
      height: diameter,
      color: _headerColorLight,
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    return Container(
      width: diameter + 8,
      height: diameter + 8,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accentColor, _accentColor.withValues(alpha: 0.3)],
        ),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withValues(alpha: 0.35),
            blurRadius: 14,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipOval(
        child: student.photoUrl == null
            ? fallback
            : Image.network(
                student.photoUrl!,
                width: diameter,
                height: diameter,
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                errorBuilder: (_, _, _) => fallback,
                loadingBuilder: (_, child, progress) =>
                    progress == null ? child : fallback,
              ),
      ),
    );
  }

  Widget _detailSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            title,
            style: const TextStyle(
              color: _mutedTextColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _mutedTextColor),
          const SizedBox(width: 10),
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(color: _mutedTextColor, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? _textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmStudentAction(
    BuildContext detailsContext,
    _Row row, {
    required bool allowRetake,
  }) async {
    final action = allowRetake ? 'Allow Retake' : 'Stop Exam';
    final confirmed = await AppDialog.confirm(
      detailsContext,
      tone: allowRetake ? AppTone.info : AppTone.warning,
      icon: allowRetake ? Icons.restart_alt : Icons.stop_circle_outlined,
      title: allowRetake ? 'Allow a retake?' : 'Stop this exam?',
      detail: row.student.studentNo,
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
          .doc(row.student.uid);
      if (allowRetake) {
        await studentResult.delete();
      } else {
        await studentResult.update({
          'currentIndex': 'stopped',
          'status': 'incomplete',
        });
      }
      if (!detailsContext.mounted) return;
      Navigator.of(detailsContext).pop();
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

  static String _statusLabel(String s) =>
      s.isEmpty ? '-' : s[0].toUpperCase() + s.substring(1);

  Widget _countBadge(int count, {bool compact = false}) {
    final color = count == 0
        ? _successColor
        : count < 3
        ? _warnColor
        : _errorColor;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 12,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: color,
          fontSize: compact ? 10 : 12.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _emptyState(IconData icon, String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _accentColor.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, size: 28, color: _accentColor),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _mutedTextColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Clips dialog
  // -------------------------------------------------------------------------
  Stream<List<_Clip>> _clipsStream(String uid, _ClipKind kind) {
    return _db
        .collection('examResults')
        .doc(widget.examId)
        .collection('students')
        .doc(uid)
        .collection('cheatClips')
        .orderBy('number')
        .snapshots()
        .asyncMap((snapshot) async {
          final clips = <_Clip>[];
          for (final d in snapshot.docs) {
            final m = d.data();
            final files = (m['files'] as Map?) ?? {};
            final file = files[kind.key] as Map?;
            if (file == null || file['path'] == null) continue;

            String? url;
            try {
              url = await FirebaseStorage.instance
                  .ref('${file['path']}')
                  .getDownloadURL();
            } on FirebaseException catch (error) {
              if (error.code != 'object-not-found') rethrow;
            }

            clips.add(
              _Clip(
                number:
                    (m['number'] as num?)?.toInt() ?? int.tryParse(d.id) ?? 0,
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
              ),
            );
          }
          return clips;
        });
  }

  Future<void> _openClipsDialog(_Row row, _ClipKind kind) {
    final clipsStream = _clipsStream(row.student.uid, kind);
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final color = kind == _ClipKind.camera ? _accentColor : _warnColor;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: color.withValues(alpha: 0.45)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: color.withValues(alpha: 0.4)),
                      ),
                      child: Icon(kind.icon, size: 22, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${kind.label} clips',
                            style: const TextStyle(
                              color: _textColor,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${row.student.studentNo} - ${row.student.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _mutedTextColor,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: _mutedTextColor),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: StreamBuilder<List<_Clip>>(
                    stream: clipsStream,
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return _dialogMessage(
                          Icons.error_outline,
                          "Couldn't load clips.\n${snap.error}",
                          _errorColor,
                        );
                      }
                      if (!snap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(28),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: _accentColor,
                            ),
                          ),
                        );
                      }
                      final clips = snap.data!;
                      if (clips.isEmpty) {
                        return _dialogMessage(
                          Icons.videocam_off_outlined,
                          'No video',
                          _mutedTextColor,
                        );
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: clips.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _clipTile(clips[index], color),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dialogMessage(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clipTile(_Clip clip, Color color) {
    final range = clip.startCount == clip.endCount
        ? 'Cheat count #${clip.endCount}'
        : 'Cheat count #${clip.startCount} to #${clip.endCount}';
    final time = clip.occurredAt == null
        ? null
        : DateFormat('MMM d, h:mm:ss a').format(clip.occurredAt!);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Clip ${clip.number}',
                style: const TextStyle(
                  color: _textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              _statChip(Icons.flag_outlined, range, _errorColor),
              const Spacer(),
              if (time != null)
                Text(
                  time,
                  style: const TextStyle(
                    color: _mutedTextColor,
                    fontSize: 11.5,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (clip.url == null)
            const Row(
              children: [
                Icon(
                  Icons.videocam_off_outlined,
                  size: 15,
                  color: _mutedTextColor,
                ),
                SizedBox(width: 6),
                Text(
                  'No video (file unavailable)',
                  style: TextStyle(color: _mutedTextColor, fontSize: 12.5),
                ),
              ],
            )
          else ...[
            if (clip.fileName.toLowerCase().endsWith('.jpg')) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.photo_camera_outlined,
                    size: 14,
                    color: _warnColor,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Photo (video was interrupted)',
                    style: TextStyle(color: _warnColor, fontSize: 11.5),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: color.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(12),
                      ),
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
              _ClipPreview(
                key: ValueKey(clip.url),
                url: clip.url!,
                color: color,
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () => launchUrl(
                    Uri.parse(clip.url!),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Open'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
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
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy link'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textColor,
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                    textStyle: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
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

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------
const double _kHumpRadius = 50;
const double _kHumpBoxTop = 38;

enum _ClipKind {
  camera('camera', 'Camera', Icons.videocam_outlined),
  screen('screen', 'Screen recording', Icons.desktop_windows_outlined);

  final String key;
  final String label;
  final IconData icon;
  const _ClipKind(this.key, this.label, this.icon);
}

class _Student {
  final String uid;
  final String studentNo;
  final String name;
  final String? photoUrl;
  _Student({
    required this.uid,
    required this.studentNo,
    required this.name,
    required this.photoUrl,
  });
}

class _HumpCardPainter extends CustomPainter {
  final Color fillTop;
  final Color fill;
  final Color border;

  const _HumpCardPainter({
    required this.fillTop,
    required this.fill,
    required this.border,
  });

  static Path _path(Size size) {
    const cornerRadius = 18.0;
    final centerX = size.width / 2;
    final humpHalfWidth = math.sqrt(
      _kHumpRadius * _kHumpRadius -
          (_kHumpRadius - _kHumpBoxTop) * (_kHumpRadius - _kHumpBoxTop),
    );
    final humpLeft = centerX - humpHalfWidth;
    final humpRight = centerX + humpHalfWidth;

    return Path()
      ..moveTo(cornerRadius, _kHumpBoxTop)
      ..lineTo(humpLeft, _kHumpBoxTop)
      ..cubicTo(
        centerX - humpHalfWidth * 0.65,
        -2,
        centerX + humpHalfWidth * 0.65,
        -2,
        humpRight,
        _kHumpBoxTop,
      )
      ..lineTo(size.width - cornerRadius, _kHumpBoxTop)
      ..arcToPoint(
        Offset(size.width, _kHumpBoxTop + cornerRadius),
        radius: const Radius.circular(cornerRadius),
      )
      ..lineTo(size.width, size.height - cornerRadius)
      ..arcToPoint(
        Offset(size.width - cornerRadius, size.height),
        radius: const Radius.circular(cornerRadius),
      )
      ..lineTo(cornerRadius, size.height)
      ..arcToPoint(
        Offset(0, size.height - cornerRadius),
        radius: const Radius.circular(cornerRadius),
      )
      ..lineTo(0, _kHumpBoxTop + cornerRadius)
      ..arcToPoint(
        Offset(cornerRadius, _kHumpBoxTop),
        radius: const Radius.circular(cornerRadius),
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final path = _path(size);
    canvas.drawShadow(path, Colors.black.withValues(alpha: 0.6), 16, true);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [fillTop, fill],
          stops: const [0, 0.4],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = border,
    );
  }

  @override
  bool shouldRepaint(_HumpCardPainter oldDelegate) =>
      oldDelegate.fillTop != fillTop ||
      oldDelegate.fill != fill ||
      oldDelegate.border != border;
}

class _Row {
  final _Student student;
  final int cheatCount;
  final int clipCount;
  final String? status;
  final bool isOnline;
  final bool hasStarted;
  final bool hasResultDocument;
  final int? currentIndex;
  final int? score;
  final int? total;
  final DateTime? startedAt;
  final DateTime? lastSeenAt;
  final DateTime? submittedAt;
  final String? incompleteReason;
  final DateTime? lastFlagAt;
  int get perKindCount => clipCount;
  _Row({
    required this.student,
    required this.cheatCount,
    required this.clipCount,
    required this.status,
    required this.isOnline,
    required this.hasStarted,
    required this.hasResultDocument,
    required this.currentIndex,
    required this.score,
    required this.total,
    required this.startedAt,
    required this.lastSeenAt,
    required this.submittedAt,
    required this.incompleteReason,
    required this.lastFlagAt,
  });
}

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

class _ClipPreview extends StatefulWidget {
  final String url;
  final Color color;

  const _ClipPreview({super.key, required this.url, required this.color});

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
        constraints: const BoxConstraints(maxHeight: 220),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: widget.color.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: HtmlElementView(viewType: _viewType),
            ),
          ),
        ),
      ),
    );
  }
}
