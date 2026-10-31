// lib/widgets/exam_form_dialog.dart
// Popup replacement for the old EditExamPage (create + edit).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '/helpers/AppTheme.dart';
import '/widgets/app_dialog.dart';

const _examBlueAccent = Color(0xFF153CFF);

/// What the popup tells the exams page when it closes.
class ExamDialogResult {
  final String examId;
  final bool openQuestions;
  const ExamDialogResult({required this.examId, this.openQuestions = false});
}

class _ClassScheduleEntry {
  const _ClassScheduleEntry({
    required this.classDoc,
    required this.start,
    required this.end,
  });

  final QueryDocumentSnapshot<Map<String, dynamic>> classDoc;
  final int start;
  final int end;
}

/// Open it with:
///   final r = await ExamFormDialog.show(context, docId: id, existing: data);
class ExamFormDialog extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? existing;

  const ExamFormDialog({super.key, this.docId, this.existing});

  static Future<ExamDialogResult?> show(
    BuildContext context, {
    String? docId,
    Map<String, dynamic>? existing,
  }) {
    return AppDialog.custom<ExamDialogResult>(
      context,
      builder: (_) => ExamFormDialog(docId: docId, existing: existing),
    );
  }

  @override
  State<ExamFormDialog> createState() => _ExamFormDialogState();
}

class _ExamFormDialogState extends State<ExamFormDialog> {
  static const Map<String, int> _dayNumbers = {
    'Monday': DateTime.monday,
    'Tuesday': DateTime.tuesday,
    'Wednesday': DateTime.wednesday,
    'Thursday': DateTime.thursday,
    'Friday': DateTime.friday,
    'Saturday': DateTime.saturday,
    'Sunday': DateTime.sunday,
  };

  final _formKey = GlobalKey<FormState>();
  final _db = FirebaseFirestore.instance;

  final _subjectController = TextEditingController();
  final _yearBlockController = TextEditingController();
  final _creatorController = TextEditingController();

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classes = [];
  Map<String, String> _programAcronyms = {};
  String? _selectedClassId;
  String? _teacherId;

  DateTime? _examDate;
  DateTime? _startTime;
  DateTime? _endTime;
  String? _selectedDayOfWeek;
  int? _selectedWindowStart;
  int? _selectedWindowEnd;

  // ON  = exam uses the class time automatically.
  // OFF = teacher sets a custom start / end time, but it must stay inside
  //       the class's scheduled time on that day.
  bool _useClassTime = true;

  String _statusValue = 'upcoming';
  String _approvalStatus = 'draft';
  String? _reviewNote;
  int? _questionCount;
  DateTime? _submittedAt;
  bool _isPc = true;
  bool _wasFinished = false;

  bool _loading = true;
  bool _saving = false;

  bool get _isEditing => widget.docId != null;
  bool get _isLocked =>
      _isEditing &&
      (![
            'draft',
            'changes_requested',
          ].contains(_approvalStatus.toLowerCase()) ||
          _wasFinished ||
          _statusValue == 'finished');

