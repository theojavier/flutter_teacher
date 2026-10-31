import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '/helpers/AppTheme.dart';
import '/widgets/app_dialog.dart';
import '/widgets/exam_form_dialog.dart';

const Color _dashboardBlue = Color(0xFF153CFF);

class TeacherExamsPage extends StatefulWidget {
  const TeacherExamsPage({super.key});

  @override
  State<TeacherExamsPage> createState() => _TeacherExamsPageState();
}

class _TeacherExamsPageState extends State<TeacherExamsPage> {
  static const Color _warning = Color(0xFFFBBF24);
  // Fixed columns: # 44 + Start 142 + End 142 + Status 120 + Review 140 + Actions 190 = 778.
  // Flexible columns need at least 370, plus spacing (12 * 7) and margins (16 * 2).
  static const double _tableMinWidth = 1000;
  static const double _fabClearance = 88;
  static const double _headingRowHeight = 52;
  static const double _dataRowHeight = 68;
  static const int _pageSize = 10;

  static const _statusTabs = ['all', 'upcoming', 'ongoing', 'finished'];
  static const _reviewStatusTabs = [
    'all',
    'pending',
    'approved',
    'changes_requested',
    'draft',
  ];

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final DateFormat _dateFmt = DateFormat('MMM dd, yyyy');
  final DateFormat _timeFmt = DateFormat('hh:mm a');

  final ScrollController _horizontalController = ScrollController();
  final ScrollController _pageScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  // Loaded once (NOT in build) so rebuilds don't refetch the teacher id.
  late final Future<String?> _teacherIdFuture;

  // Created once teacherId is known, so typing in search doesn't resubscribe.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _examsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _classesStream;
  String? _streamTeacherId;

  String _searchQuery = '';
  String _statusFilter = 'all';
  String _reviewStatusFilter = 'all';
  int _page = 0;
  final Set<String> _busy = {};
  Timer? _statusRefreshTimer;
  String? _handledReviewToken;

  /// Keeps the table wide enough to avoid cramped columns while filling
  /// available space when the viewport is wider than the minimum.
  double _tableWidthFor(double available) =>
      available < _tableMinWidth ? _tableMinWidth : available;

  @override
  void initState() {
    super.initState();
    _teacherIdFuture = _loadTeacherId();
    _statusRefreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _horizontalController.dispose();
    _pageScrollController.dispose();
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
          final uid = FirebaseAuth.instance.currentUser?.uid;
          _classesStream = uid == null
              ? null
              : _db
                    .collection('classes')
                    .where('adviserId', isEqualTo: uid)
                    .snapshots();
        }

