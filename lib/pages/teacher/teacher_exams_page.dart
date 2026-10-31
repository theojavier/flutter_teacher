import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '/helpers/app_theme.dart';
import '/widgets/app_dialog.dart';

class TeacherExamsPage extends StatefulWidget {
  const TeacherExamsPage({super.key});

  @override
  State<TeacherExamsPage> createState() => _TeacherExamsPageState();
}

class _TeacherExamsPageState extends State<TeacherExamsPage>
    with SingleTickerProviderStateMixin {
  static const Color _warning = Color(0xFFFBBF24);
  static const double _tableMinWidth = 960;
  static const _statusTabs = ['all', 'upcoming', 'ongoing', 'finished'];

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final DateFormat _dateFmt = DateFormat('MMM dd, yyyy');
  final DateFormat _timeFmt = DateFormat('hh:mm a');

  late final TabController _tabController;
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  // Loaded once (NOT in build) so rebuilds don't refetch the teacher id.
  late final Future<String?> _teacherIdFuture;

  // Created once teacherId is known, so typing in search doesn't resubscribe.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _examsStream;
  String? _streamTeacherId;

  String _searchQuery = '';
  String _statusFilter = 'all';
  final Set<String> _busy = {};
  Timer? _statusRefreshTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statusTabs.length, vsync: this);
    _teacherIdFuture = _loadTeacherId();
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _horizontalController.dispose();
    _verticalController.dispose();
    _searchController.dispose();
    _statusRefreshTimer?.cancel();
    super.dispose();
  }

  Future<String?> _loadTeacherId() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return doc.data()?['ID']?.toString();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _teacherIdFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return AppTheme.loadingScaffold();
        }

        final teacherId = snap.data;
        if (teacherId == null || teacherId.isEmpty) {
          return Scaffold(
            backgroundColor: AppTheme.bg,
            body: _centered(
              AppTheme.emptyCard(
                Icons.person_off_outlined,
                'Teacher ID not found',
              ),
            ),
          );
        }

        // Only this teacher's exams.
        // (Sorted on the device, so no Firestore composite index is needed.)
        if (_streamTeacherId != teacherId) {
          _streamTeacherId = teacherId;
          _examsStream = _db
              .collection('exams')
              .where('teacherId', isEqualTo: teacherId)
              .snapshots();
        }

        return Scaffold(
          backgroundColor: AppTheme.bg,
          appBar: _buildAppBar(),
          body: _buildBody(),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Create Exam'),
            onPressed: () => _addExam(teacherId),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final wide = MediaQuery.of(context).size.width >= 600;

    return AppBar(
      automaticallyImplyLeading: false,
      toolbarHeight: 80,
      titleSpacing: 16,
      backgroundColor: AppTheme.header,
      foregroundColor: AppTheme.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Row(
        children: [
          if (wide) ...[
            AppTheme.appBarIcon(Icons.quiz_outlined),
            const SizedBox(width: 12),
            const Text(
              'My Exams',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 24),
          ],
          Expanded(
            child: TextField(
              controller: _searchController,
              cursorColor: AppTheme.accent,
              style: const TextStyle(color: AppTheme.text),
              onChanged: (v) =>
                  setState(() => _searchQuery = v.trim().toLowerCase()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, color: AppTheme.accent),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(
                          Icons.close,
                          color: AppTheme.mutedText,
                          size: 18,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                hintText: 'Search subject, program or year',
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
                isDense: true,
                filled: true,
                fillColor: AppTheme.card,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
      bottom: TabBar(
        controller: _tabController,
        labelColor: AppTheme.text,
        unselectedLabelColor: AppTheme.mutedText,
        indicatorColor: AppTheme.accent,
        onTap: (i) => setState(() => _statusFilter = _statusTabs[i]),
        tabs: const [
          Tab(text: 'All'),
          Tab(text: 'Upcoming'),
          Tab(text: 'Ongoing'),
          Tab(text: 'Finished'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _examsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _centered(
            AppTheme.emptyCard(
              Icons.error_outline,
              'Could not load your exams. Check your connection and try again.',
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.accent),
          );
        }

        final all = snapshot.data!.docs.toList()
          ..sort(
            (a, b) => _startMillis(b.data()).compareTo(_startMillis(a.data())),
          );

        if (all.isEmpty) {
          return _centered(
            AppTheme.emptyCard(
              Icons.quiz_outlined,
              'No exams yet. Tap Create Exam to add your first one.',
            ),
          );
        }

        final exams = all.where(_matchesFilters).toList();
        if (exams.isEmpty) {
          return _centered(
            AppTheme.emptyCard(
              Icons.search_off,
              'No exams match your search or filter.',
            ),
          );
        }

        final showSwipeHint =
            MediaQuery.of(context).size.width < _tableMinWidth;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text(
                      exams.length == all.length
                          ? '${all.length} exams'
                          : '${exams.length} of ${all.length} exams',
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 12.5,
                      ),
                    ),
                    const Spacer(),
                    if (showSwipeHint) ...const [
                      Icon(
                        Icons.swap_horiz,
                        size: 16,
                        color: AppTheme.mutedText,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Swipe sideways for more',
                        style: TextStyle(
                          color: AppTheme.mutedText,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(child: _buildTable(exams)),
            ],
          ),
        );
      },
    );
  }

  Widget _centered(Widget child) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: child,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TABLE
  // ---------------------------------------------------------------------------

  Widget _buildTable(List<QueryDocumentSnapshot<Map<String, dynamic>>> exams) {
    final headerBg = Color.alphaBlend(
      Colors.black.withValues(alpha: 0.25),
      AppTheme.header,
    );
    const headStyle = TextStyle(
      color: AppTheme.text,
      fontWeight: FontWeight.bold,
      fontSize: 13,
    );

    DataColumn2 col(
      String label, {
      double? width,
      ColumnSize size = ColumnSize.M,
      bool center = false,
    }) {
      return DataColumn2(
        size: size,
        fixedWidth: width,
        label: Align(
          alignment: center ? Alignment.center : Alignment.centerLeft,
          child: Text(label, style: headStyle),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.header,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
            PointerDeviceKind.stylus,
          },
        ),
        child: DataTable2(
          scrollController: _verticalController,
          horizontalScrollController: _horizontalController,
          isHorizontalScrollBarVisible: true,
          isVerticalScrollBarVisible: true,
          minWidth: _tableMinWidth,
          columnSpacing: 12,
          horizontalMargin: 16,
          headingRowHeight: 52,
          dataRowHeight: 68,
          fixedLeftColumns: 1,
          fixedColumnsColor: AppTheme.header,
          fixedCornerColor: headerBg,
          headingRowColor: WidgetStateProperty.all(headerBg),
          border: TableBorder(
            horizontalInside: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
          columns: [
            col('Subject', size: ColumnSize.L),
            col('Program', width: 120),
            col('Year/Block', width: 110),
            col('Start', width: 140),
            col('End', width: 140),
            col('Status', width: 120, center: true),
            col('Actions', width: 200, center: true),
          ],
          rows: exams.map((doc) {
            final data = doc.data();
            final subject = (data['subject'] ?? '-').toString();
            final status = _statusOf(data);
            final monitoringEnabled = data['monitoringEnabled'] == true;

            return DataRow2(
              onTap: () => _editExam(doc.id, data),
              cells: [
                DataCell(
                  Text(
                    subject,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                DataCell(_plainText((data['program'] ?? '-').toString())),
                DataCell(_plainText((data['yearBlock'] ?? '-').toString())),
                DataCell(_dateCell(data['startTime'])),
                DataCell(_dateCell(data['endTime'])),
                DataCell(Center(child: _statusChip(status))),
                DataCell(
                  _actionButtons(
                    examId: doc.id,
                    subject: subject,
                    data: data,
                    monitoringEnabled: monitoringEnabled,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _plainText(String text) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: AppTheme.text, fontSize: 13),
    );
  }

  Widget _dateCell(dynamic value) {
    if (value is! Timestamp) {
      return const Text('-', style: TextStyle(color: AppTheme.mutedText));
    }
    final d = value.toDate();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _dateFmt.format(d),
          style: const TextStyle(color: AppTheme.text, fontSize: 13),
        ),
        const SizedBox(height: 2),
        Text(
          _timeFmt.format(d),
          style: const TextStyle(color: AppTheme.mutedText, fontSize: 12),
        ),
      ],
    );
  }

  Widget _statusChip(String status) {
    final finished = status == 'finished';
    final ongoing = status == 'ongoing';
    final color = finished
        ? AppTheme.error
        : ongoing
        ? AppTheme.success
        : _warning;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        finished
            ? 'Finished'
            : ongoing
            ? 'Ongoing'
            : 'Upcoming',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _actionButtons({
    required String examId,
    required String subject,
    required Map<String, dynamic> data,
    required bool monitoringEnabled,
  }) {
    final busy = _busy.contains(examId);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _actionIcon(
          icon: monitoringEnabled
              ? Icons.pause_circle_outline
              : Icons.play_circle_outline,
          tooltip: monitoringEnabled ? 'Stop monitoring' : 'Start monitoring',
          color: monitoringEnabled ? _warning : AppTheme.success,
          busy: busy,
          onTap: busy
              ? null
              : () => _toggleMonitoring(examId, monitoringEnabled, data),
        ),
        const SizedBox(width: 8),
        _actionIcon(
          icon: Icons.video_library_outlined,
          tooltip: 'View exam clips',
          color: _warning,
          onTap: busy ? null : () => context.push('/exam-clips/$examId'),
        ),
        const SizedBox(width: 8),
        _actionIcon(
          icon: Icons.edit_outlined,
          tooltip: 'Edit exam',
          color: AppTheme.accent,
          onTap: busy ? null : () => _editExam(examId, data),
        ),
        const SizedBox(width: 8),
        _actionIcon(
          icon: Icons.delete_outline,
          tooltip: 'Delete exam',
          color: AppTheme.error,
          onTap: busy ? null : () => _deleteExam(examId, subject),
        ),
      ],
    );
  }

  Widget _actionIcon({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: onTap == null ? 0.06 : 0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withValues(alpha: 0.35)),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          child: SizedBox(
            width: 40,
            height: 40,
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(icon, size: 20, color: color),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FILTERING / STATUS
  // ---------------------------------------------------------------------------

  int _startMillis(Map<String, dynamic> data) {
    final t = data['startTime'];
    return t is Timestamp ? t.millisecondsSinceEpoch : 0;
  }

  DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  bool _matchesFilters(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();

    final status = _statusOf(data);
    if (_statusFilter != 'all' && status != _statusFilter) return false;
    if (_searchQuery.isEmpty) return true;

    final haystack = [
      data['subject'],
      data['program'],
      data['yearBlock'],
    ].map((v) => (v ?? '').toString().toLowerCase()).join(' ');
    return haystack.contains(_searchQuery);
  }

  String _statusOf(Map<String, dynamic> data) {
    final raw = (data['status'] ?? '').toString().toLowerCase();
    if (['finished', 'finish', 'complete', 'completed'].contains(raw)) {
      return 'finished';
    }
    final now = DateTime.now();
    final start = _asDate(data['startTime']);
    final end = _asDate(data['endTime']);
    if (end != null && !now.isBefore(end)) {
      return 'finished';
    }
    if (['ongoing', 'on-going', 'on going'].contains(raw)) {
      return 'ongoing';
    }
    if (raw == 'upcoming') return 'upcoming';
    if (data['monitoringEnabled'] == true &&
        start != null &&
        end != null &&
        !now.isBefore(start) &&
        now.isBefore(end)) {
      return 'ongoing';
    }
    return 'upcoming';
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  void _addExam(String teacherId) {
    context.push(
      '/edit-exam',
      extra: {'teacherId': teacherId, 'docId': null, 'existing': null},
    );
  }

  void _editExam(String examId, Map<String, dynamic> data) {
    context.push(
      '/edit-exam/$examId',
      extra: {'docId': examId, 'existing': data},
    );
  }

  Future<void> _toggleMonitoring(
    String examId,
    bool currentlyEnabled,
    Map<String, dynamic> data,
  ) async {
    if (!currentlyEnabled) {
      final now = DateTime.now();
      final start = _asDate(data['startTime']);
      final end = _asDate(data['endTime']);
      if (start == null ||
          end == null ||
          now.isBefore(start) ||
          !now.isBefore(end)) {
        await AppDialog.alert(
          context,
          tone: AppTone.warning,
          title: 'Monitoring is unavailable',
          message:
              'Monitoring can only start at or after the exam start time and before the exam end time.',
        );
        return;
      }
    }

    if (currentlyEnabled) {
      final ok = await _confirm(
        title: 'Stop monitoring?',
        message:
            'Students will no longer be monitored for this exam. If no other '
            'exams are being monitored, the shared cleanup schedule will pause.',
        confirmLabel: 'Stop',
        tone: AppTone.warning,
      );
      if (!ok) return;
    }

    setState(() => _busy.add(examId));
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable(
            currentlyEnabled ? 'stopExamMonitoring' : 'startExamMonitoring',
          );
      final result = await callable.call({'examId': examId});
      if (currentlyEnabled) {
        final end = _asDate(data['endTime']);
        final ended = end != null && !DateTime.now().isBefore(end);
        await _db.collection('exams').doc(examId).update({
          'status': ended ? 'finished' : 'upcoming',
        });
      }
      final scheduleOk = (result.data as Map?)?['scheduleOk'] != false;

      await _showMonitoringResult(
        currentlyEnabled: currentlyEnabled,
        scheduleOk: scheduleOk,
      );
    } catch (e) {
      await _showMonitoringResult(
        currentlyEnabled: currentlyEnabled,
        error: _errorText(e),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(examId));
    }
  }

  Future<void> _deleteExam(String examId, String subject) async {
    final ok = await _confirm(
      title: 'Delete exam?',
      message:
          '"$subject" and its questions will be permanently deleted, '
          'along with the related student notifications.',
      confirmLabel: 'Delete',
      tone: AppTone.danger,
    );
    if (!ok) return;

    setState(() => _busy.add(examId));
    try {
      final examRef = _db.collection('exams').doc(examId);
      final examData = (await examRef.get()).data();

      final questionsSnap = await examRef.collection('questions').get();
      await Future.wait(questionsSnap.docs.map((q) => q.reference.delete()));

      await examRef.delete();

      if (examData != null) {
        final studentsSnap = await _db
            .collection('users')
            .where('role', isEqualTo: 'student')
            .where('program', isEqualTo: examData['program'])
            .where('yearBlock', isEqualTo: examData['yearBlock'])
            .get();

        await Future.wait(
          studentsSnap.docs.map((student) async {
            final notifSnap = await student.reference
                .collection('notifications')
                .where('examId', isEqualTo: examId)
                .get();
            await Future.wait(notifSnap.docs.map((n) => n.reference.delete()));
          }),
        );
      }

      await _showActionResult(
        title: 'Exam deleted',
        message: 'Exam and related notifications deleted.',
        tone: AppTone.success,
      );
    } catch (e) {
      await _showActionResult(
        title: 'Unable to delete exam',
        message: _errorText(e),
        tone: AppTone.error,
      );
    } finally {
      if (mounted) setState(() => _busy.remove(examId));
    }
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    AppTone tone = AppTone.info,
  }) async {
    return AppDialog.confirm(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      tone: tone,
    );
  }

  Future<void> _showMonitoringResult({
    required bool currentlyEnabled,
    bool scheduleOk = true,
    String? error,
  }) async {
    if (!mounted) return;

    final failed = error != null || !scheduleOk;
    final title = error != null
        ? 'Monitoring update failed'
        : currentlyEnabled
        ? 'Monitoring stopped'
        : 'Monitoring started';
    final message = error != null
        ? 'Could not ${currentlyEnabled ? 'stop' : 'start'} monitoring.\n$error'
        : !scheduleOk
        ? 'Monitoring was ${currentlyEnabled ? 'stopped' : 'started'}, but the automatic cleanup schedule could not be updated. Check the Cloud Function logs.'
        : currentlyEnabled
        ? 'Monitoring is stopped for this exam. If no other exams are being monitored, the shared cleanup schedule is paused until monitoring starts again.'
        : 'Monitoring is active for this exam. The shared cleanup schedule is running and checks monitored exams every minute.';

    await AppDialog.alert(
      context,
      title: title,
      message: message,
      tone: failed ? AppTone.error : AppTone.success,
    );
  }

  Future<void> _showActionResult({
    required String title,
    required String message,
    required AppTone tone,
  }) async {
    if (!mounted) return;
    await AppDialog.alert(context, title: title, message: message, tone: tone);
  }

  String _errorText(Object e) {
    if (e is FirebaseFunctionsException) return e.message ?? e.code;
    return e.toString();
  }
}