  bool _isFinishedExam(Map<String, dynamic> data) {
    const finishedStatuses = {'finished', 'finish', 'completed', 'complete'};
    final status = (data['status'] ?? '').toString().toLowerCase();
    final end = data['endTime'];
    return finishedStatuses.contains(status) ||
        (end is Timestamp && !end.toDate().isAfter(DateTime.now()));
  }

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) _applyExisting(widget.existing!);
    _loadInitial();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _yearBlockController.dispose();
    _creatorController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // LOAD
  // ---------------------------------------------------------------------

  void _applyExisting(Map<String, dynamic> data) {
    final status = (data['status'] ?? 'upcoming').toString().toLowerCase();
    _subjectController.text = (data['subject'] ?? '').toString();
    _yearBlockController.text = (data['yearBlock'] ?? '').toString();
    _creatorController.text = (data['creator'] ?? '').toString();
    final classId = (data['classId'] ?? '').toString().trim();
    _selectedClassId = classId.isEmpty ? null : classId;
    _isPc = data['isPc'] is bool ? data['isPc'] as bool : true;
    // Old exams without the flag are treated as custom-time exams.
    final special = data['isSpecialExam'] is bool
        ? data['isSpecialExam'] as bool
        : _isEditing;
    _useClassTime = !special;
    _selectedDayOfWeek = (data['dayOfWeek'] ?? '').toString().trim();
    if (_selectedDayOfWeek!.isEmpty) _selectedDayOfWeek = null;
    _approvalStatus = (data['approvalStatus'] ?? 'draft').toString();
    _reviewNote = (data['reviewNote'] ?? '').toString().trim();
    _questionCount = int.tryParse(data['questionCount']?.toString() ?? '');
    final start = data['startTime'];
    final end = data['endTime'];
    if (start is Timestamp) {
      _startTime = start.toDate();
      _examDate = DateUtils.dateOnly(_startTime!);
    }
    if (end is Timestamp) _endTime = end.toDate();
    final submitted = data['submittedAt'];
    _submittedAt = submitted is Timestamp ? submitted.toDate() : null;
    _wasFinished =
        ['finished', 'finish', 'completed', 'complete'].contains(status) ||
        (_endTime != null && !DateTime.now().isBefore(_endTime!));
    _statusValue = _wasFinished ? 'finished' : 'upcoming';
  }

  Future<void> _loadInitial() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw StateError('No signed-in teacher was found.');

      final userDoc = await _db.collection('users').doc(user.uid).get();
      if (!userDoc.exists) {
        throw StateError('The signed-in teacher profile could not be found.');
      }
      final profile = userDoc.data()!;

      final snap = await _db
          .collection('classes')
          .where('adviserId', isEqualTo: user.uid)
          .get();
      final programSnap = await _db.collection('programs').get();
      final classes = snap.docs.where((d) {
        final s = (d.data()['status'] ?? '').toString();
        return s != 'archived' && s != 'inactive';
      }).toList();

      final name =
          (profile['name'] ??
                  profile['fullName'] ??
                  profile['displayName'] ??
                  user.displayName ??
                  '')
              .toString()
              .trim();

      if (!mounted) return;
      setState(() {
        _teacherId = profile['ID']?.toString();
        _classes = classes;
        _programAcronyms = _buildProgramAcronyms(programSnap.docs);

        // Match the saved class, or fall back to the only class.
        if (_selectedClassId == null ||
            !classes.any((c) => c.id == _selectedClassId)) {
          final byFields = classes.where((c) {
            final d = c.data();
            return (d['subject'] ?? '').toString() == _subjectController.text &&
                (d['yearBlock'] ?? '').toString() == _yearBlockController.text;
          });
          _selectedClassId = byFields.isNotEmpty
              ? byFields.first.id
              : (!_isEditing && classes.length == 1 ? classes.first.id : null);
        }

        final c = _selectedClass;
        if (c != null) {
          if (_subjectController.text.trim().isEmpty) {
            _subjectController.text = (c['subject'] ?? '').toString();
          }
          if (_yearBlockController.text.trim().isEmpty) {
            _yearBlockController.text = (c['yearBlock'] ?? '').toString();
          }
          final classDays = _daysOf(c);
          if (_selectedDayOfWeek == null ||
              !classDays.contains(_selectedDayOfWeek)) {
            _selectedDayOfWeek = classDays.isEmpty ? null : classDays.first;
          }
          if (_selectedDayOfWeek != null) {
            final windows = _windowsForDay(c, _selectedDayOfWeek!);
            if (windows.isNotEmpty) {
              final start = _startTime == null
                  ? null
                  : _startTime!.hour * 60 + _startTime!.minute;
              final end = _endTime == null
                  ? null
                  : _endTime!.hour * 60 + _endTime!.minute;
              final matchingWindow = windows.where(
                (window) =>
                    start != null &&
                    end != null &&
                    window.start <= start &&
                    window.end >= end,
              );
              final window = matchingWindow.isNotEmpty
                  ? matchingWindow.first
                  : windows.first;
              _selectedWindowStart = window.start;
              _selectedWindowEnd = window.end;
            }
          }
        }
        if (_yearBlockController.text.trim().isEmpty) {
          _yearBlockController.text = (profile['yearBlock'] ?? '').toString();
        }
        if (_creatorController.text.trim().isEmpty) {
          _creatorController.text = name;
        }

        // New exam: start on the next date that matches the class day,
        // not just "today".
        if (_examDate == null) {
          final day = _selectedDayOfWeek;
          _examDate = day == null
              ? DateUtils.dateOnly(DateTime.now())
              : _nextDateForDay(DateTime.now(), day);
        }
        if (_useClassTime) _applyClassTime();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await AppDialog.alert(
        context,
        title: 'Unable to load teacher information',
        message: '$e',
        tone: AppTone.error,
      );
    }
  }

  // ---------------------------------------------------------------------
  // CLASS TIME
  // ---------------------------------------------------------------------

  Map<String, dynamic>? get _selectedClass {
    for (final c in _classes) {
      if (c.id == _selectedClassId) return c.data();
    }
    return null;
  }

  Map<String, String> _buildProgramAcronyms(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> programs,
  ) {
    final acronyms = <String, String>{};
    const ignoredWords = {'a', 'an', 'and', 'for', 'in', 'of', 'the', 'to'};
    for (final program in programs) {
      final data = program.data();
      final name = (data['name'] ?? '').toString().trim();
      if (name.isEmpty) continue;
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
      acronyms[name] = acronym;
      final code = (data['code'] ?? '').toString().trim();
      if (code.isNotEmpty) acronyms[code] = acronym;
    }
    return acronyms;
  }

  String _programLabel(Object? rawProgram) {
    final value = (rawProgram ?? '').toString().trim();
    return _programAcronyms[value] ?? value;
  }

  int? _minutesOf(Map<String, dynamic> data, String key, String labelKey) {
    final value = data[key];
    if (value is num) return value.toInt();
    final label = (data[labelKey] ?? '').toString().trim();
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)?$',
      caseSensitive: false,
    ).firstMatch(label);
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final meridiem = match.group(3)?.toUpperCase();
    if (minute > 59) return null;
    if (meridiem != null) {
      if (hour < 1 || hour > 12) return null;
      if (meridiem == 'AM' && hour == 12) hour = 0;
      if (meridiem == 'PM' && hour != 12) hour += 12;
    } else if (hour > 23) {
      return null;
    }
    return hour * 60 + minute;
  }

  List<String> _daysOf(Map<String, dynamic> data) {
    final days = <String>{};
    final schedules = data['schedules'];
    if (schedules is List && schedules.isNotEmpty) {
      for (final raw in schedules) {
        if (raw is! Map) continue;
        final schedule = Map<String, dynamic>.from(raw);
        final day = (schedule['dayOfWeek'] ?? '').toString().trim();
        if (_dayNumbers.containsKey(day)) days.add(day);
      }
    }
    if (days.isEmpty) {
      final rawScheduleDays = data['scheduleDays'];
      if (rawScheduleDays is List) {
        for (final rawDay in rawScheduleDays) {
          final day = rawDay.toString().trim();
          if (_dayNumbers.containsKey(day)) days.add(day);
        }
      }
    }
    if (days.isEmpty) {
      final raw = data['days'] ?? data['day'] ?? data['dayOfWeek'];
      final values = raw is List
          ? raw
          : raw is String
          ? raw.split(RegExp(r'[,/;\s]+'))
          : const <Object>[];
      for (final value in values) {
        final text = value.toString().trim();
        if (text.length < 3) continue;
        final day = _dayNumbers.keys.firstWhere(
          (name) => name.toLowerCase().startsWith(text.toLowerCase()),
          orElse: () => '',
        );
        if (day.isNotEmpty) days.add(day);
      }
    }
    return _dayNumbers.keys.where(days.contains).toList();
  }

  List<({int start, int end})> _windowsForDay(
    Map<String, dynamic> data,
    String day,
  ) {
    final windows = <({int start, int end})>[];
    final schedules = data['schedules'];
    if (schedules is List && schedules.isNotEmpty) {
      for (final raw in schedules) {
        if (raw is! Map) continue;
        final schedule = Map<String, dynamic>.from(raw);
        if ((schedule['dayOfWeek'] ?? '').toString().trim() != day) continue;
        final start = _minutesOf(schedule, 'startMinutes', 'startLabel');
        if (start == null) continue;
        final duration = schedule['durationMin'];
        final end =
            _minutesOf(schedule, 'endMinutes', 'endLabel') ??
            (duration is num && duration > 0 ? start + duration.toInt() : null);
        if (end != null && end > start) {
          windows.add((start: start, end: end));
        }
      }
    } else if ((data['dayOfWeek'] ?? '').toString().trim() == day) {
      final start = _minutesOf(data, 'startMinutes', 'startLabel');
      final duration = data['durationMin'];
      final end =
          _minutesOf(data, 'endMinutes', 'endLabel') ??
          (duration is num && duration > 0 && start != null
              ? start + duration.toInt()
              : null);
      if (start != null && end != null && end > start) {
        windows.add((start: start, end: end));
      }
    }
    windows.sort((first, second) => first.start.compareTo(second.start));
    return windows;
  }

  /// The time window the exam must stay inside (the selected class's slot).
  ({int start, int end})? get _selectedClassWindow {
    final c = _selectedClass;
    final day = _selectedDayOfWeek;
    if (c == null || day == null) return null;
    final windows = _windowsForDay(c, day);
    if (windows.isEmpty) return null;
    for (final window in windows) {
      if (window.start == _selectedWindowStart &&
          window.end == _selectedWindowEnd) {
        return window;
      }
    }
    return windows.first;
  }

  String _fmtMinutes(int minutes) => DateFormat(
    'h:mm a',
  ).format(DateTime(2000, 1, 1, (minutes ~/ 60) % 24, minutes % 60));

  /// All of this teacher's classes on [day] that have a valid time,
  /// earliest first.
  List<_ClassScheduleEntry> _slotsForDay(String day) {
    final slots = <_ClassScheduleEntry>[];
    for (final classDoc in _classes) {
      for (final window in _windowsForDay(classDoc.data(), day)) {
        slots.add(
          _ClassScheduleEntry(
            classDoc: classDoc,
            start: window.start,
            end: window.end,
          ),
        );
      }
    }
    slots.sort((first, second) => first.start.compareTo(second.start));
    return slots;
  }

  /// Fills _startTime/_endTime from the class schedule + exam date.
  void _applyClassTime() {
    final window = _selectedClassWindow;
    if (window == null || _examDate == null) {
      _startTime = null;
      _endTime = null;
      return;
    }
    final d = DateUtils.dateOnly(_examDate!);
    _startTime = DateTime(
      d.year,
      d.month,
      d.day,
      window.start ~/ 60,
      window.start % 60,
    );
    _endTime = DateTime(
      d.year,
      d.month,
      d.day,
    ).add(Duration(minutes: window.end));
  }

  /// Keeps the picked custom times, but moves them onto the current exam date.
  void _moveTimesToExamDate() {
    final d = _examDate;
    if (d == null) return;
    DateTime? move(DateTime? t) =>
        t == null ? null : DateTime(d.year, d.month, d.day, t.hour, t.minute);
    _startTime = move(_startTime);
    _endTime = move(_endTime);
  }

  String _classTimeLabel() {
    final c = _selectedClass;
    if (c == null) return 'Choose a class to use its scheduled time.';
    final window = _selectedClassWindow;
    if (window == null) {
      return 'This class has no valid time. Ask an administrator to fix it.';
    }
    final minutes = window.end - window.start;
    return '${_fmtMinutes(window.start)} – ${_fmtMinutes(window.end)} · $minutes min';
  }

  void _setUseClassTime(bool value) {
    setState(() {
      _useClassTime = value;
      if (value) {
        _applyClassTime(); // snap back to the class schedule
      } else {
        // Start the custom time from whatever the class gave, so the
        // teacher only has to tweak it.
        if (_startTime == null || _endTime == null) _applyClassTime();
      }
    });
  }

  /// Picks a class (from the dropdown or the schedule list) and moves the
  /// day, date and times to match it.
  void _selectClass(String id, {int? windowStart, int? windowEnd}) {
    final c = _classes.firstWhere((x) => x.id == id).data();
    setState(() {
      _selectedClassId = id;
      _yearBlockController.text = (c['yearBlock'] ?? '').toString();
      _subjectController.text = (c['subject'] ?? '').toString();
      final classDays = _daysOf(c);
      if (_selectedDayOfWeek == null ||
          !classDays.contains(_selectedDayOfWeek)) {
        _selectedDayOfWeek = classDays.isEmpty ? null : classDays.first;
      }
      final day = _selectedDayOfWeek;
      final windows = day == null
          ? const <({int start, int end})>[]
          : _windowsForDay(c, day);
      final selectedWindow = windows.where(
        (window) => window.start == windowStart && window.end == windowEnd,
      );
      final window = selectedWindow.isNotEmpty
          ? selectedWindow.first
          : windows.isEmpty
          ? null
          : windows.first;
      _selectedWindowStart = window?.start;
      _selectedWindowEnd = window?.end;
      // Keep the date on the class's weekday.
      if (day != null &&
          day.isNotEmpty &&
          (_examDate == null || _examDate!.weekday != _getWeekdayNumber(day))) {
        _examDate = _nextDateForDay(DateTime.now(), day);
      }
      _applyClassTime();
    });
  }

  // ---------------------------------------------------------------------
  // PICKERS
  // ---------------------------------------------------------------------

  Widget _pickerTheme(BuildContext context, Widget child) => Theme(
    data: Theme.of(context).copyWith(
      colorScheme: ColorScheme.light(
        primary: _examBlueAccent,
        onPrimary: Colors.white,
        surface: AppTheme.header,
        onSurface: AppTheme.text,
      ),
    ),
    child: child,
  );

  int _getWeekdayNumber(String dayName) =>
      _dayNumbers[dayName] ?? DateTime.monday;

  /// Find the next date (today included) that matches the selected day.
  DateTime _nextDateForDay(DateTime from, String dayName) {
    final targetWeekday = _dayNumbers[dayName];
    final candidate = DateUtils.dateOnly(from);
    if (targetWeekday == null) return candidate;
    final daysUntilTarget = (targetWeekday - candidate.weekday + 7) % 7;
    return candidate.add(Duration(days: daysUntilTarget));
  }

  Future<void> _pickExamDate() async {
    if (_selectedDayOfWeek == null || _selectedDayOfWeek!.isEmpty) {
      await _warn(
        'Select a day first',
        'Please select the day of the week before choosing the exam date.',
      );
      return;
    }

    final weekday = _getWeekdayNumber(_selectedDayOfWeek!);
    final today = DateUtils.dateOnly(DateTime.now());
    final firstDate = _isEditing ? DateTime(2024) : today;
    final nextValidDate = _nextDateForDay(today, _selectedDayOfWeek!);
    var initialDate = _examDate != null && _examDate!.weekday == weekday
        ? _examDate!
        : nextValidDate;
    if (initialDate.isBefore(firstDate)) initialDate = nextValidDate;

    final date = await AppDialog.custom<DateTime>(
      context,
      builder: (c) => _pickerTheme(
        c,
        DatePickerDialog(
          initialDate: initialDate,
          firstDate: firstDate,
          lastDate: DateTime(2100),
          // Only dates that fall on the selected day of the week.
          selectableDayPredicate: (date) => date.weekday == weekday,
        ),
      ),
    );
    if (!mounted || date == null) return;

    if (date.weekday != weekday) {
      await _warn(
        'Invalid date',
        'Please select a ${_selectedDayOfWeek!} date.',
      );
      return;
    }

    setState(() {
      _examDate = DateUtils.dateOnly(date);
      if (_useClassTime) {
        _applyClassTime();
      } else {
        _moveTimesToExamDate();
      }
    });
  }

  /// Custom-time mode: pick a start or end time that stays inside the
  /// selected class's scheduled time on the exam day.
  Future<void> _pickTime(bool isStart) async {
    if (_selectedClass == null) {
      await _warn(
        'Choose a class first',
        'Pick a class so its scheduled time on this day is known.',
      );
      return;
    }
    final window = _selectedClassWindow;
    if (window == null) {
      await _warn(
        'Class has no valid time',
        'Ask an administrator to set this class\'s start time and duration.',
        tone: AppTone.error,
      );
      return;
    }
    if (_examDate == null) {
      await _warn('Pick the exam date first', 'Choose the exam date above.');
      return;
    }

    final current = isStart ? _startTime : _endTime;
    final fallback = isStart ? window.start : window.end;
    final initial = current != null
        ? TimeOfDay.fromDateTime(current)
        : TimeOfDay(hour: fallback ~/ 60, minute: fallback % 60);

    final time = await AppDialog.custom<TimeOfDay>(
      context,
      builder: (c) => _pickerTheme(
        c,
        TimePickerDialog(
          initialTime: initial,
          helpText: isStart ? 'SELECT START TIME' : 'SELECT END TIME',
        ),
      ),
    );
    if (!mounted || time == null) return;

    final minutes = time.hour * 60 + time.minute;
    if (minutes < window.start || minutes > window.end) {
      await _warn(
        'Outside the class schedule',
        'Pick a time between ${_fmtMinutes(window.start)} and '
            '${_fmtMinutes(window.end)}. That is this class\'s schedule on '
            '${_selectedDayOfWeek ?? 'this day'}.',
      );
      return;
    }

    final other = isStart ? _endTime : _startTime;
    if (other != null) {
      final otherMinutes = other.hour * 60 + other.minute;
      final invalid = isStart
          ? minutes >= otherMinutes
          : minutes <= otherMinutes;
      if (invalid) {
        await _warn(
          'Invalid exam time',
          isStart
              ? 'Start time must be before the end time.'
              : 'End time must be after the start time.',
        );
        return;
      }
    }

    final d = DateUtils.dateOnly(_examDate!);
    final picked = DateTime(d.year, d.month, d.day, time.hour, time.minute);
    setState(() => isStart ? _startTime = picked : _endTime = picked);
  }

  // ---------------------------------------------------------------------
  // SAVE
  // ---------------------------------------------------------------------

  Future<void> _warn(
    String title,
    String message, {
    AppTone tone = AppTone.warning,
  }) {
    return AppDialog.alert(context, title: title, message: message, tone: tone);
  }

  /// Check for scheduling conflicts with other classes and exams.
  /// Returns a warning message if conflicts exist, null otherwise.
  Future<String?> _checkConflicts(
    String program,
    DateTime start,
    DateTime end,
  ) async {
    final cls = _selectedClass;
    if (cls == null || _selectedDayOfWeek == null) return null;

    final conflicts = <String>[];
    final yearBlock = _yearBlockController.text.trim();
    final semester = (cls['semester'] ?? '').toString().trim();
    final schoolYear = (cls['schoolYear'] ?? '').toString().trim();
    final room = (cls['roomDefault'] ?? '').toString().trim();

    // Check for overlapping classes on the same day
    if (room.isNotEmpty &&
        semester.isNotEmpty &&
        schoolYear.isNotEmpty &&
        _selectedDayOfWeek!.isNotEmpty) {
      try {
        final classesSnap = await _db
            .collection('classes')
            .where('semester', isEqualTo: semester)
            .where('schoolYear', isEqualTo: schoolYear)
            .get();

        for (final doc in classesSnap.docs) {
          if (doc.id == _selectedClassId) continue;

          final data = doc.data();
          final classRoom = (data['roomDefault'] ?? '').toString().trim();
          if (classRoom != room) continue;

          for (final window in _windowsForDay(data, _selectedDayOfWeek!)) {
            final classStart = DateTime(
              start.year,
              start.month,
              start.day,
              window.start ~/ 60,
              window.start % 60,
            );
            final classEnd = DateTime(
              start.year,
              start.month,
              start.day,
              window.end ~/ 60,
              window.end % 60,
            );

            if (start.isBefore(classEnd) && end.isAfter(classStart)) {
              final classInfo =
                  '${doc.id} · ${data['program'] ?? 'Unknown'} · '
                  '${data['yearBlock'] ?? ''} · ${data['subject'] ?? ''}';
              conflicts.add(
                'Room $room: Class "$classInfo" runs '
                '${DateFormat('h:mm a').format(classStart)} - '
                '${DateFormat('h:mm a').format(classEnd)}',
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Error checking class conflicts: $e');
      }
    }

    // Check for overlapping exams on the same day, program, yearBlock, semester
    if (program.isNotEmpty &&
        yearBlock.isNotEmpty &&
        semester.isNotEmpty &&
        schoolYear.isNotEmpty &&
        _selectedDayOfWeek!.isNotEmpty) {
      try {
        final examsSnap = await _db
            .collection('exams')
            .where('program', isEqualTo: program)
            .where('yearBlock', isEqualTo: yearBlock)
            .where('dayOfWeek', isEqualTo: _selectedDayOfWeek)
            .get();

        for (final doc in examsSnap.docs) {
          if (_isEditing && doc.id == widget.docId) continue;

          final data = doc.data();
          final examStart = data['startTime'];
          final examEnd = data['endTime'];
          if (examStart is! Timestamp || examEnd is! Timestamp) continue;

          final eStart = examStart.toDate();
          final eEnd = examEnd.toDate();

          // Check if on the same date
          if (DateUtils.dateOnly(
            eStart,
          ).isAtSameMomentAs(DateUtils.dateOnly(start))) {
            // Check for time overlap
            if ((start.isBefore(eEnd) && end.isAfter(eStart))) {
              final subject = (data['subject'] ?? 'Untitled exam').toString();
              conflicts.add(
                'Exam "$subject" is scheduled ${DateFormat('h:mm a').format(eStart)} - ${DateFormat('h:mm a').format(eEnd)}',
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Error checking exam conflicts: $e');
      }
    }

    if (conflicts.isEmpty) return null;

    return 'The following conflicts were detected:\n\n${conflicts.map((c) => '• $c').join('\n')}\n\nDo you want to save this exam anyway?';
  }

  /// Returns the exam id on success, null on failure.
  Future<String?> _save() async {
    if (_isLocked) {
      await _warn(
        'Exam is locked',
        'Approved or pending exams cannot be changed.',
      );
      return null;
    }
    if (_loading) {
      await _warn('Still loading', 'Please wait for your profile to load.');
      return null;
    }
    if (!_formKey.currentState!.validate()) return null;

    if (_selectedDayOfWeek == null || _selectedDayOfWeek!.trim().isEmpty) {
      await _warn(
        'Day required',
        'Please select the day of the week for this exam.',
      );
      return null;
    }

    final cls = _selectedClass;
    if (_selectedClassId == null || cls == null) {
      await _warn('Class required', 'Choose one of your assigned classes.');
      return null;
    }
    final program = (cls['program'] ?? '').toString().trim();
    if (program.isEmpty) {
      await _warn(
        'Class program is missing',
        'Ask an administrator to complete the program details for this class.',
        tone: AppTone.error,
      );
      return null;
    }

    if (_useClassTime) _applyClassTime();
    final start = _startTime;
    final end = _endTime;
    if (start == null || end == null) {
      await _warn(
        'Exam time required',
        _useClassTime
            ? 'This class has no valid scheduled time. Turn off "Use class time" to set one.'
            : 'Please select a start and end time.',
      );
      return null;
    }
    if (!end.isAfter(start)) {
      await _warn('Invalid exam time', 'End time must be after start time.');
      return null;
    }

    // The exam date must fall on the selected day of the week.
    if (start.weekday != _getWeekdayNumber(_selectedDayOfWeek!)) {
      await _warn(
        'Wrong day',
        'The exam date must be a $_selectedDayOfWeek. Pick the date again.',
      );
      return null;
    }

    // Custom times must stay inside the class's scheduled time.
    if (!_useClassTime) {
      final window = _selectedClassWindow;
      if (window == null) {
        await _warn(
          'Class has no valid time',
          'Ask an administrator to set this class\'s start time and duration.',
          tone: AppTone.error,
        );
        return null;
      }
      final startMin = start.hour * 60 + start.minute;
      final endMin = end.hour * 60 + end.minute;
      if (startMin < window.start || endMin > window.end) {
        await _warn(
          'Outside the class schedule',
          'Exam time must be between ${_fmtMinutes(window.start)} and '
              '${_fmtMinutes(window.end)} on $_selectedDayOfWeek.',
        );
        return null;
      }
    }

    if (_teacherId == null || _teacherId!.trim().isEmpty) {
      await _warn(
        'Teacher ID required',
        'Teacher ID is required to save this exam.',
      );
      return null;
    }

    // Check for conflicts (classes, exams) on the same day, time, and room
    final conflict = await _checkConflicts(program, start, end);
    if (conflict != null) {
      final proceed = await AppDialog.confirm(
        context,
        title: 'Scheduling conflict detected',
        message: conflict,
        confirmLabel: 'Save anyway',
        tone: AppTone.warning,
      );
      if (!proceed) return null;
    }

    setState(() => _saving = true);
    final teacherId = _teacherId!.trim();
    final data = <String, dynamic>{
      'program': program,
      'classId': _selectedClassId!,
      'subject': (cls['subject'] ?? _subjectController.text).toString().trim(),
      'yearBlock': _yearBlockController.text.trim(),
      if (!_isEditing) 'creator': _creatorController.text.trim(),
      'dayOfWeek': _selectedDayOfWeek!,
      if (!_isEditing) 'status': 'upcoming',
      'isPc': _isPc,
      'isSpecialExam': !_useClassTime,
      'teacherId': teacherId,
      'startTime': Timestamp.fromDate(start),
      'endTime': Timestamp.fromDate(end),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (_isEditing) {
        final fresh = await _db.collection('exams').doc(widget.docId).get();
        final freshData = fresh.data();
        final approvalStatus = (freshData?['approvalStatus'] ?? 'draft')
            .toString()
            .toLowerCase();
        if (!fresh.exists ||
            !['draft', 'changes_requested'].contains(approvalStatus) ||
            freshData == null ||
            _isFinishedExam(freshData) ||
            freshData['teacherId'] != teacherId) {
          await _warn(
            'Exam is locked',
            'Only your unfinished draft or an exam returned for changes can be edited.',
          );
          return null;
        }
      }
      final String examId;
      if (!_isEditing) {
        final ref = await _db.collection('exams').add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
        examId = ref.id;
      } else {
        examId = widget.docId!;
        await _db.collection('exams').doc(examId).update(data);
      }

      await _db.collection('examResults').doc(examId).set({
        'teacherId': teacherId,
        'examId': examId,
        'classId': _selectedClassId!,
        'yearBlock': _yearBlockController.text.trim(),
        'program': program,
      }, SetOptions(merge: true));

      return examId;
    } catch (e) {
      if (mounted) {
        await _warn('Unable to save exam', '$e', tone: AppTone.error);
      }
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onSavePressed() async {
    final id = await _save();
    if (id == null || !mounted) return;
    await AppDialog.alert(
      context,
      title: _isEditing ? 'Exam updated' : 'Exam created',
      message: _isEditing
          ? 'Exam updated successfully!'
          : 'Exam saved successfully!',
      tone: AppTone.success,
    );
    if (!mounted) return;
    Navigator.of(context).pop(ExamDialogResult(examId: id));
  }

  Future<void> _onQuestionsPressed() async {
    if (_isEditing) {
      Navigator.of(
        context,
      ).pop(ExamDialogResult(examId: widget.docId!, openQuestions: true));
      return;
    }
    // New exam: save first, then jump to the questions.
    final id = await _save();
    if (id == null || !mounted) return;
    Navigator.of(
      context,
    ).pop(ExamDialogResult(examId: id, openQuestions: true));
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      backgroundColor: AppTheme.header,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: size.width < 600 ? 12 : 24,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.line),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _titleBar(),
            const Divider(height: 1, color: AppTheme.line),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: _examBlueAccent,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_isLocked) ...[
                              _lockedBanner(),
                              const SizedBox(height: 16),
                            ],
                            IgnorePointer(
                              ignoring: _isLocked,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _detailsSection(),
                                  if (_isEditing) ...[
                                    const SizedBox(height: 16),
                                    _reviewSection(),
                                  ],
                                  const SizedBox(height: 16),
                                  _scheduleSection(),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _questionsButton(),
                          ],
                        ),
                      ),
                    ),
            ),
            const Divider(height: 1, color: AppTheme.line),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _titleBar() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
    child: Row(
      children: [
        Icon(
          _isLocked
              ? Icons.lock_outline
              : _isEditing
              ? Icons.edit_note
              : Icons.add_circle_outline,
          color: _examBlueAccent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _isLocked
                ? 'View Exam'
                : _isEditing
                ? 'Edit Exam'
                : 'Add Exam',
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: AppTheme.mutedText),
        ),
      ],
    ),
  );

  Widget _footer() {
    if (_isLocked) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: TextButton(
            style: AppTheme.ghostButton(),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              style: AppTheme.ghostButton(),
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              style: AppTheme.primaryButton(),
              onPressed: _saving || _loading ? null : _onSavePressed,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_saving ? 'Saving...' : 'Save'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lockedBanner() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.accentSoft,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.accent.withValues(alpha: 0.25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline, size: 18, color: _examBlueAccent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _approvalStatus == 'approved'
                ? 'This exam is approved and locked. You can view it but not change it.'
                : 'This exam is waiting for admin review and is locked until the review is finished.',
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: AppTheme.cardDecoration(),
    child: child,
  );

  Widget _sectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _examBlueAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: _examBlueAccent),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Container(height: 1, color: AppTheme.line)),
        ],
      ),
    );
  }

  // ---- details -----------------------------------------------------------

  Widget _detailsSection() => _card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(Icons.info_outline, 'Exam Details'),
        _dayOfWeekDropdown(),
        _classDropdown(),
        _readOnly(
          _subjectController,
          'Subject',
          Icons.menu_book_outlined,
          'Choose a class to fill in the subject.',
        ),
        _readOnly(
          _yearBlockController,
          'Year/Block',
          Icons.groups_outlined,
          'Year/block is missing from your profile.',
        ),
        _readOnly(
          _creatorController,
          'Creator (Teacher)',
          Icons.person_outline,
          'Name is missing from your profile.',
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(_statusValue),
          initialValue: _statusValue,
          dropdownColor: AppTheme.header,
          iconEnabledColor: AppTheme.mutedText,
          style: const TextStyle(color: AppTheme.text),
          decoration: AppTheme.inputDecoration(
            'Status',
            icon: Icons.flag_outlined,
            helper: 'Status is managed automatically.',
          ),
          items: const [
            DropdownMenuItem(value: 'upcoming', child: Text('Upcoming')),
            DropdownMenuItem(value: 'finished', child: Text('Finished')),
          ],
          onChanged: null,
        ),
        const SizedBox(height: 14),
        _switchTile(
          value: _isPc,
          onChanged: (v) => setState(() => _isPc = v),
          icon: _isPc
              ? Icons.desktop_windows_outlined
              : Icons.smartphone_outlined,
          title: _isPc
              ? 'PC (screen recording on)'
              : 'Mobile (no screen recording)',
        ),
      ],
    ),
  );

  Widget _switchTile({
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    required String title,
    String? subtitle,
  }) => Material(
    color: AppTheme.bg,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: AppTheme.line),
    ),
    child: SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppTheme.accent,
      secondary: Icon(icon, color: AppTheme.mutedText),
      title: Text(
        title,
        style: const TextStyle(color: AppTheme.text, fontSize: 14),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: const TextStyle(
                color: AppTheme.mutedText,
                fontSize: 12,
                height: 1.4,
              ),
            ),
    ),
  );

  Widget _dayOfWeekDropdown() {
    final days = _dayNumbers.keys.toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        key: ValueKey(_selectedDayOfWeek),
        initialValue: _selectedDayOfWeek,
        isExpanded: true,
        dropdownColor: AppTheme.header,
        iconEnabledColor: AppTheme.mutedText,
        style: const TextStyle(color: AppTheme.text),
        decoration: AppTheme.inputDecoration(
          'Day of week',
          icon: Icons.calendar_today_outlined,
          helper: 'Select the day to filter classes and check for conflicts.',
        ),
        items: days
            .map((day) => DropdownMenuItem(value: day, child: Text(day)))
            .toList(),
        onChanged: _loading || _isLocked
            ? null
            : (day) {
                if (day == null) return;
                setState(() {
                  _selectedDayOfWeek = day;

                  // Automatically set exam date to next occurrence of this day
                  _examDate = _nextDateForDay(DateTime.now(), day);

                  // Reset class selection if current class doesn't match day
                  if (_selectedClassId != null) {
                    final selectedClass = _classes.where(
                      (c) => c.id == _selectedClassId,
                    );
                    final currentClass = selectedClass.isEmpty
                        ? null
                        : selectedClass.first.data();
                    if (currentClass == null ||
                        !_daysOf(currentClass).contains(day)) {
                      _selectedClassId = null;
                      _subjectController.clear();
                      _yearBlockController.clear();
                      _selectedWindowStart = null;
                      _selectedWindowEnd = null;
                    } else {
                      final windows = _windowsForDay(currentClass, day);
                      _selectedWindowStart = windows.isEmpty
                          ? null
                          : windows.first.start;
                      _selectedWindowEnd = windows.isEmpty
                          ? null
                          : windows.first.end;
                    }
                  }

                  // Re-derive the times for the new day (or clear them if
                  // no class is selected any more).
                  _applyClassTime();
                });
              },
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Select a day of the week' : null,
      ),
    );
  }

  Widget _classDropdown() {
    final selected = _classes.any((c) => c.id == _selectedClassId)
        ? _selectedClassId
        : null;

    // Filter classes by selected day
    final filteredClasses = _selectedDayOfWeek == null
        ? _classes
        : _classes.where((c) {
            return _daysOf(c.data()).contains(_selectedDayOfWeek);
          }).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        key: ValueKey(selected),
        initialValue: selected,
        isExpanded: true,
        dropdownColor: AppTheme.header,
        iconEnabledColor: AppTheme.mutedText,
        style: const TextStyle(color: AppTheme.text),
        decoration: AppTheme.inputDecoration(
          'Assigned class',
          icon: Icons.school_outlined,
          helper: _classes.isEmpty && !_loading
              ? 'Ask an administrator to assign you to a class first.'
              : _selectedDayOfWeek != null && filteredClasses.isEmpty
              ? 'No classes match the selected day. Choose a different day.'
              : null,
        ),
        items: filteredClasses
            .map(
              (c) => DropdownMenuItem(
                value: c.id,
                child: Text(
                  [
                        'Class ${c.id}',
                        if ((c.data()['subject'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty)
                          'Subject: ${c.data()['subject']}',
                        _programLabel(c.data()['program']),
                        c.data()['yearBlock'],
                      ]
                      .where((v) => v != null && v.toString().isNotEmpty)
                      .join(' · '),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: _loading || filteredClasses.isEmpty || _isLocked
            ? null
            : (id) {
                if (id == null) return;
                _selectClass(id);
              },
        validator: (v) => (v == null || v.trim().isEmpty)
            ? (_classes.isEmpty
                  ? 'You need an assigned class before creating an exam.'
                  : 'Choose a class')
            : null,
      ),
    );
  }

  Widget _readOnly(
    TextEditingController c,
    String label,
    IconData icon,
    String emptyMessage,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: c,
      readOnly: true,
      style: const TextStyle(color: AppTheme.text),
      decoration: AppTheme.inputDecoration(label, icon: icon),
      validator: (v) => (v == null || v.trim().isEmpty) ? emptyMessage : null,
    ),
  );

  // ---- review (read only) ------------------------------------------------

  Widget _reviewSection() {
    final color = switch (_approvalStatus) {
      'pending' => const Color(0xFFB7791F),
      'approved' => AppTheme.success,
      'changes_requested' => AppTheme.error,
      _ => AppTheme.mutedText,
    };
    final label = switch (_approvalStatus) {
      'pending' => 'Pending review',
      'approved' => 'Approved',
      'changes_requested' => 'Changes requested',
      _ => 'Draft',
    };
    final submitted = _submittedAt == null
        ? 'Not submitted yet'
        : DateFormat('MMM d, yyyy – hh:mm a').format(_submittedAt!);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.fact_check_outlined, 'Approval details'),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _questionCount == null
                    ? 'Questions: not available'
                    : 'Questions: $_questionCount',
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 12),
              ),
              Text(
                'Submitted: $submitted',
                style: const TextStyle(color: AppTheme.mutedText, fontSize: 12),
              ),
            ],
          ),
          if (_reviewNote != null && _reviewNote!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.redSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.25),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ADMIN REVIEW NOTE',
                    style: TextStyle(
                      color: AppTheme.redDark,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _reviewNote!,
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---- schedule ----------------------------------------------------------

  Widget _scheduleSection() {
    final date = _examDate ?? DateTime.now();
    final window = _selectedClassWindow;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.schedule, 'Exam schedule'),

          // ON / OFF switch for the automatic class timer
          _switchTile(
            value: _useClassTime,
            onChanged: _setUseClassTime,
            icon: _useClassTime ? Icons.timer_outlined : Icons.tune_outlined,
            title: _useClassTime
                ? 'Use class time (automatic)'
                : 'Custom time (within class schedule)',
            subtitle: _useClassTime
                ? 'Start and end follow the class schedule.'
                : 'Pick your own start and end, inside the class time.',
          ),
          const SizedBox(height: 14),

          // The date is picked in both modes, limited to the chosen weekday.
          InkWell(
            onTap: _pickExamDate,
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: AppTheme.inputDecoration(
                'Exam date',
                icon: Icons.event_outlined,
                helper: _selectedDayOfWeek == null
                    ? 'Select a day of week first'
                    : 'Tap to choose a different ${_selectedDayOfWeek!} date',
              ),
              child: Text(
                DateFormat('EEEE, MMM d, yyyy').format(date),
                style: const TextStyle(color: AppTheme.text),
              ),
            ),
          ),
          const SizedBox(height: 12),

          _daySchedule(),

          if (_useClassTime)
            _timeInfoBox('CLASS TIME', _classTimeLabel())
          else ...[
            _timeInfoBox(
              'ALLOWED TIME',
              window == null
                  ? _classTimeLabel()
                  : '${_fmtMinutes(window.start)} – ${_fmtMinutes(window.end)} '
                        '(class schedule)',
            ),
            const SizedBox(height: 12),
            _timeField('Start Time', _startTime, () => _pickTime(true)),
            const SizedBox(height: 14),
            _timeField('End Time', _endTime, () => _pickTime(false)),
          ],
        ],
      ),
    );
  }

  /// Every class this teacher has on the selected day, so they can see the
  /// day's schedule and tap the slot they want to give an exam to.
  Widget _daySchedule() {
    final day = _selectedDayOfWeek;
    if (day == null) return const SizedBox.shrink();
    final slots = _slotsForDay(day);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'YOUR SCHEDULE ON ${day.toUpperCase()}',
              style: const TextStyle(
                color: AppTheme.mutedText,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            if (slots.isEmpty)
              const Text(
                'No classes with a valid time on this day.',
                style: TextStyle(color: AppTheme.mutedText, fontSize: 12.5),
              )
            else
              for (final c in slots) _slotTile(c),
          ],
        ),
      ),
    );
  }

  Widget _slotTile(_ClassScheduleEntry slot) {
    final c = slot.classDoc;
    final data = c.data();
    final selected =
        c.id == _selectedClassId &&
        slot.start == _selectedWindowStart &&
        slot.end == _selectedWindowEnd;
    final details = [
      'Class ${c.id}',
      data['subject'],
      _programLabel(data['program']),
      data['yearBlock'],
      data['roomDefault'],
    ].where((v) => v != null && v.toString().trim().isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: _isLocked
            ? null
            : () => _selectClass(
                c.id,
                windowStart: slot.start,
                windowEnd: slot.end,
              ),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accent.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.line,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? _examBlueAccent : AppTheme.mutedText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_fmtMinutes(slot.start)} – ${_fmtMinutes(slot.end)}',
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        details,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.mutedText,
                          fontSize: 12,
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

  Widget _timeInfoBox(String caption, String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: AppTheme.bg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.line),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.access_time_outlined,
          size: 18,
          color: _examBlueAccent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                caption,
                style: const TextStyle(
                  color: AppTheme.mutedText,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                text,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _timeField(String label, DateTime? dt, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: InputDecorator(
      decoration: AppTheme.inputDecoration(
        label,
        icon: Icons.access_time_outlined,
      ),
      child: Text(
        dt == null ? 'Select time' : DateFormat('h:mm a').format(dt),
        style: TextStyle(
          color: dt == null ? AppTheme.mutedText : AppTheme.text,
        ),
      ),
    ),
  );

  Widget _questionsButton() => OutlinedButton.icon(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppTheme.text,
      side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.6)),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    icon: Icon(_isLocked ? Icons.visibility_outlined : Icons.edit_note),
    label: Text(
      _isLocked
          ? 'View questions'
          : _isEditing
          ? 'Edit questions'
          : 'Save & add questions',
    ),
    onPressed: _saving || _loading ? null : _onQuestionsPressed,
  );
}
