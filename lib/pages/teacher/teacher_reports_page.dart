import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:web/web.dart' as web;

import '../../helpers/AppTheme.dart';
import '../../widgets/app_dialog.dart';
import 'teacher_incident_report_sheet.dart';
const Color _dashboardBlue = Color(0xFF153CFF);
class _Ui {
  static const blue = AppTheme.accent;
  static const blueWash = AppTheme.headerLight;
  static const blueWashBorder = AppTheme.line;
  static const placeholderBg = AppTheme.bg;
  static const placeholderLine = AppTheme.line;
  static const placeholderText = AppTheme.mutedText;
  static const noteBg = AppTheme.headerLight;
  static const noteLine = AppTheme.line;
  static const noteText = AppTheme.text;
  static const incomplete = Color(0xFFB77A16);
}

class TeacherReportsPage extends StatefulWidget {
  const TeacherReportsPage({super.key});

  @override
  State<TeacherReportsPage> createState() => _TeacherReportsPageState();
}

class _TeacherReportsPageState extends State<TeacherReportsPage> {
  final _db = FirebaseFirestore.instance;
  final _dateFormat = DateFormat('MMM d, yyyy');
  List<_ExamReport> _reports = [];
  String? _error;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadReports());
  }

  Future<void> _loadReports() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('Sign in to view your reports.');

      final teacherSnapshot = await _db.collection('users').doc(user.uid).get();
      final teacherId = (teacherSnapshot.data()?['ID'] ?? '').toString().trim();
      if (teacherId.isEmpty) {
        throw StateError('Your teacher ID could not be found.');
      }

      final examSnapshot = await _db
          .collection('exams')
          .where('teacherId', isEqualTo: teacherId)
          .get();
      final reports = await Future.wait(
        examSnapshot.docs.map((exam) async {
          final resultSnapshot = await _db
              .collection('examResults')
              .doc(exam.id)
              .collection('students')
              .get();
          return _ExamReport.fromDocuments(
            id: exam.id,
            data: exam.data(),
            results: resultSnapshot.docs,
          );
        }),
      );
      reports.sort((a, b) {
        final aDate = a.startTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.startTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _loading = false;
      });
    }
  }

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
final compact = screenWidth < 680;
final sidePad = screenWidth < 600 ? 16.0 : 24.0;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadReports,
          color: _Ui.blue,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
  sidePad,
  24,
  sidePad,
  40,
),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1350),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _pageHeading(compact),
                      SizedBox(height: compact ? 21 : 26),
                      if (_error != null) ...[
                        _errorNote(),
                        const SizedBox(height: 16),
                      ],
                      _card(
                        compact: compact,
                        title: 'Exam performance',
                        subtitle: 'Scores and completion trends',
                        child: _performanceChart(),
                      ),
                      const SizedBox(height: 16),
                      _card(
                        compact: compact,
                        title: 'Monitoring events',
                        subtitle: 'Flags and review outcomes',
                        child: _monitoringChart(),
                      ),
                      const SizedBox(height: 16),
                      _generatedReports(compact),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── heading ─────────────────────────

  Widget _pageHeading(bool compact) {
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '06 / FACULTY ANALYTICS',
         style: TextStyle(
            color: _dashboardBlue,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(height: compact ? 11 : 16),
        Text(
          'Reports.',
          style: AppTheme.display(34, ls: -0.06, color: AppTheme.text)),
        const SizedBox(height: 10),
        const Text(
          'Explore performance trends, assessment summaries, and monitoring results.',
          style: TextStyle(
            color: AppTheme.mutedText,
            fontSize: 13,
            height: 1.6,
          ),
        ),
      ],
    );

    final exportButton = TweenAnimationBuilder<double>(
      key: ValueKey(_exporting),
      tween: Tween(begin: 0.96, end: 1),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: OutlinedButton(
        onPressed: _exporting || _loading ? null : _exportExcel,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.text,
          backgroundColor: AppTheme.header,
          side: const BorderSide(color: AppTheme.line),
          elevation: 0,
          minimumSize: Size(compact ? double.infinity : 0, compact ? 56 : 47),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: TextStyle(
            fontSize: compact ? 14 : 12,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 10 : 7),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Row(
            key: ValueKey(_exporting),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_exporting) ...[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 9),
              ] else ...[
                const Icon(Icons.file_download_outlined, size: 17),
                const SizedBox(width: 8),
              ],
              Text(_exporting ? 'Preparing Excel...' : 'Export Excel'),
            ],
          ),
        ),
      ),
    );

    final reportButton = FilledButton.icon(
      onPressed: _loading ? null : _openReportDialog,
      icon: const Icon(Icons.flag_outlined, size: 17),
      label: const Text('Report to admin'),
      style: FilledButton.styleFrom(
        backgroundColor: _Ui.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: Size(compact ? double.infinity : 0, compact ? 56 : 47),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        textStyle: TextStyle(
          fontSize: compact ? 14 : 12,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(compact ? 10 : 7),
        ),
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 16),
          reportButton,
          const SizedBox(height: 10),
          exportButton,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: title),
        const SizedBox(width: 24),
        reportButton,
        const SizedBox(width: 12),
        exportButton,
      ],
    );
  }

  Widget _errorNote() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: _Ui.noteBg,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: _Ui.noteLine),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            _error ?? '',
            style: const TextStyle(
              color: _Ui.noteText,
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ),
        TextButton(
          onPressed: _loadReports,
          style: TextButton.styleFrom(foregroundColor: _Ui.blue),
          child: const Text('Try again'),
        ),
      ],
    ),
  );

  // ───────────────────────── card shell ─────────────────────────

  Widget _card({
    required bool compact,
    required String title,
    required String subtitle,
    required Widget child,
    bool flush = false,
  }) {
    final hPad = compact ? 16.0 : 22.0;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.header,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: EdgeInsets.symmetric(
              horizontal: hPad,
              vertical: compact ? 16 : 19,
            ),
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.display(18, ls: -0.045, color: AppTheme.text),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.line),
          flush
              ? child
              : Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: hPad,
                    vertical: compact ? 16 : 20,
                  ),
                  child: child,
                ),
        ],
      ),
    );
  }

  // ───────────────────────── placeholders ─────────────────────────

  /// Dashed "chart placeholder" box, same as the HTML .chart-placeholder.
  Widget _chartPlaceholder({String? message, bool loading = false}) {
    return _DashedBox(
      minHeight: 175,
      radius: 7,
      borderColor: _Ui.placeholderLine,
      color: _Ui.placeholderBg,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _Ui.blue,
                ),
              )
            : Text(
                message ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _Ui.placeholderText,
                  fontSize: 12,
                ),
              ),
      ),
    );
  }

  /// Same as the HTML .empty block (icon square, title, message).
  Widget _emptyBlock({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return _DashedBox(
      minHeight: 216,
      radius: 8,
      borderColor: const Color(0xFFD3D7DC),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFDFDFD), Color(0xFFF8F9FB)],
      ),
      padding: const EdgeInsets.all(22),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _Ui.blueWash,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _Ui.blueWashBorder),
              ),
              child: Icon(icon, size: 24, color: _Ui.blue),
            ),
            const SizedBox(height: 13),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTheme.display(16, ls: -0.04, color: AppTheme.text),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 330),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 12,
                  height: 1.65,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── charts ─────────────────────────

  /// All exams in chronological order, including exams without scored attempts.
  List<_ExamReport> get _performanceReports => _reports.reversed.toList();

  /// Exams that have at least one student attempt.
  List<_ExamReport> get _chartReports => _reports
      .where((report) => report.totalStudents > 0)
      .take(12)
      .toList()
      .reversed
      .toList();

  Widget _performanceChart() {
    if (_loading) return _chartPlaceholder(loading: true);
    final reports = _performanceReports;
    if (reports.isEmpty) {
      return _chartPlaceholder(
        message: 'Performance data will appear after exams are scheduled.',
      );
    }
    if (reports.every((report) => report.totalStudents == 0)) {
      return _chartPlaceholder(
        message:
            'Score and completion trends will appear after students attempt an exam.',
      );
    }
    final scorePoints = reports
        .asMap()
        .entries
        .where((entry) => entry.value.averageScore != null)
        .map(
          (entry) => FlSpot(
            entry.key.toDouble(),
            entry.value.averageScore!.clamp(0, 100).toDouble(),
          ),
        )
        .toList();
    final completionPoints = reports
        .asMap()
        .entries
        .where((entry) => entry.value.completionRate != null)
        .map(
          (entry) => FlSpot(
            entry.key.toDouble(),
            entry.value.completionRate!.clamp(0, 100).toDouble(),
          ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final chartWidth = math.max(
              constraints.maxWidth,
              reports.length * 88.0,
            );
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: chartWidth,
                height: 270,
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: 100,
                    minX: 0,
                    maxX: math.max(1, reports.length - 1).toDouble(),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: 25,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: AppTheme.line.withValues(alpha: 0.7),
                        strokeWidth: 1,
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 42,
                          interval: 25,
                          getTitlesWidget: (value, meta) => SideTitleWidget(
                            meta: meta,
                            child: Text(
                              '${value.toInt()}%',
                              style: const TextStyle(
                                color: AppTheme.mutedText,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 50,
                          interval: 1,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= reports.length) {
                              return const SizedBox.shrink();
                            }
                            return SideTitleWidget(
                              meta: meta,
                              space: 8,
                              child: SizedBox(
                                width: 80,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      reports[index].subject,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppTheme.mutedText,
                                        fontSize: 9,
                                      ),
                                    ),
                                    if (reports[index].startTime != null)
                                      Text(
                                        DateFormat(
                                          'M/d',
                                        ).format(reports[index].startTime!),
                                        style: const TextStyle(
                                          color: AppTheme.mutedText,
                                          fontSize: 8,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => AppTheme.text,
                        getTooltipItems: (spots) => spots.map((spot) {
                          final index = spot.x.toInt();
                          final report = reports[index];
                          final metric = spot.barIndex == 0
                              ? 'Average score'
                              : 'Completion';
                          return LineTooltipItem(
                            '${report.subject}\n$metric: ${spot.y.toStringAsFixed(1)}%',
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    lineBarsData: [
                      _performanceLine(scorePoints, AppTheme.accent),
                      _performanceLine(completionPoints, AppTheme.success),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 18,
          runSpacing: 8,
          children: [
            _chartLegend(AppTheme.accent, 'Average score'),
            _chartLegend(AppTheme.success, 'Completion rate'),
          ],
        ),
      ],
    );
  }

  LineChartBarData _performanceLine(List<FlSpot> points, Color color) =>
      LineChartBarData(
        spots: points,
        isCurved: false,
        color: color,
        barWidth: 3,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
            radius: 4,
            color: color,
            strokeWidth: 2,
            strokeColor: AppTheme.header,
          ),
        ),
      );

  Widget _monitoringChart() {
    if (_loading) return _chartPlaceholder(loading: true);
    final reports = _chartReports;
    if (reports.isEmpty) {
      return _chartPlaceholder(
        message: 'Monitoring outcomes will appear when students attempt exams.',
      );
    }
    final maxValue = reports.fold<int>(
      0,
      (max, report) => [
        max,
        report.flaggedStudents,
        report.completed,
        report.incomplete,
      ].reduce((a, b) => a > b ? a : b),
    );
    final interval = maxValue <= 4 ? 1.0 : (maxValue / 4).ceilToDouble();
    final groups = reports.asMap().entries.map((entry) {
      final report = entry.value;
      return BarChartGroupData(
        x: entry.key,
        barsSpace: 4,
        barRods: [
          _bar(report.completed, AppTheme.success),
          _bar(report.incomplete, _Ui.incomplete),
          _bar(report.flaggedStudents, AppTheme.error),
        ],
      );
    }).toList();

    return Column(
      children: [
        SizedBox(
          height: 240,
          child: BarChart(
            BarChartData(
              maxY: (maxValue + interval).toDouble(),
              barGroups: groups,
              alignment: BarChartAlignment.spaceEvenly,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: AppTheme.line.withValues(alpha: 0.7),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: interval,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        value.toInt().toString(),
                        style: const TextStyle(
                          color: AppTheme.mutedText,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= reports.length) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        space: 8,
                        child: SizedBox(
                          width: 76,
                          child: Text(
                            reports[index].subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppTheme.mutedText,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => AppTheme.text,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final report = reports[group.x];
                    final labels = ['Completed', 'Incomplete', 'Flagged'];
                    return BarTooltipItem(
                      '${report.subject}\n${labels[rodIndex]}: ${rod.toY.toInt()}',
                      const TextStyle(color: Colors.white, fontSize: 11),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            _chartLegend(AppTheme.success, 'Completed'),
            _chartLegend(_Ui.incomplete, 'Incomplete'),
            _chartLegend(AppTheme.error, 'Flagged'),
          ],
        ),
      ],
    );
  }

  BarChartRodData _bar(int value, Color color) => BarChartRodData(
    toY: value.toDouble(),
    width: 10,
    color: color,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
  );

  Widget _chartLegend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(color: AppTheme.mutedText, fontSize: 11),
      ),
    ],
  );

  // ───────────────────────── generated reports ─────────────────────────

  Widget _generatedReports(bool compact) {
    final reports = _reports;
    final title = 'Generated reports';
    final subtitle = 'Downloadable analysis when available';

    if (_loading) {
      return _card(
        compact: compact,
        title: title,
        subtitle: subtitle,
        child: _chartPlaceholder(loading: true),
      );
    }

    if (reports.isEmpty) {
      return _card(
        compact: compact,
        title: title,
        subtitle: subtitle,
        child: _emptyBlock(
          icon: Icons.insert_chart_outlined,
          title: 'No reports generated',
          message:
              'Student attempts and monitoring signals appear here when available.',
        ),
      );
    }

    if (compact) {
      return _card(
        compact: compact,
        title: title,
        subtitle: subtitle,
        flush: true,
        child: Column(
          children: [
            for (var i = 0; i < reports.length; i++)
              _reportTile(reports[i], last: i == reports.length - 1),
          ],
        ),
      );
    }

    return _card(
      compact: compact,
      title: title,
      subtitle: subtitle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableHeight = (reports.length * 54.0 + 56)
              .clamp(220.0, 560.0)
              .toDouble();
          return SizedBox(
            height: tableHeight,
            child: DataTable2(
              minWidth: constraints.maxWidth,
              headingRowHeight: 52,
              dataRowHeight: 54,
              horizontalMargin: 14,
              columnSpacing: 12,
              headingRowColor: WidgetStateProperty.all(AppTheme.soft),
              headingTextStyle: AppTheme.mono(10, color: AppTheme.mutedText),
              dataTextStyle: const TextStyle(
                color: AppTheme.text,
                fontSize: 12,
              ),
              dividerThickness: 1,
              columns: const [
                DataColumn2(
                  label: Text('EXAM'),
                  size: ColumnSize.L,
                  minWidth: 160,
                ),
                DataColumn2(
                  label: Text('CLASS'),
                  size: ColumnSize.M,
                  minWidth: 105,
                ),
                DataColumn2(
                  label: Text('DATE'),
                  size: ColumnSize.M,
                  minWidth: 120,
                ),
                DataColumn2(
                  label: Text('STUDENTS'),
                  size: ColumnSize.S,
                  minWidth: 82,
                ),
                DataColumn2(
                  label: Text('COMPLETED'),
                  size: ColumnSize.S,
                  minWidth: 92,
                ),
                DataColumn2(
                  label: Text('AVG. SCORE'),
                  size: ColumnSize.S,
                  minWidth: 96,
                ),
                DataColumn2(
                  label: Text('FLAGGED'),
                  size: ColumnSize.S,
                  minWidth: 80,
                ),
              ],
              rows: reports.map(_reportTableRow).toList(),
            ),
          );
        },
      ),
    );
  }

  Widget _reportTile(_ExamReport report, {required bool last}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      border: last
          ? null
          : const Border(bottom: BorderSide(color: AppTheme.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          report.subject,
          style: const TextStyle(
            color: AppTheme.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${report.classId.isEmpty ? 'Class not set' : report.classId} · ${report.startTime == null ? 'Date not set' : _dateFormat.format(report.startTime!)}',
          style: const TextStyle(color: AppTheme.mutedText, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              '${report.completed}/${report.totalStudents} completed',
              style: const TextStyle(color: AppTheme.mutedText, fontSize: 11),
            ),
            Text(
              'Average: ${_scoreLabel(report.averageScore)}',
              style: const TextStyle(color: AppTheme.mutedText, fontSize: 11),
            ),
            Text(
              'Flagged: ${report.flaggedStudents}',
              style: const TextStyle(color: AppTheme.mutedText, fontSize: 11),
            ),
          ],
        ),
      ],
    ),
  );

  DataRow _reportTableRow(_ExamReport report) => DataRow(
    cells: [
      DataCell(
        SizedBox(
          width: 170,
          child: Text(
            report.subject,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      DataCell(Text(report.classId.isEmpty ? '—' : report.classId)),
      DataCell(
        Text(
          report.startTime == null
              ? '—'
              : _dateFormat.format(report.startTime!),
        ),
      ),
      DataCell(Text('${report.totalStudents}')),
      DataCell(Text('${report.completed}')),
      DataCell(Text(_scoreLabel(report.averageScore))),
      DataCell(Text('${report.flaggedStudents}')),
    ],
  );

  String _scoreLabel(double? score) =>
      score == null ? '—' : '${score.toStringAsFixed(1)}%';

  // ───────────────────────── export ─────────────────────────

  Future<void> _openReportDialog() async {
    final exams = _reports
        .map((report) => report.toReportable(_dateFormat))
        .toList();
    final sent = await showTeacherReportSheet(context, exams: exams);
    if (sent == null || !mounted) return;
    await AppDialog.alert(
      context,
      title: 'Report sent',
      message: sent > 1
          ? '$sent student reports were sent to the admin for review.'
          : 'Your report was sent to the admin for review.',
      tone: AppTone.success,
    );
  }

  Future<void> _exportExcel() async {
    if (_reports.isEmpty) {
      await AppDialog.alert(
        context,
        title: 'Nothing to export',
        message: 'There are no exam reports available to export yet.',
        tone: AppTone.warning,
      );
      return;
    }
    setState(() => _exporting = true);
    try {
      final workbook = Excel.createExcel();
      workbook.rename('Sheet1', 'Exam Reports');
      final sheet = workbook['Exam Reports'];
      sheet.appendRow([
        TextCellValue('Exam'),
        TextCellValue('Class ID'),
        TextCellValue('Start date'),
        TextCellValue('Students'),
        TextCellValue('Completed'),
        TextCellValue('Incomplete'),
        TextCellValue('Average score (%)'),
        TextCellValue('Flagged students'),
        TextCellValue('Monitoring flags'),
      ]);
      for (final report in _reports) {
        sheet.appendRow([
          TextCellValue(report.subject),
          TextCellValue(report.classId),
          TextCellValue(
            report.startTime == null
                ? ''
                : DateFormat('yyyy-MM-dd HH:mm').format(report.startTime!),
          ),
          IntCellValue(report.totalStudents),
          IntCellValue(report.completed),
          IntCellValue(report.incomplete),
          report.averageScore == null
              ? null
              : DoubleCellValue(report.averageScore!),
          IntCellValue(report.flaggedStudents),
          IntCellValue(report.monitoringFlags),
        ]);
      }
      const columnWidths = [
        28.0,
        20.0,
        20.0,
        12.0,
        12.0,
        12.0,
        20.0,
        18.0,
        20.0,
      ];
      for (var i = 0; i < columnWidths.length; i++) {
        sheet.setColumnWidth(i, columnWidths[i]);
      }
      final bytes = workbook.save();
      if (bytes == null) {
        throw StateError('The Excel workbook could not be generated.');
      }
      final fileName =
          'exam_reports_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
      final fileBytes = Uint8List.fromList(bytes);
      String? savedPath;
      if (kIsWeb) {
        _downloadExcelInBrowser(fileBytes, fileName);
      } else {
        savedPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save exam report',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: const ['xlsx'],
          bytes: fileBytes,
        );
      }
      if (!mounted) return;
      if (kIsWeb || savedPath != null) {
        await AppDialog.alert(
          context,
          title: 'Export complete',
          message: 'Your Excel report has been downloaded successfully.',
          tone: AppTone.success,
        );
      }
    } catch (error) {
      if (!mounted) return;
      await AppDialog.alert(
        context,
        title: 'Export failed',
        message: 'The Excel report could not be exported.',
        detail: error.toString(),
        tone: AppTone.danger,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _downloadExcelInBrowser(Uint8List bytes, String fileName) {
    final blob = web.Blob([bytes.toJS].toJS);
    final url = web.URL.createObjectURL(blob);
    web.HTMLAnchorElement()
      ..href = url
      ..download = fileName
      ..click();
    Future<void>.delayed(const Duration(seconds: 1), () {
      web.URL.revokeObjectURL(url);
    });
  }
}

// ───────────────────────── dashed border helper ─────────────────────────

class _DashedBox extends StatelessWidget {
  const _DashedBox({
    required this.child,
    required this.borderColor,
    this.minHeight = 0,
    this.radius = 7,
    this.color,
    this.gradient,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final Color borderColor;
  final double minHeight;
  final double radius;
  final Color? color;
  final Gradient? gradient;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedRRectPainter(
        color: borderColor,
        radius: radius,
      ),
      child: Container(
        constraints: BoxConstraints(minHeight: minHeight),
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          gradient: gradient,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: child,
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;
  static const double dash = 4;
  static const double gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}

// ───────────────────────── data model ─────────────────────────

class _ExamReport {
  const _ExamReport({
    required this.id,
    required this.subject,
    required this.classId,
    required this.startTime,
    required this.totalStudents,
    required this.completed,
    required this.incomplete,
    required this.flaggedStudents,
    required this.monitoringFlags,
    required this.averageScore,
    required this.students,
  });

  final String id;
  final String subject;
  final String classId;
  final DateTime? startTime;
  final int totalStudents;
  final int completed;
  final int incomplete;
  final int flaggedStudents;
  final int monitoringFlags;
  final double? averageScore;
  final List<ReportableStudent> students;

  double? get completionRate =>
      totalStudents == 0 ? null : completed * 100 / totalStudents;

  ReportableExam toReportable(DateFormat format) => ReportableExam(
    id: id,
    title: subject,
    classId: classId,
    dateLabel: startTime == null ? '' : format.format(startTime!),
    students: students,
  );

  factory _ExamReport.fromDocuments({
    required String id,
    required Map<String, dynamic> data,
    required Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> results,
  }) {
    final docs = results.toList();
    var completed = 0;
    var incomplete = 0;
    var flaggedStudents = 0;
    var monitoringFlags = 0;
    var scoreTotal = 0.0;
    var scoredStudents = 0;
    final students = <ReportableStudent>[];

    int number(dynamic value) {
      if (value is num) return value.toInt();
      return int.tryParse('$value') ?? 0;
    }

    for (final doc in docs) {
      final result = doc.data();
      final status = (result['status'] ?? '').toString().toLowerCase();
      if (status == 'completed') {
        completed++;
        final score = number(result['score']);
        final total = number(result['total']);
        if (total > 0) {
          scoreTotal += score * 100 / total;
          scoredStudents++;
        }
      } else if (status == 'incomplete' || status == 'stopped') {
        incomplete++;
      }

      final flags = number(result['cheatingCount'] ?? result['cheatCount']);
      monitoringFlags += flags;
      if (flags > 0) flaggedStudents++;

      students.add(
        ReportableStudent(
          id: doc.id,
          name: (result['studentName'] ?? '').toString().trim(),
          email: (result['studentEmail'] ?? '').toString().trim(),
          strikes: flags,
          status: status,
        ),
      );
    }
    students.sort(
      (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
    );

    final startValue = data['startTime'];
    final startTime = startValue is Timestamp
        ? startValue.toDate()
        : startValue is DateTime
        ? startValue
        : null;

    return _ExamReport(
      id: id,
      subject: (data['subject'] ?? 'Untitled exam').toString(),
      classId: (data['classId'] ?? '').toString(),
      startTime: startTime,
      totalStudents: docs.length,
      completed: completed,
      incomplete: incomplete,
      flaggedStudents: flaggedStudents,
      monitoringFlags: monitoringFlags,
      averageScore: scoredStudents == 0 ? null : scoreTotal / scoredStudents,
      students: students,
    );
  }
}