        return Scaffold(
          backgroundColor: AppTheme.bg,
          body: SafeArea(
            child: Scrollbar(
              controller: _pageScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _pageScrollController,
                padding: EdgeInsets.fromLTRB(
                  MediaQuery.of(context).size.width < 600 ? 16 : 24,
                  MediaQuery.of(context).size.width < 600 ? 16 : 24,
                  MediaQuery.of(context).size.width < 600 ? 16 : 24,
                  _fabClearance,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '02 / ASSESSMENT MANAGEMENT',
                      style: TextStyle(
                        color: _dashboardBlue,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Exams.', style: AppTheme.display(34, ls: -0.06)),
                    const SizedBox(height: 6),
                    const Text(
                      'Manage exam schedules, questions, and review status',
                      style: TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: AppTheme.cardDecoration(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [_buildCatalogHeader(), _buildBody()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Create Exam'),
            onPressed: _addExam,
          ),
        );
      },
    );
  }

  Widget _buildCatalogHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        color: AppTheme.header,
        border: Border(bottom: BorderSide(color: AppTheme.line)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Exam Library',
                style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.7,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Your exams, schedules, and review details',
                style: TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          );
          final search = _buildSearchField(fullWidth: compact);
          final filters = _buildStatusFilters();

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 14),
                search,
                const SizedBox(height: 12),
                filters,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 20),
                  search,
                ],
              ),
              const SizedBox(height: 16),
              filters,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField({required bool fullWidth}) {
    return SizedBox(
      width: fullWidth ? double.infinity : 380,
      height: 44,
      child: TextField(
        controller: _searchController,
        cursorColor: AppTheme.accent,
        style: const TextStyle(color: AppTheme.text, fontSize: 13),
        onChanged: (value) => setState(() {
          _searchQuery = value.trim().toLowerCase();
          _page = 0;
        }),
        decoration: InputDecoration(
          prefixIcon: const Icon(
            Icons.search,
            color: AppTheme.mutedText,
            size: 19,
          ),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _page = 0;
                    });
                  },
                ),
          hintText: 'Search subject, teacher, program',
          hintStyle: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
          filled: true,
          fillColor: AppTheme.bg,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: AppTheme.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: AppTheme.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: const BorderSide(color: AppTheme.accent),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusFilters() {
    const scheduleLabels = ['All', 'Upcoming', 'On-going', 'Finished'];
    const scheduleIcons = [
      Icons.view_list_outlined,
      Icons.schedule_outlined,
      Icons.play_circle_outline,
      Icons.task_alt_outlined,
    ];
    const reviewLabels = [
      'All',
      'Pending review',
      'Approved',
      'Changes requested',
      'Draft',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _filterGroupLabel('SCHEDULE'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(_statusTabs.length, (index) {
            final status = _statusTabs[index];
            return _filterButton(
              label: scheduleLabels[index],
              icon: scheduleIcons[index],
              selected: _statusFilter == status,
              onPressed: () => setState(() {
                _statusFilter = status;
                _page = 0;
              }),
            );
          }),
        ),
        const SizedBox(height: 12),
        _filterGroupLabel('REVIEW STATUS'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: List.generate(_reviewStatusTabs.length, (index) {
            final status = _reviewStatusTabs[index];
            return _filterButton(
              label: reviewLabels[index],
              icon: [
                Icons.view_list_outlined,
                Icons.hourglass_empty_outlined,
                Icons.check_circle_outline,
                Icons.rate_review_outlined,
                Icons.edit_note_outlined,
              ][index],
              selected: _reviewStatusFilter == status,
              onPressed: () => setState(() {
                _reviewStatusFilter = status;
                _page = 0;
              }),
            );
          }),
        ),
      ],
    );
  }

  Widget _filterGroupLabel(String label) => Text(
    label,
    style: AppTheme.mono(
      9,
      color: AppTheme.mutedText,
    ).copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8),
  );

  Widget _filterButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? Colors.white : AppTheme.text,
        backgroundColor: selected ? AppTheme.accent : AppTheme.header,
        side: BorderSide(color: selected ? AppTheme.accent : AppTheme.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
          return const Padding(
            padding: EdgeInsets.all(48),
            child: Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            ),
          );
        }

        _maybeOpenReviewFromLink(snapshot.data!);

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _classesStream,
          builder: (context, classSnapshot) {
            if (classSnapshot.hasError) {
              return _centered(
                AppTheme.emptyCard(
                  Icons.error_outline,
                  'Could not load your assigned classes. Check your connection and try again.',
                ),
              );
            }
            if (!classSnapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.accent),
                ),
              );
            }
            return _buildExamContent(
              snapshot.data!.docs,
              classSnapshot.data!.docs,
            );
          },
        );
      },
    );
  }

  void _maybeOpenReviewFromLink(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final query = GoRouterState.of(context).uri.queryParameters;
    final examId = query['review'];
    if (examId == null || examId.isEmpty) return;

    final token = '$examId|${query['t'] ?? ''}';
    if (_handledReviewToken == token) return;

    QueryDocumentSnapshot<Map<String, dynamic>>? match;
    for (final doc in snapshot.docs) {
      if (doc.id == examId) {
        match = doc;
        break;
      }
    }
    if (match == null && snapshot.metadata.isFromCache) return;

    _handledReviewToken = token;
    final found = match;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (found == null) {
        unawaited(
          AppDialog.alert(
            context,
            title: 'Exam not found',
            message: 'That exam no longer exists or is not available to you.',
            tone: AppTone.warning,
          ),
        );
        return;
      }
      unawaited(_showReviewDetails(found.id, found.data()));
    });
  }

  Widget _buildExamContent(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> all,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> classes,
  ) {
    final sortedExams = all.toList()
      ..sort(
        (a, b) => _startMillis(b.data()).compareTo(_startMillis(a.data())),
      );

    if (sortedExams.isEmpty) {
      return _centered(
        AppTheme.emptyCard(
          Icons.quiz_outlined,
          'No exams yet. Tap Create Exam to add your first one.',
        ),
      );
    }

    final exams = sortedExams.where(_matchesFilters).toList();
    if (exams.isEmpty) {
      return _centered(
        AppTheme.emptyCard(
          Icons.search_off,
          'No exams match your search or filter.',
        ),
      );
    }

    final totalPages = (exams.length / _pageSize).ceil();
    final page = _page.clamp(0, totalPages - 1).toInt();
    final pageExams = exams.skip(page * _pageSize).take(_pageSize).toList();
    final showSwipeHint = MediaQuery.of(context).size.width < _tableMinWidth;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppTheme.line)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Text(
                'Showing ${page * _pageSize + 1}-'
                '${page * _pageSize + pageExams.length} '
                'of ${exams.length} exams',
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 12.5,
                ),
              ),
              if (showSwipeHint)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.swap_horiz, size: 16, color: AppTheme.mutedText),
                    SizedBox(width: 4),
                    Text(
                      'Swipe sideways for more',
                      style: TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SizedBox(
            height:
                _headingRowHeight + (pageExams.length * _dataRowHeight) + 24,
            child: _buildTable(
              exams: pageExams,
              classes: classes,
              startIndex: page * _pageSize,
            ),
          ),
        ),
        if (totalPages > 1) _buildPager(page, totalPages),
        const SizedBox(height: 8),
      ],
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

  Widget _buildTable({
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> exams,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> classes,
    required int startIndex,
  }) {
    const headStyle = TextStyle(
      color: AppTheme.mutedText,
      fontWeight: FontWeight.w600,
      fontSize: 12,
      letterSpacing: 0.3,
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.line),
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
        child: LayoutBuilder(
          builder: (context, constraints) => DataTable2(
            horizontalScrollController: _horizontalController,
            isHorizontalScrollBarVisible: true,
            isVerticalScrollBarVisible: false,
            minWidth: _tableWidthFor(constraints.maxWidth),
            columnSpacing: 12,
            horizontalMargin: 16,
            headingRowHeight: _headingRowHeight,
            dataRowHeight: _dataRowHeight,
            fixedLeftColumns: 1,
            fixedColumnsColor: AppTheme.header,
            fixedCornerColor: AppTheme.soft,
            headingRowColor: WidgetStateProperty.all(AppTheme.soft),
            border: TableBorder(
              horizontalInside: BorderSide(
                color: AppTheme.line.withValues(alpha: 0.7),
              ),
            ),
            columns: [
              col('#', width: 44, center: true),
              col('Subject', size: ColumnSize.L),
              col('Class ID', size: ColumnSize.S),
              col('Start time', width: 142),
              col('End time', width: 142),
              col('Exam status', width: 120, center: true),
              col('Review status', width: 140, center: true),
              col('Actions', width: 190, center: true),
            ],
            rows: List<DataRow2>.generate(exams.length, (index) {
              final doc = exams[index];
              final data = doc.data();
              final subject = (data['subject'] ?? 'Untitled exam').toString();
              final monitoringEnabled = data['monitoringEnabled'] == true;

              return DataRow2(
                onTap: () => _editExam(doc.id, data),
                cells: [
                  DataCell(_number(startIndex + index + 1)),
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
                  DataCell(_classIdCell(_resolveClassId(data, classes))),
                  DataCell(_dateCell(data['startTime'])),
                  DataCell(_dateCell(data['endTime'])),
                  DataCell(_examStatusCell(data)),
                  DataCell(_reviewStatusCell(doc.id, data)),
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
            }),
          ),
        ),
      ),
    );
  }

  Widget _examStatusCell(Map<String, dynamic> data) {
    final status = _statusOf(data);
    final color = switch (status) {
      'upcoming' => const Color(0xFF2563EB),
      'ongoing' => const Color(0xFFB7791F),
      'finished' => AppTheme.success,
      _ => AppTheme.mutedText,
    };
    final label = switch (status) {
      'upcoming' => 'Upcoming',
      'ongoing' => 'On-going',
      'finished' => 'Finished',
      _ => 'Unknown',
    };

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _reviewStatusCell(String examId, Map<String, dynamic> data) {
    final status = (data['approvalStatus'] ?? 'draft').toString();
    final unread =
        status == 'changes_requested' && data['reviewNoteSeen'] == false;
    return Center(
      child: Tooltip(
        message: unread
            ? 'New review notes - tap to read'
            : 'View review details',
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _showReviewDetails(examId, data),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 4, right: 4),
                child: _approvalStatusChip(status),
              ),
              if (unread)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppTheme.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.header, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReviewDetails(
    String examId,
    Map<String, dynamic> data,
  ) async {
    final status = (data['approvalStatus'] ?? 'draft').toString();
    if (status == 'changes_requested') {
      unawaited(_markReviewNoteRead(examId));
    }
    final action = await AppDialog.custom<String>(
      context,
      builder: (_) => _ReviewDetailsDialog(
        data: data,
        status: status,
        chip: _approvalStatusChip(status),
      ),
    );
    if (action == 'edit' && mounted) _editExam(examId, data);
  }

  Future<void> _markReviewNoteRead(String examId) async {
    try {
      await FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('markReviewNoteRead').call({'examId': examId});
    } catch (error, stackTrace) {
      debugPrint('Unable to mark review note as read for $examId: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not mark the review note as read. Tap the status to retry.',
            ),
          ),
        );
      }
    }
  }

  List<int?> _pageItems(int current, int total) {
    if (total <= 7) return List<int?>.generate(total, (index) => index);
    final pages = <int>{0, total - 1, current - 1, current, current + 1}
      ..removeWhere((page) => page < 0 || page >= total);
    final sorted = pages.toList()..sort();
    final items = <int?>[];
    for (var index = 0; index < sorted.length; index++) {
      if (index > 0 && sorted[index] - sorted[index - 1] > 1) {
        items.add(null);
      }
      items.add(sorted[index]);
    }
    return items;
  }

  Widget _buildPager(int page, int totalPages) {
    Widget pageButton(int pageIndex) {
      final selected = pageIndex == page;
      return SizedBox(
        width: 38,
        height: 38,
        child: OutlinedButton(
          onPressed: selected ? null : () => setState(() => _page = pageIndex),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: selected ? AppTheme.accent : AppTheme.header,
            disabledBackgroundColor: AppTheme.accent,
            foregroundColor: AppTheme.text,
            disabledForegroundColor: Colors.white,
            side: BorderSide(color: selected ? AppTheme.accent : AppTheme.line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text('${pageIndex + 1}', style: const TextStyle(fontSize: 13)),
        ),
      );
    }

    Widget arrow(IconData icon, String tip, int? target) {
      return IconButton(
        tooltip: tip,
        icon: Icon(icon),
        color: AppTheme.text,
        onPressed: target == null ? null : () => setState(() => _page = target),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        runSpacing: 6,
        children: [
          arrow(
            Icons.chevron_left,
            'Previous page',
            page > 0 ? page - 1 : null,
          ),
          for (final item in _pageItems(page, totalPages))
            item == null
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '…',
                      style: TextStyle(color: AppTheme.mutedText),
                    ),
                  )
                : pageButton(item),
          arrow(
            Icons.chevron_right,
            'Next page',
            page < totalPages - 1 ? page + 1 : null,
          ),
        ],
      ),
    );
  }

  Widget _number(int value) => Center(
    child: Text(
      value.toString().padLeft(2, '0'),
      style: AppTheme.mono(
        12,
        color: _dashboardBlue,
      ).copyWith(fontWeight: FontWeight.w700),
    ),
  );

  Widget _classIdCell(String classId) {
    if (classId.isEmpty) {
      return const Text(
        'Not linked',
        style: TextStyle(color: AppTheme.mutedText, fontSize: 12),
      );
    }
    return Tooltip(
      message: classId,
      child: Text(
        classId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.mono(11, color: AppTheme.text),
      ),
    );
  }

  String _resolveClassId(
    Map<String, dynamic> exam,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> classes,
  ) {
    final savedClassId = (exam['classId'] ?? '').toString().trim();
    if (savedClassId.isNotEmpty) {
      for (final classDoc in classes) {
        final data = classDoc.data();
        if (classDoc.id == savedClassId ||
            (data['classId'] ?? '').toString().trim() == savedClassId) {
          return (data['classId'] ?? classDoc.id).toString();
        }
      }
      return savedClassId;
    }

    final matches = classes.where((classDoc) {
      final data = classDoc.data();
      return (data['program'] ?? '').toString() ==
              (exam['program'] ?? '').toString() &&
          (data['subject'] ?? '').toString() ==
              (exam['subject'] ?? '').toString() &&
          (data['yearBlock'] ?? '').toString() ==
              (exam['yearBlock'] ?? '').toString();
    }).toList();

    if (matches.length != 1) return '';
    final classData = matches.single.data();
    return (classData['classId'] ?? matches.single.id).toString();
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

  Widget _approvalStatusChip(String status) {
    final color = switch (status) {
      'pending' => const Color(0xFFB7791F),
      'approved' => AppTheme.success,
      'changes_requested' => AppTheme.error,
      _ => AppTheme.mutedText,
    };
    final label = switch (status) {
      'pending' => 'Pending review',
      'approved' => 'Approved',
      'changes_requested' => 'Changes requested',
      _ => 'Draft',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
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
    final locked = _isLocked(data);
    final isApproved =
        (data['approvalStatus'] ?? 'draft').toString().toLowerCase() ==
        'approved';

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isApproved) ...[
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
        ],
        // _actionIcon(
        //   icon: Icons.video_library_outlined,
        //   tooltip: 'View exam clips',
        //   color: _warning,
        //   onTap: busy ? null : () => context.push('/exam-clips/$examId'),
        // ),
        const SizedBox(width: 8),
        _actionIcon(
          icon: locked ? Icons.visibility_outlined : Icons.edit_outlined,
          tooltip: locked ? 'View exam (locked)' : 'Edit exam',
          color: _dashboardBlue,
          onTap: busy ? null : () => _editExam(examId, data),
        ),
        const SizedBox(width: 8),
        _actionIcon(
          icon: locked ? Icons.lock_outline : Icons.delete_outline,
          tooltip: locked
              ? 'Locked after submission or when finished'
              : 'Delete exam',
          color: locked ? AppTheme.mutedText : AppTheme.error,
          onTap: busy || locked ? null : () => _deleteExam(examId, subject),
        ),
      ],
    );
  }

  bool _isLocked(Map<String, dynamic> data) {
    final status = (data['approvalStatus'] ?? 'draft').toString().toLowerCase();
    final examStatus = (data['status'] ?? '').toString().toLowerCase();
    final endTime = data['endTime'];
    final ended =
        endTime is Timestamp && !endTime.toDate().isAfter(DateTime.now());
    return !['draft', 'changes_requested'].contains(status) ||
        ['finished', 'finish', 'completed', 'complete'].contains(examStatus) ||
        ended;
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
        color: color.withOpacity(onTap == null ? 0.06 : 0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: color.withOpacity(0.35)),
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
    final reviewStatus = (data['approvalStatus'] ?? 'draft')
        .toString()
        .toLowerCase();
    if (_reviewStatusFilter != 'all' && reviewStatus != _reviewStatusFilter) {
      return false;
    }
    if (_searchQuery.isEmpty) return true;

    final haystack = [
      data['subject'],
      data['creator'],
      data['program'],
      data['yearBlock'],
      data['classId'],
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

  Future<void> _openExamDialog({
    String? docId,
    Map<String, dynamic>? existing,
  }) async {
    final result = await ExamFormDialog.show(
      context,
      docId: docId,
      existing: existing,
    );
    if (!mounted || result == null) return;
    if (result.openQuestions) {
      context.go('/edit-question/${result.examId}');
    }
  }

  void _addExam() => _openExamDialog();

  void _editExam(String examId, Map<String, dynamic> data) =>
      _openExamDialog(docId: examId, existing: data);

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
    final DocumentSnapshot<Map<String, dynamic>> fresh;
    try {
      fresh = await _db.collection('exams').doc(examId).get();
    } catch (e) {
      await _showActionResult(
        title: 'Unable to check exam status',
        message: _errorText(e),
        tone: AppTone.error,
      );
      return;
    }
    if (_isLocked(fresh.data() ?? {})) {
      await _showActionResult(
        title: 'Exam is locked',
        message: 'Submitted or finished exams cannot be deleted.',
        tone: AppTone.warning,
      );
      return;
    }
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
      if (_isLocked(examData ?? {})) {
        await _showActionResult(
          title: 'Exam is locked',
          message: 'Submitted or finished exams cannot be deleted.',
          tone: AppTone.warning,
        );
        return;
      }

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

enum _StepState { done, current, attention, upcoming }

class _FlowStep {
  const _FlowStep(this.title, this.subtitle, this.state);

  final String title;
  final String subtitle;
  final _StepState state;
}

class _ReviewDetailsDialog extends StatelessWidget {
  const _ReviewDetailsDialog({
    required this.data,
    required this.status,
    required this.chip,
  });

  final Map<String, dynamic> data;
  final String status;
  final Widget chip;

  static final DateFormat _fmt = DateFormat('MMM dd, yyyy · hh:mm a');

  String? _when(dynamic value) =>
      value is Timestamp ? _fmt.format(value.toDate()) : null;

  List<_FlowStep> _steps() {
    final submitted = status != 'draft';
    final pending = status == 'pending';
    final changes = status == 'changes_requested';
    final approved = status == 'approved';
    final reviewed = approved || changes;

    return [
      _FlowStep(
        'Draft',
        'You build the exam and add its questions.',
        submitted ? _StepState.done : _StepState.current,
      ),
      _FlowStep(
        'Submitted for review',
        submitted
            ? (_when(data['submittedAt']) ?? 'Sent to the admin.')
            : 'Submit the exam to send it to the admin.',
        submitted ? _StepState.done : _StepState.upcoming,
      ),
      _FlowStep(
        'Admin review',
        reviewed
            ? (_when(data['reviewedAt']) ?? 'Reviewed by the admin.')
            : pending
            ? 'Waiting for an admin to review your questions.'
            : 'An admin checks every question and answer.',
        reviewed
            ? _StepState.done
            : pending
            ? _StepState.current
            : _StepState.upcoming,
      ),
      _FlowStep(
        changes
            ? 'Changes requested'
            : approved
            ? 'Approved'
            : 'Approved or sent back',
        changes
            ? 'Fix the points in the notes, then submit again. The review restarts as Pending.'
            : approved
            ? 'Released to students at the scheduled time.'
            : 'Approved exams go live; otherwise you get notes to fix.',
        changes
            ? _StepState.attention
            : approved
            ? _StepState.done
            : _StepState.upcoming,
      ),
    ];
  }

  Widget _stepRow(_FlowStep step, {required bool last}) {
    final color = switch (step.state) {
      _StepState.done => AppTheme.success,
      _StepState.current => const Color(0xFFB7791F),
      _StepState.attention => _dashboardBlue,
      _StepState.upcoming => AppTheme.mutedText,
    };
    final icon = switch (step.state) {
      _StepState.done => Icons.check_circle,
      _StepState.current => Icons.hourglass_top_rounded,
      _StepState.attention => Icons.error_rounded,
      _StepState.upcoming => Icons.radio_button_unchecked,
    };
    final upcoming = step.state == _StepState.upcoming;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Icon(icon, size: 20, color: color),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: upcoming
                          ? AppTheme.line
                          : color.withValues(alpha: 0.4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.title,
                    style: TextStyle(
                      color: upcoming ? AppTheme.mutedText : AppTheme.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.subtitle,
                    style: const TextStyle(
                      color: AppTheme.mutedText,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subject = (data['subject'] ?? 'Untitled exam').toString();
    final note = (data['reviewNote'] ?? '').toString().trim();
    final changes = status == 'changes_requested';
    final steps = _steps();
    final outlined = OutlinedButton.styleFrom(
      foregroundColor: AppTheme.text,
      minimumSize: const Size(0, 46),
      side: const BorderSide(color: AppTheme.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.line),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'REVIEW DETAILS',
                        style: AppTheme.mono(9, color: _dashboardBlue)
                            .copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subject,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      chip,
                      if (changes) ...[
                        const SizedBox(height: 18),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppTheme.error.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.error.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.rate_review_outlined,
                                    size: 16,
                                    color: _dashboardBlue,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'ADMIN REVIEW NOTES',
                                    style: AppTheme.mono(
                                      9,
                                      color: AppTheme.error,
                                    ).copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                note.isEmpty
                                    ? 'The admin did not leave a note.'
                                    : note,
                                style: const TextStyle(
                                  color: AppTheme.text,
                                  fontSize: 13.5,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Text(
                        'EXAM FLOW',
                        style: AppTheme.mono(9, color: AppTheme.mutedText)
                            .copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                      ),
                      const SizedBox(height: 12),
                      for (var index = 0; index < steps.length; index++)
                        _stepRow(steps[index], last: index == steps.length - 1),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: outlined,
                        child: const Text('Close'),
                      ),
                    ),
                    if (changes || status == 'draft') ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).pop('edit'),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit exam'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 46),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
