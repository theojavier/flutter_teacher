// lib/pages/exam_clips_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

// ---------------------------------------------------------------------------
// DATA CONFIG: change these if your field names differ
// ---------------------------------------------------------------------------
const String kStudentsCollection = 'users'; // where student profiles live
const String kRoleField = ''; // set to '' to skip the role filter
const String kRoleValue = 'student';
const String kProgramField = 'program'; // field on BOTH exam and student docs
const String kYearBlockField = 'yearBlock'; // field on BOTH exam and student docs

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

  final _db = FirebaseFirestore.instance;
  final _searchCtrl = TextEditingController();
  late final Future<_ExamBundle> _bundleFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _bundleFuture = _loadBundle();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Data
  // -------------------------------------------------------------------------
  Future<_ExamBundle> _loadBundle() async {
    final examSnap = await _db.collection('exams').doc(widget.examId).get();
    if (!examSnap.exists) throw Exception('Exam not found');
    final exam = examSnap.data() ?? {};

    Query<Map<String, dynamic>> q = _db.collection(kStudentsCollection);
    if (kRoleField.isNotEmpty) q = q.where(kRoleField, isEqualTo: kRoleValue);
    final program = exam[kProgramField];
    final yearBlock = exam[kYearBlockField];
    if (program != null) q = q.where(kProgramField, isEqualTo: program);
    if (yearBlock != null) q = q.where(kYearBlockField, isEqualTo: yearBlock);

    final rosterSnap = await q.get();
    final roster = rosterSnap.docs.map((d) {
      final m = d.data();
      return _Student(
        uid: d.id,
        studentNo: '${m['studentId'] ?? m['studentNo'] ?? d.id}',
        name: _nameOf(m),
      );
    }).toList();

    return _ExamBundle(exam: exam, roster: roster);
  }
  static int? _asInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

  static String _nameOf(Map<String, dynamic> m) {
    final full = m['fullName'] ?? m['name'] ?? m['displayName'];
    if (full != null && '$full'.trim().isNotEmpty) return '$full';
    final parts = [m['firstName'], m['lastName']]
        .where((e) => e != null && '$e'.trim().isNotEmpty)
        .join(' ');
    return parts.isEmpty ? 'Unknown student' : parts;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get _resultsStream => _db
      .collection('examResults')
      .doc(widget.examId)
      .collection('students')
      .snapshots();

  List<_Row> _mergeRows(
    List<_Student> roster,
    QuerySnapshot<Map<String, dynamic>>? results,
  ) {
    final byUid = {for (final d in results?.docs ?? []) d.id: d.data()};
    final rows = roster.map((s) {
      final r = byUid[s.uid];
      return _Row(
        student: s,
        cheatCount: _asInt(r?['cheatingCount']) ?? _asInt(r?['cheatCount']) ?? 0,
        clipCount: (r?['cheatClipCount'] as num?)?.toInt() ?? 0,
        status: r?['status']?.toString(),
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
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTitleBar(),
              const SizedBox(height: 10),
              Expanded(
                child: FutureBuilder<_ExamBundle>(
                  future: _bundleFuture,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _emptyState(Icons.error_outline,
                          "Couldn't load exam details\n${snap.error}");
                    }
                    if (!snap.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: _accentColor),
                      );
                    }
                    return _buildContent(snap.data!);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(_ExamBundle bundle) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _resultsStream,
      builder: (context, snap) {
        final rows = _mergeRows(bundle.roster, snap.data);
        final q = _query.trim().toLowerCase();
        final filtered = q.isEmpty
            ? rows
            : rows
                .where((r) =>
                    r.student.name.toLowerCase().contains(q) ||
                    r.student.studentNo.toLowerCase().contains(q))
                .toList();

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildExamCard(bundle.exam, rows),
            const SizedBox(height: 10),
            _buildInstructionsCard(),
            const SizedBox(height: 10),
            _buildSearchField(),
            const SizedBox(height: 10),
            _buildTable(filtered, loading: !snap.hasData && !snap.hasError),
            const SizedBox(height: 12),
          ],
        );
      },
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
            color: Colors.black.withOpacity(0.25),
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
                  _accentColor.withOpacity(0.9),
                  _accentColor.withOpacity(0.25),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _accentColor.withOpacity(0.35),
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
              child: const Icon(Icons.video_library_outlined,
                  color: Colors.white, size: 18),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Exam Clips',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 3),
              _tag('CHEATING EVIDENCE'),
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
        color: Colors.black.withOpacity(0.25),
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
                  color: Colors.black.withOpacity(0.25),
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
    const double r = 20;
    final fmt = DateFormat('MMM d, yyyy h:mm a');
    final start = (exam['startTime'] as Timestamp?)?.toDate();
    final end = (exam['endTime'] as Timestamp?)?.toDate();
    final teacher =
        '${exam['creator'] ?? exam['teacher'] ?? exam['createdBy'] ?? 'Unknown'}';

    final info = <_DetailRow>[
      _DetailRow(Icons.person_outline, 'Teacher', teacher),
      if (exam[kProgramField] != null)
        _DetailRow(Icons.school_outlined, 'Program', '${exam[kProgramField]}'),
      if (exam[kYearBlockField] != null)
        _DetailRow(
            Icons.groups_outlined, 'Year & Block', '${exam[kYearBlockField]}'),
      if (start != null)
        _DetailRow(Icons.play_circle_outline, 'Start', fmt.format(start)),
      if (end != null)
        _DetailRow(Icons.event_available_outlined, 'End', fmt.format(end)),
    ];

    final flagged = rows.where((r) => r.cheatCount > 0).length;
    final withClips = rows.where((r) => r.clipCount > 0).length;

    return _doubleBorder(
      color: _accentColor.withOpacity(0.55),
      innerRadius: r,
      shadow: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_headerColorLight, _headerColor],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tag('SUBJECT'),
                  const SizedBox(height: 8),
                  Text(
                    '${exam['subject'] ?? 'Exam'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _statChip(Icons.people_outline, '${rows.length} students',
                          _accentColor),
                      _statChip(Icons.flag_outlined, '$flagged flagged',
                          flagged > 0 ? _errorColor : _successColor),
                      _statChip(Icons.videocam_outlined,
                          '$withClips with clips', _warnColor),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: _cardColor,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                children: [
                  for (var i = 0; i < info.length; i++)
                    _detail(info[i], shaded: i.isOdd),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detail(_DetailRow row, {required bool shaded}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
      decoration: BoxDecoration(
        color: shaded ? Colors.white.withOpacity(0.03) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(row.icon, size: 15, color: _accentColor.withOpacity(0.8)),
          const SizedBox(width: 8),
          Text(row.label,
              style: const TextStyle(fontSize: 12.5, color: _mutedTextColor)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _textColor,
              ),
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
    const double r = 16;
    const items = <List<String>>[
      [
        'Each clip is a short recording (about 3 seconds) captured at the moment a cheating event is detected.',
        'cheat',
      ],
      [
        'Cheat count: the number shown on a clip (for example #3 to #5) is the cheat count, or range of counts, that happened within that 3 second clip.',
        'count',
      ],
      [
        'The Cheat Count column is the total detected for the student, so one student can have many clips.',
        'total',
      ],
      [
        'Camera shows the student\'s webcam. Screen shows their shared screen. The same clip number in both views refers to the same moment.',
        'views',
      ],
      [
        'Tap View to see every clip with its video link. Open plays it in a new tab and Copy saves the link. "No video" means nothing was recorded.',
        'view',
      ],
      [
        'Review the evidence before taking action. Detection can trigger by mistake, so check the clip first.',
        'review',
      ],
    ];

    return _doubleBorder(
      color: _warnColor.withOpacity(0.55),
      innerRadius: r,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(
          color: _warnColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(r),
          border: Border.all(color: _warnColor.withOpacity(0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: _warnColor, size: 20),
                const SizedBox(width: 8),
                Text.rich(
                  const TextSpan(
                    children: [
                      TextSpan(
                        text: 'HOW TO READ THIS TABLE',
                        style: TextStyle(
                          color: _textColor,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle, size: 5, color: _warnColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item[0],
                        style: const TextStyle(
                          color: _textColor,
                          fontSize: 13,
                          height: 1.3,
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
        fillColor: _cardColor.withOpacity(0.6),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _accentColor),
        ),
      ),
    );
  }

  Widget _buildTable(List<_Row> rows, {required bool loading}) {
    const double r = 20;
    const double minWidth = 720;

    Widget body;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator(color: _accentColor)),
      );
    } else if (rows.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: _emptyState(Icons.people_outline,
            'No students found for this program and year block.'),
      );
    } else {
      body = Column(
        children: [
          for (var i = 0; i < rows.length; i++) _buildRow(rows[i], i),
        ],
      );
    }

    return _doubleBorder(
      color: _accentColor.withOpacity(0.35),
      innerRadius: r,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: Container(
          color: _cardColor,
          child: LayoutBuilder(
            builder: (context, c) {
              final width = c.maxWidth < minWidth ? minWidth : c.maxWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: Column(
                    children: [_buildHeaderRow(), body],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String text, {TextAlign align = TextAlign.left}) {
    return Text(
      text.toUpperCase(),
      textAlign: align,
      style: const TextStyle(
        color: Colors.white70,
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.0,
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_headerColorLight, _headerColor],
        ),
      ),
      child: Row(
        children: [
          Expanded(flex: 4, child: _headerCell('Student No. - Name')),
          Expanded(
              flex: 2,
              child: _headerCell('Cheat count', align: TextAlign.center)),
          Expanded(
              flex: 2, child: _headerCell('Camera', align: TextAlign.center)),
          Expanded(
              flex: 2,
              child: _headerCell('Screen recording', align: TextAlign.center)),
        ],
      ),
    );
  }

  Widget _buildRow(_Row row, int index) {
    final hasClips = row.clipCount > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: index.isOdd ? Colors.white.withOpacity(0.03) : Colors.transparent,
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row.student.studentNo} - ${row.student.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.status == null
                      ? 'Did not take the exam'
                      : _statusLabel(row.status!),
                  style: const TextStyle(color: _mutedTextColor, fontSize: 11),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Center(child: _countBadge(row.cheatCount)),
          ),
          Expanded(
  flex: 2,
  child: Center(
    child: hasClips
        ? _viewButton(
            icon: Icons.videocam_outlined,
            count: row.perKindCount,
            onTap: () => _openClipsDialog(row, _ClipKind.camera),
          )
        : _noVideo(),
  ),
),
          Expanded(
            flex: 2,
            child: Center(
              child: hasClips
                  ? _viewButton(
    icon: Icons.desktop_windows_outlined,
    count: row.perKindCount,
    onTap: () => _openClipsDialog(row, _ClipKind.screen),
  )
                  : _noVideo(),
            ),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(String s) =>
      s.isEmpty ? '-' : s[0].toUpperCase() + s.substring(1);

  Widget _countBadge(int count) {
    final color = count == 0
        ? _successColor
        : count < 3
            ? _warnColor
            : _errorColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          color: color,
          fontSize: 12.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _viewButton({
  required IconData icon,
  required int count,
  required VoidCallback onTap,
}) {
  return OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 16),
    label: Text('View ($count)'),
    style: OutlinedButton.styleFrom(
      foregroundColor: _textColor,
      side: BorderSide(color: _accentColor.withOpacity(0.7)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

  Widget _noVideo() {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.videocam_off_outlined, size: 15, color: _mutedTextColor),
        SizedBox(width: 6),
        Text('No video',
            style: TextStyle(color: _mutedTextColor, fontSize: 12)),
      ],
    );
  }

  Widget _emptyState(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _accentColor.withOpacity(0.35)),
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
    );
  }

  // -------------------------------------------------------------------------
  // Clips dialog
  // -------------------------------------------------------------------------
  Future<List<_Clip>> _loadClips(String uid, _ClipKind kind) async {
    final snap = await _db
        .collection('examResults')
        .doc(widget.examId)
        .collection('students')
        .doc(uid)
        .collection('cheatClips')
        .orderBy('number')
        .get();

    final clips = <_Clip>[];
    for (final d in snap.docs) {
      final m = d.data();
      final files = (m['files'] as Map?) ?? {};
      final file = files[kind.key] as Map?;
      if (file == null || file['path'] == null) continue;

      String? url;
      try {
        url = await FirebaseStorage.instance
            .ref('${file['path']}')
            .getDownloadURL();
      } catch (_) {
        url = null; // file missing (upload never finished) or no permission
      }

      clips.add(_Clip(
        number: (m['number'] as num?)?.toInt() ?? int.tryParse(d.id) ?? 0,
        startCount: (m['startCheatCount'] as num?)?.toInt() ??
            (m['cheatCount'] as num?)?.toInt() ??
            0,
        endCount: (m['endCheatCount'] as num?)?.toInt() ??
            (m['cheatCount'] as num?)?.toInt() ??
            0,
        occurredAt: (m['occurredAt'] as Timestamp?)?.toDate(),
        fileName: '${file['fileName'] ?? ''}',
        url: url,
      ));
    }
    return clips;
  }

  Future<void> _openClipsDialog(_Row row, _ClipKind kind) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final color = kind == _ClipKind.camera ? _accentColor : _warnColor;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: color.withOpacity(0.45)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
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
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: color.withOpacity(0.4)),
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
                                color: _mutedTextColor, fontSize: 12.5),
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
                  child: FutureBuilder<List<_Clip>>(
                    future: _loadClips(row.student.uid, kind),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return _dialogMessage(Icons.error_outline,
                            "Couldn't load clips.\n${snap.error}", _errorColor);
                      }
                      if (!snap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(28),
                          child: Center(
                            child: CircularProgressIndicator(
                                color: _accentColor),
                          ),
                        );
                      }
                      final clips = snap.data!;
                      if (clips.isEmpty) {
                        return _dialogMessage(Icons.videocam_off_outlined,
                            'No video', _mutedTextColor);
                      }
                      return ListView.separated(
                        shrinkWrap: true,
                        itemCount: clips.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) => _clipTile(clips[i], color),
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
                  color: color, fontSize: 14, fontWeight: FontWeight.w600),
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
        color: Colors.black.withOpacity(0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
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
                Text(time,
                    style: const TextStyle(
                        color: _mutedTextColor, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 10),
          if (clip.url == null)
            const Row(
              children: [
                Icon(Icons.videocam_off_outlined,
                    size: 15, color: _mutedTextColor),
                SizedBox(width: 6),
                Text('No video (file unavailable)',
                    style: TextStyle(color: _mutedTextColor, fontSize: 12.5)),
              ],
            )
          else ...[
            SelectableText(
              clip.url!,
              maxLines: 2,
              style: const TextStyle(color: _accentColor, fontSize: 11.5),
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
                        fontSize: 12.5, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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
                    side: BorderSide(color: Colors.white.withOpacity(0.25)),
                    textStyle: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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
enum _ClipKind {
  camera('camera', 'Camera', Icons.videocam_outlined),
  screen('screen', 'Screen recording', Icons.desktop_windows_outlined);

  final String key;
  final String label;
  final IconData icon;
  const _ClipKind(this.key, this.label, this.icon);
}

class _ExamBundle {
  final Map<String, dynamic> exam;
  final List<_Student> roster;
  _ExamBundle({required this.exam, required this.roster});
}

class _Student {
  final String uid;
  final String studentNo;
  final String name;
  _Student({required this.uid, required this.studentNo, required this.name});
}

class _Row {
  final _Student student;
  final int cheatCount;
  final int clipCount;
  final String? status;
  int get perKindCount => clipCount;
  _Row({
    required this.student,
    required this.cheatCount,
    required this.clipCount,
    required this.status,
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

class _DetailRow {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow(this.icon, this.label, this.value);
}