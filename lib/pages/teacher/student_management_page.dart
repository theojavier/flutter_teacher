import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../helpers/AppTheme.dart';
const Color _dashboardBlue = Color(0xFF153CFF);
class StudentManagementPage extends StatefulWidget {
  const StudentManagementPage({super.key});

  @override
  State<StudentManagementPage> createState() => _StudentManagementPageState();
}

class _StudentManagementPageState extends State<StudentManagementPage> {
  static const double _tableMinWidth = 1000;
  static const double _headingHeight = 44;
  static const double _rowHeight = 68;

  final _searchController = TextEditingController();
  final _horizontalController = ScrollController();
  final _dateFormat = DateFormat('MMM d, yyyy · h:mm a');

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _students = [];
  String _searchQuery = '';
  String? _selectedClassId;
  String? _loadError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStudents());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  Future<void> _loadStudents() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('getTeacherClassStudents');
      final result = await callable.call();
      final data = Map<String, dynamic>.from(result.data as Map);
      final classes = (data['classes'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
      final students = (data['students'] as List<dynamic>? ?? [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _classes = classes;
        _students = students;
        if (_selectedClassId != null &&
            !_classes.any((item) => item['id'] == _selectedClassId)) {
          _selectedClassId = null;
        }
        _loading = false;
      });
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.message ?? error.code;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Unable to load your class roster: $error';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _visibleStudents {
    final students = _students.where((student) {
      final classIds = (student['classIds'] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList();
      if (_selectedClassId != null && !classIds.contains(_selectedClassId)) {
        return false;
      }
      if (_searchQuery.isEmpty) return true;
      final searchable = [
        student['name'],
        student['studentId'],
        student['email'],
        student['program'],
        student['yearBlock'],
      ].map((value) => (value ?? '').toString().toLowerCase()).join(' ');
      return searchable.contains(_searchQuery);
    }).toList();

    students.sort(
      (a, b) => (a['name'] ?? '').toString().toLowerCase().compareTo(
        (b['name'] ?? '').toString().toLowerCase(),
      ),
    );
    return students;
  }

  @override
  Widget build(BuildContext context) {
    final students = _visibleStudents;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadStudents,
          color: AppTheme.accent,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(compact ? 16 : 24),
            children: [
              Text(
                '03 / CLASS MANAGEMENT',
                style: TextStyle(
            color: _dashboardBlue,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
              ),
              const SizedBox(height: 12),
              Text(
                'Students.',
                style: AppTheme.display(34, ls: -0.06, color: AppTheme.text),
              ),
              const SizedBox(height: 6),
              const Text(
                'Browse students enrolled in your assigned classes.',
                style: TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 22),
              _directoryCard(students),
            ],
          ),
        ),
      ),
    );
  }

  Widget _directoryCard(List<Map<String, dynamic>> students) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.header,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _directoryHeader(students.length),
          const Divider(height: 1, color: AppTheme.line),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                child: CircularProgressIndicator(color: AppTheme.accent),
              ),
            )
          else if (_loadError != null)
            _messageState(
              icon: Icons.error_outline,
              title: 'Unable to load students',
              message: _loadError!,
              action: TextButton.icon(
                onPressed: _loadStudents,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            )
          else if (_classes.isEmpty)
            _messageState(
              icon: Icons.class_outlined,
              title: 'No assigned classes',
              message:
                  'Students will appear here when a class is assigned to you.',
            )
          else if (_students.isEmpty)
            _messageState(
              icon: Icons.people_outline,
              title: 'No students enrolled',
              message:
                  'There are no student accounts enrolled in your assigned classes.',
            )
          else if (students.isEmpty)
            _messageState(
              icon: Icons.search_off,
              title: 'No matching students',
              message: 'Try another search or choose a different class.',
            )
          else
            _studentTable(students),
        ],
      ),
    );
  }

  OutlineInputBorder _fieldBorder([Color color = AppTheme.line]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: color),
      );

  Widget _directoryHeader(int visibleCount) {
    final total = _students.length;
    final filtered = _searchQuery.isNotEmpty || _selectedClassId != null;
    final subtitle = _loading
        ? 'Loading students...'
        : filtered
        ? 'Showing $visibleCount of $total students'
        : '$total enrolled student${total == 1 ? '' : 's'}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Student directory',
                style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 12),
              ),
            ],
          );
          final controls = Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: compact ? constraints.maxWidth : 230,
                height: 44,
                child: TextField(
                  controller: _searchController,
                  cursorColor: AppTheme.accent,
                  style: const TextStyle(color: AppTheme.text, fontSize: 13),
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search students...',
                    hintStyle: const TextStyle(
                      color: AppTheme.mutedText,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 19,
                      color: AppTheme.mutedText,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: AppTheme.header,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: _fieldBorder(),
                    enabledBorder: _fieldBorder(),
                    focusedBorder: _fieldBorder(AppTheme.accent),
                  ),
                ),
              ),
              SizedBox(
                width: compact ? constraints.maxWidth : 190,
                height: 44,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_selectedClassId),
                  initialValue: _selectedClassId ?? '',
                  isExpanded: true,
                  dropdownColor: AppTheme.header,
                  iconEnabledColor: AppTheme.mutedText,
                  style: const TextStyle(color: AppTheme.text, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppTheme.header,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: _fieldBorder(),
                    enabledBorder: _fieldBorder(),
                    focusedBorder: _fieldBorder(AppTheme.accent),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: '',
                      child: Text(
                        'All classes',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ..._classes.map(
                      (classInfo) => DropdownMenuItem(
                        value: classInfo['id'].toString(),
                        child: Text(
                          _classLabel(classInfo),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(
                    () => _selectedClassId = value == null || value.isEmpty
                        ? null
                        : value,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Refresh directory',
                onPressed: _loading ? null : _loadStudents,
                icon: const Icon(Icons.refresh, color: AppTheme.mutedText),
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [title, const SizedBox(height: 14), controls],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 20),
              controls,
            ],
          );
        },
      ),
    );
  }

  Widget _studentTable(List<Map<String, dynamic>> students) {
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
          child: Text(label, style: _headStyle),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: SizedBox(
        height: _headingHeight + students.length * _rowHeight + 16,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
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
                minWidth: constraints.maxWidth < _tableMinWidth
                    ? _tableMinWidth
                    : constraints.maxWidth,
                columnSpacing: 12,
                horizontalMargin: 16,
                headingRowHeight: _headingHeight,
                dataRowHeight: _rowHeight,
                headingRowColor: WidgetStateProperty.all(AppTheme.soft),
                fixedLeftColumns: 1,
                fixedColumnsColor: AppTheme.header,
                fixedCornerColor: AppTheme.soft,
                border: TableBorder(
                  horizontalInside: BorderSide(
                    color: AppTheme.line.withValues(alpha: 0.7),
                  ),
                ),
                columns: [
                  col('STUDENT', width: 280),
                  col('CLASS', size: ColumnSize.L),
                  col('EXAM ACCESS', width: 140, center: true),
                  col('LAST SESSION', width: 170),
                  col('STATUS', width: 110, center: true),
                  col('ACTION', width: 80, center: true),
                ],
                rows: students.map(_studentRow).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  TextStyle get _headStyle => AppTheme.mono(
    10,
    color: AppTheme.mutedText,
  ).copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.8);

  DataRow2 _studentRow(Map<String, dynamic> student) {
    final name = (student['name'] ?? '').toString().trim();
    final studentId = (student['studentId'] ?? '').toString().trim();
    final photoUrl = (student['profileImage'] ?? '').toString().trim();
    final status = (student['status'] ?? 'active').toString().toLowerCase();

    return DataRow2(
      onTap: () => _showStudentDetails(student),
      cells: [
        DataCell(
          Row(
            children: [
              _studentAvatar(photoUrl, name),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Student' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      studentId.isEmpty
                          ? (student['email'] ?? '').toString()
                          : studentId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        DataCell(
          Text(
            _classNames(student),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.text, fontSize: 12),
          ),
        ),
        DataCell(Center(child: _examAccessChip(student))),
        DataCell(Text(_lastSession(student), style: _cellTextStyle)),
        DataCell(Center(child: _statusChip(status))),
        DataCell(
          Center(
            child: Tooltip(
              message: 'View student details',
              child: Material(
                color: AppTheme.accent.withValues(alpha: 0.12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: AppTheme.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: InkWell(
                  customBorder: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  onTap: () => _showStudentDetails(student),
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.visibility_outlined,
                      size: 19,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static const _cellTextStyle = TextStyle(
    color: AppTheme.mutedText,
    fontSize: 12,
  );

  Widget _studentAvatar(String photoUrl, String name) {
    final initials = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return ClipOval(
      child: SizedBox(
        width: 38,
        height: 38,
        child: photoUrl.isEmpty
            ? _avatarFallback(initials)
            : Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _avatarFallback(initials),
              ),
      ),
    );
  }

  Widget _avatarFallback(String initials) => Container(
    color: AppTheme.soft,
    alignment: Alignment.center,
    child: Text(
      initials.isEmpty ? '?' : initials,
      style: const TextStyle(
        color: AppTheme.mutedText,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  String _classNames(Map<String, dynamic> student) {
    if (_selectedClassId != null) {
      final match = _classes.where((item) => item['id'] == _selectedClassId);
      if (match.isNotEmpty) return _classLabel(match.first);
    }
    final labels = (student['classLabels'] as List<dynamic>? ?? [])
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
    if (labels.isEmpty) return 'Class not available';
    return labels.take(2).join(', ');
  }

  String _classLabel(Map<String, dynamic> classInfo) {
    final parts =
        [classInfo['subject'], classInfo['yearBlock'], classInfo['semester']]
            .map((value) => (value ?? '').toString().trim())
            .where((value) => value.isNotEmpty)
            .toList();
    return parts.isEmpty
        ? (classInfo['classId'] ?? 'Class').toString()
        : parts.join(' · ');
  }

  Widget _examAccessChip(Map<String, dynamic> student) {
    var active = 0;
    var upcoming = 0;
    final byClass = Map<String, dynamic>.from(
      student['examAccessByClass'] as Map? ?? {},
    );
    final classIds = _selectedClassId == null
        ? byClass.keys
        : [_selectedClassId!];
    for (final id in classIds) {
      final access = Map<String, dynamic>.from(byClass[id] as Map? ?? {});
      active += (access['activeExamCount'] as num?)?.toInt() ?? 0;
      upcoming += (access['upcomingExamCount'] as num?)?.toInt() ?? 0;
    }

    if (active > 0) {
      return _pill('$active available', const Color(0xFF27804A));
    }
    if (upcoming > 0) {
      return _pill('$upcoming scheduled', const Color(0xFF2563EB));
    }
    return _pill('No exams', AppTheme.mutedText);
  }

  Widget _statusChip(String status) {
    final inactive = status == 'inactive';
    return _pill(
      inactive ? 'Inactive' : 'Active',
      inactive ? AppTheme.error : AppTheme.success,
    );
  }

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );

  String _lastSession(Map<String, dynamic> student) {
    final millis = (student['lastSessionMillis'] as num?)?.toInt();
    if (millis == null) return 'No session recorded';
    return _dateFormat.format(DateTime.fromMillisecondsSinceEpoch(millis));
  }

  Widget _messageState({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 52),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppTheme.mutedText, size: 36),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.text,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppTheme.mutedText,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 12), action],
      ],
    ),
  );

  Future<void> _showStudentDetails(Map<String, dynamic> student) {
    final photoUrl = (student['profileImage'] ?? '').toString().trim();
    final name = (student['name'] ?? 'Student').toString();
    final email = (student['email'] ?? '').toString();
    final id = (student['studentId'] ?? '').toString();
    final program = (student['program'] ?? '').toString();
    final yearBlock = (student['yearBlock'] ?? '').toString();
    final semester = (student['semester'] ?? '').toString();

    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.header,
        title: const Text('Student details'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (photoUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      photoUrl,
                      width: 112,
                      height: 112,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _studentAvatar('', name),
                    ),
                  )
                else
                  _studentAvatar('', name),
                const SizedBox(height: 14),
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _detailLine('Student ID', id),
                _detailLine('Email', email),
                _detailLine('Class', _classNames(student)),
                _detailLine('Program', program),
                _detailLine('Year / block', yearBlock),
                _detailLine('Semester', semester),
                _detailLine('Last session', _lastSession(student)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 105,
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.mutedText, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? 'Not available' : value,
            style: const TextStyle(color: AppTheme.text, fontSize: 12),
          ),
        ),
      ],
    ),
  );
}
