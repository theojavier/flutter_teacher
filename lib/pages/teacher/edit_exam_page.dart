import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../helpers/AppTheme.dart';
import '../../widgets/app_dialog.dart';

class EditExamPage extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? existing;

  const EditExamPage({super.key, this.docId, this.existing});

  @override
  State<EditExamPage> createState() => _EditExamPageState();
}

class _EditExamPageState extends State<EditExamPage> {
  final _formKey = GlobalKey<FormState>();
  final _db = FirebaseFirestore.instance;

  bool _isSaving = false;
  bool _isLoadingTeacherProfile = true;

  final _subjectController = TextEditingController();
  final _yearBlockController = TextEditingController();
  final _creatorController = TextEditingController();
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classes = [];
  Map<String, String> _programAcronyms = {};
  String? _selectedProgram;
  String? _selectedClassId;

  DateTime? _startTime;
  DateTime? _endTime;
  DateTime? _examDate;
  DateTime? _submittedAt;

  String? _teacherId;
  String? _reviewNote;
  String _statusValue = 'upcoming';
  String _approvalStatus = 'draft';
  int? _questionCount;
  bool _isPc = true;
  bool _isSpecialExam = false;

  @override
  void initState() {
    super.initState();

    _loadTeacherProfile();

    if (widget.docId != null) {
      _loadExam(widget.docId!);
    } else if (widget.existing != null) {
      _setControllers(widget.existing!);
    }
  }

  // ============================================================
  // LOAD TEACHER PROFILE
  // ============================================================

  Future<void> _loadTeacherProfile() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    try {
      if (currentUser == null) {
        throw StateError('No signed-in teacher was found.');
      }

      final doc = await _db.collection('users').doc(currentUser.uid).get();
      if (!doc.exists) {
        throw StateError('The signed-in teacher profile could not be found.');
      }
      final classSnapshot = await _db
          .collection('classes')
          .where('adviserId', isEqualTo: currentUser.uid)
          .get();
      final programSnapshot = await _db.collection('programs').get();
      final classes = classSnapshot.docs.where((classDoc) {
        final status = (classDoc.data()['status'] ?? '').toString();
        return status != 'archived' && status != 'inactive';
      }).toList();
      final data = doc.data()!;
      final name =
          (data['name'] ??
                  data['fullName'] ??
                  data['displayName'] ??
                  currentUser.displayName ??
                  '')
              .toString()
              .trim();

      if (!mounted) return;

      setState(() {
        _teacherId = data['ID']?.toString();
        _classes = classes;
        _programAcronyms = _buildProgramAcronyms(programSnapshot.docs);
        _selectedClassId =
            _classForExam(
              _selectedClassId,
              _selectedProgram,
              _subjectController.text,
              _yearBlockController.text,
            ) ??
            (widget.docId == null && classes.length == 1
                ? classes.first.id
                : null);
        final selectedClass = _selectedClass;
        if (selectedClass != null) {
          _selectedProgram = (selectedClass['program'] ?? '').toString();
          if (_subjectController.text.trim().isEmpty) {
            _subjectController.text = (selectedClass['subject'] ?? '')
                .toString();
          }
          if (_yearBlockController.text.trim().isEmpty) {
            _yearBlockController.text = (selectedClass['yearBlock'] ?? '')
                .toString();
          }
        }
        if (_yearBlockController.text.trim().isEmpty) {
          _yearBlockController.text = (data['yearBlock'] ?? '').toString();
        }
        if (_creatorController.text.trim().isEmpty) {
          _creatorController.text = name;
        }
        _examDate ??= DateUtils.dateOnly(DateTime.now());
        if (!_isSpecialExam && _selectedClassId != null) {
          _refreshClassSchedule();
        }
        _isLoadingTeacherProfile = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoadingTeacherProfile = false);
      await AppDialog.alert(
        context,
        title: 'Unable to load teacher information',
        message: '$e',
        tone: AppTone.error,
      );
    }
  }

  // ============================================================
  // LOAD EXISTING EXAM
  // ============================================================

  Future<void> _loadExam(String id) async {
    try {
      final doc = await _db.collection('exams').doc(id).get();

      if (!mounted) return;

      if (doc.exists) {
        _setControllers(doc.data()!);
      }
    } catch (e) {
      if (!mounted) return;

      await AppDialog.alert(
        context,
        title: 'Unable to load exam',
        message: '$e',
        tone: AppTone.error,
      );
    }
  }

  // ============================================================
  // SET FORM DATA
  // ============================================================

  void _setControllers(Map<String, dynamic> data) {
    final statusValue = (data['status'] ?? 'upcoming').toString().toLowerCase();

    setState(() {
      final examProgram = (data['program'] ?? '').toString();
      _selectedProgram = examProgram.isEmpty ? null : examProgram;

      _subjectController.text = (data['subject'] ?? '').toString();
      final yearBlock = (data['yearBlock'] ?? '').toString();
      final creator = (data['creator'] ?? '').toString();
      if (yearBlock.trim().isNotEmpty) {
        _yearBlockController.text = yearBlock;
      }
      if (creator.trim().isNotEmpty) {
        _creatorController.text = creator;
      }
      _selectedClassId = (data['classId'] ?? '').toString().trim();
      _isSpecialExam = data['isSpecialExam'] is bool
          ? data['isSpecialExam'] as bool
          : widget.docId != null;
      _isPc = data['isPc'] is bool ? data['isPc'] as bool : true;
      _approvalStatus = (data['approvalStatus'] ?? 'draft').toString();
      _reviewNote = (data['reviewNote'] ?? '').toString().trim();
      _questionCount = int.tryParse(data['questionCount']?.toString() ?? '');

      _statusValue =
          ['finished', 'finish', 'completed', 'complete'].contains(statusValue)
          ? 'finished'
          : ['ongoing', 'on-going', 'on going'].contains(statusValue)
          ? 'ongoing'
          : 'upcoming';

      final start = data['startTime'];
      final end = data['endTime'];

      if (start is Timestamp) {
        _startTime = start.toDate();
        _examDate = DateUtils.dateOnly(_startTime!);
      }

      if (end is Timestamp) {
        _endTime = end.toDate();
      }
      _examDate ??= DateUtils.dateOnly(DateTime.now());

      final submittedAt = data['submittedAt'];
      _submittedAt = submittedAt is Timestamp ? submittedAt.toDate() : null;
    });
  }

  String? _classForExam(
    String? classId,
    String? program,
    String subject,
    String yearBlock,
  ) {
    if (classId != null && _classes.any((classDoc) => classDoc.id == classId)) {
      return classId;
    }
    for (final classDoc in _classes) {
      final data = classDoc.data();
      if ((data['program'] ?? '').toString() == (program ?? '') &&
          (data['subject'] ?? '').toString() == subject &&
          (data['yearBlock'] ?? '').toString() == yearBlock) {
        return classDoc.id;
      }
    }
    return null;
  }

  Map<String, dynamic>? get _selectedClass {
    for (final classDoc in _classes) {
      if (classDoc.id == _selectedClassId) return classDoc.data();
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

  int? _classStartMinutes(Map<String, dynamic> classData) {
    final value = classData['startMinutes'];
    if (value is num) return value.toInt();
    final label = (classData['startLabel'] ?? '').toString().trim();
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(label);
    if (match == null) return null;

    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final meridiem = match.group(3)!.toUpperCase();
    if (hour < 1 || hour > 12 || minute > 59) return null;
    if (meridiem == 'AM') {
      if (hour == 12) hour = 0;
    } else if (hour != 12) {
      hour += 12;
    }
    return hour * 60 + minute;
  }

  void _refreshClassSchedule() {
    final classData = _selectedClass;
    final startMinutes = classData == null
        ? null
        : _classStartMinutes(classData);
    final duration = classData?['durationMin'];
    if (classData == null ||
        startMinutes == null ||
        duration is! num ||
        duration <= 0 ||
        _examDate == null) {
      _startTime = null;
      _endTime = null;
      return;
    }

    final date = DateUtils.dateOnly(_examDate!);
    _startTime = DateTime(
      date.year,
      date.month,
      date.day,
      startMinutes ~/ 60,
      startMinutes % 60,
    );
    _endTime = _startTime!.add(Duration(minutes: duration.toInt()));
  }

  String _classScheduleLabel(Map<String, dynamic>? classData) {
    if (classData == null) return 'Choose a class to use its scheduled time.';
    final startMinutes = _classStartMinutes(classData);
    final duration = classData['durationMin'];
    if (startMinutes == null || duration is! num || duration <= 0) {
      return 'This class has no valid scheduled time. Set a special exam time.';
    }

    final date = _examDate ?? DateTime.now();
    final start = DateTime(
      date.year,
      date.month,
      date.day,
      startMinutes ~/ 60,
      startMinutes % 60,
    );
    final end = start.add(Duration(minutes: duration.toInt()));
    return '${DateFormat('h:mm a').format(start)} – '
        '${DateFormat('h:mm a').format(end)}'
        ' · ${duration.toInt()} min';
  }

  Future<void> _pickExamDate() async {
    final current = _examDate ?? DateTime.now();
    final date = await AppDialog.custom<DateTime>(
      context,
      builder: (dialogContext) => _pickerBuilder(
        dialogContext,
        DatePickerDialog(
          initialDate: current,
          firstDate: DateTime(2024),
          lastDate: DateTime(2100),
        ),
      ),
    );
    if (!mounted || date == null) return;
    setState(() {
      _examDate = DateUtils.dateOnly(date);
      if (!_isSpecialExam) _refreshClassSchedule();
    });
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _subjectController.dispose();
    _yearBlockController.dispose();
    _creatorController.dispose();

    super.dispose();
  }

  // ============================================================
  // DATE / TIME PICKER
  // ============================================================

  Future<void> _pickDateTime(bool isStart) async {
    final current = isStart ? _startTime : _endTime;

    final date = await AppDialog.custom<DateTime>(
      context,
      builder: (dialogContext) => _pickerBuilder(
        dialogContext,
        DatePickerDialog(
          initialDate: current ?? DateTime.now(),
          firstDate: DateTime(2024),
          lastDate: DateTime(2100),
        ),
      ),
    );

    if (!mounted || date == null) return;

    final time = await AppDialog.custom<TimeOfDay>(
      context,
      builder: (dialogContext) => _pickerBuilder(
        dialogContext,
        TimePickerDialog(
          initialTime: TimeOfDay.fromDateTime(current ?? DateTime.now()),
        ),
      ),
    );

    if (!mounted || time == null) return;

    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      if (isStart) {
        _startTime = selected;
      } else {
        _endTime = selected;
      }
    });
  }

  // ============================================================
  // DATE / TIME PICKER THEME
  // ============================================================

  Widget _pickerBuilder(BuildContext context, Widget? child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.dark(
          primary: AppTheme.accent,
          onPrimary: Colors.white,
          surface: AppTheme.header,
          onSurface: AppTheme.text,
        ),
      ),
      child: child!,
    );
  }

  // ============================================================
  // SAVE EXAM
  // ============================================================

  Future<void> _saveExam() async {
    if (_isLoadingTeacherProfile) {
      await AppDialog.alert(
        context,
        title: 'Teacher profile is loading',
        message: 'Please wait until your teacher profile has finished loading.',
        tone: AppTone.warning,
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedClassId == null || _selectedClass == null) {
      await AppDialog.alert(
        context,
        title: 'Class required',
        message:
            'Choose one of your assigned classes so the exam is linked to the correct class ID and schedule.',
        tone: AppTone.warning,
      );
      return;
    }
    final program = (_selectedClass!['program'] ?? '').toString().trim();
    if (program.isEmpty) {
      await AppDialog.alert(
        context,
        title: 'Class program is missing',
        message:
            'Ask an administrator to complete the program details for this class.',
        tone: AppTone.error,
      );
      return;
    }

    if (!_isSpecialExam) _refreshClassSchedule();
    final startTime = _startTime;
    final endTime = _endTime;
    if (startTime == null || endTime == null) {
      await AppDialog.alert(
        context,
        title: 'Exam time required',
        message: _isSpecialExam
            ? 'Please select start and end time for this special exam.'
            : 'This class has no valid scheduled time. Turn on the special exam option to set an exam time.',
        tone: AppTone.warning,
      );

      return;
    }

    if (!endTime.isAfter(startTime)) {
      await AppDialog.alert(
        context,
        title: 'Invalid exam time',
        message: 'End time must be after start time',
        tone: AppTone.warning,
      );

      return;
    }

    if (_teacherId == null || _teacherId!.trim().isEmpty) {
      if (!mounted) return;

      await AppDialog.alert(
        context,
        title: 'Teacher ID required',
        message: 'Teacher ID is required to save this exam.',
        tone: AppTone.warning,
      );

      return;
    }

    setState(() {
      _isSaving = true;
    });

    final data = {
      'program': program,
      'classId': _selectedClassId!,
      'subject': _subjectController.text.trim(),
      'yearBlock': _yearBlockController.text.trim(),
      'creator': _creatorController.text.trim(),
      'status': _statusValue,
      'isPc': _isPc,
      'isSpecialExam': _isSpecialExam,
      'teacherId': _teacherId!.trim(),
      'startTime': Timestamp.fromDate(startTime),
      'endTime': Timestamp.fromDate(endTime),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      String examId;

      // ========================================================
      // CREATE NEW EXAM
      // ========================================================

      if (widget.docId == null) {
        final docRef = await _db.collection('exams').add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });

        examId = docRef.id;

        // Create / update examResults
        await _db.collection('examResults').doc(examId).set({
          'teacherId': _teacherId!.trim(),
          'examId': examId,
          'classId': _selectedClassId!,
          'yearBlock': _yearBlockController.text.trim(),
          'program': program,
        }, SetOptions(merge: true));

        if (!mounted) return;

        await AppDialog.alert(
          context,
          title: 'Exam created',
          message: 'Exam saved successfully!',
          tone: AppTone.success,
        );

        if (!mounted) return;
        context.go('/teacher-exams');
      }
      // ========================================================
      // UPDATE EXISTING EXAM
      // ========================================================
      else {
        examId = widget.docId!;

        await _db.collection('exams').doc(examId).update(data);

        // Update examResults
        await _db.collection('examResults').doc(examId).set({
          'teacherId': _teacherId!.trim(),
          'examId': examId,
          'classId': _selectedClassId!,
          'yearBlock': _yearBlockController.text.trim(),
          'program': program,
        }, SetOptions(merge: true));

        if (!mounted) return;

        await AppDialog.alert(
          context,
          title: 'Exam updated',
          message: 'Exam updated successfully!',
          tone: AppTone.success,
        );
      }
    } catch (e) {
      if (!mounted) return;

      await AppDialog.alert(
        context,
        title: 'Unable to save exam',
        message: '$e',
        tone: AppTone.error,
      );
    } finally {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });
    }
  }

  // ============================================================
  // FORMAT DATE TIME
  // ============================================================

  String _formatDateTime(DateTime? dt) {
    if (dt == null) {
      return 'Select date/time';
    }

    return DateFormat('MMM d, yyyy – hh:mm a').format(dt);
  }

  Widget _scheduleSection() {
    final classData = _selectedClass;
    final date = _examDate ?? DateTime.now();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTheme.sectionHeader(Icons.schedule, 'Exam schedule'),
          if (!_isSpecialExam) ...[
            const Text(
              'The exam will use the selected class time automatically.',
              style: TextStyle(
                color: AppTheme.mutedText,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickExamDate,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: AppTheme.inputDecoration(
                  'Exam date',
                  icon: Icons.event_outlined,
                ),
                child: Text(
                  DateFormat('MMM d, yyyy').format(date),
                  style: const TextStyle(color: AppTheme.text),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
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
                    color: AppTheme.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'CLASS TIME',
                          style: TextStyle(
                            color: AppTheme.mutedText,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _classScheduleLabel(classData),
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
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => setState(() => _isSpecialExam = true),
                icon: const Icon(Icons.tune_outlined, size: 17),
                label: const Text('Change time for a special exam'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.text,
                  side: const BorderSide(color: AppTheme.line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Special exam time',
                    style: TextStyle(
                      color: AppTheme.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _isSpecialExam = false;
                      _refreshClassSchedule();
                    });
                  },
                  icon: const Icon(Icons.restart_alt, size: 17),
                  label: const Text('Use class time'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _dateTimePicker(
              'Start Time',
              _startTime,
              () => _pickDateTime(true),
            ),
            const SizedBox(height: 14),
            _dateTimePicker('End Time', _endTime, () => _pickDateTime(false)),
          ],
        ],
      ),
    );
  }

  Widget _reviewDetailsCard() {
    final statusColor = switch (_approvalStatus) {
      'pending' => const Color(0xFFB7791F),
      'approved' => AppTheme.success,
      'changes_requested' => AppTheme.error,
      _ => AppTheme.mutedText,
    };
    final statusLabel = switch (_approvalStatus) {
      'pending' => 'Pending review',
      'approved' => 'Approved',
      'changes_requested' => 'Changes requested',
      _ => 'Draft',
    };
    final submitted = _submittedAt == null
        ? 'Not submitted yet'
        : DateFormat('MMM d, yyyy – hh:mm a').format(_submittedAt!);

    Widget detail(String label, String value, IconData icon) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: AppTheme.mutedText),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      color: AppTheme.mutedText,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppTheme.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTheme.sectionHeader(Icons.fact_check_outlined, 'Approval details'),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
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
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [detail('Submitted', submitted, Icons.schedule_outlined)],
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

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.docId != null;

    return Scaffold(
      backgroundColor: AppTheme.bg,

      // ========================================================
      // APP BAR
      // ========================================================
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 80,
        titleSpacing: 16,
        backgroundColor: AppTheme.header,
        foregroundColor: AppTheme.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,

        title: Row(
          children: [
            AppTheme.appBarIcon(
              isEditing ? Icons.edit_note : Icons.add_circle_outline,
            ),

            const SizedBox(width: 12),

            Text(
              isEditing ? 'Edit Exam' : 'Add Exam',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),

      // ========================================================
      // BODY
      // ========================================================
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),

          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),

            child: Form(
              key: _formKey,

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,

                children: [
                  // ==================================================
                  // EXAM DETAILS CARD
                  // ==================================================
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: AppTheme.cardDecoration(),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        AppTheme.sectionHeader(
                          Icons.info_outline,
                          'Exam Details',
                        ),

                        _classDropdown(),

                        _field(
                          _subjectController,
                          'Subject',
                          Icons.menu_book_outlined,
                        ),

                        _readOnlyField(
                          _yearBlockController,
                          'Year/Block',
                          Icons.groups_outlined,
                          emptyMessage:
                              'Year/block is missing from your profile.',
                        ),

                        _readOnlyField(
                          _creatorController,
                          'Creator (Teacher)',
                          Icons.person_outline,
                          emptyMessage: 'Name is missing from your profile.',
                        ),

                        // ==========================================
                        // STATUS
                        // ==========================================
                        DropdownButtonFormField<String>(
                          key: ValueKey(_statusValue),

                          initialValue: _statusValue,

                          dropdownColor: AppTheme.header,

                          iconEnabledColor: AppTheme.mutedText,

                          style: TextStyle(color: AppTheme.text),

                          decoration: AppTheme.inputDecoration(
                            'Status',
                            icon: Icons.flag_outlined,
                          ),

                          items: const [
                            DropdownMenuItem(
                              value: 'upcoming',
                              child: Text('Upcoming'),
                            ),
                            DropdownMenuItem(
                              value: 'ongoing',
                              child: Text('On-going'),
                            ),

                            DropdownMenuItem(
                              value: 'finished',
                              child: Text('Finished'),
                            ),
                          ],

                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _statusValue = value;
                              });
                            }
                          },
                        ),

                        const SizedBox(height: 14),

                        Material(
                          color: Colors.black.withOpacity(0.22),
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Colors.white.withOpacity(0.06),
                            ),
                          ),
                          child: SwitchListTile(
                            value: _isPc,
                            activeColor: AppTheme.accent,
                            onChanged: (value) {
                              setState(() {
                                _isPc = value;
                              });
                            },
                            secondary: Icon(
                              _isPc
                                  ? Icons.desktop_windows_outlined
                                  : Icons.smartphone_outlined,
                              color: AppTheme.mutedText,
                            ),
                            title: Text(
                              _isPc
                                  ? 'PC (screen recording on)'
                                  : 'Mobile (no screen recording)',
                              style: TextStyle(
                                color: AppTheme.text,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (isEditing) ...[
                    _reviewDetailsCard(),
                    const SizedBox(height: 16),
                  ],

                  // ==================================================
                  // SCHEDULE CARD
                  // ==================================================
                  _scheduleSection(),

                  const SizedBox(height: 20),

                  // ==================================================
                  // SAVE / CANCEL
                  // ==================================================
                  Row(
                    children: [
                      // CANCEL
                      Expanded(
                        child: TextButton(
                          style: AppTheme.ghostButton(),

                          onPressed: _isSaving
                              ? null
                              : () {
                                  if (!mounted) return;

                                  context.go('/teacher-exams');
                                },

                          child: const Text('Cancel'),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // SAVE
                      Expanded(
                        flex: 2,

                        child: ElevatedButton.icon(
                          style: AppTheme.primaryButton(),

                          onPressed: _isSaving ? null : _saveExam,

                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,

                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined, size: 18),

                          label: Text(_isSaving ? 'Saving...' : 'Save'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ==================================================
                  // EDIT QUESTIONS
                  // ==================================================
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.text,

                      side: BorderSide(color: AppTheme.accent.withOpacity(0.6)),

                      padding: const EdgeInsets.symmetric(vertical: 14),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),

                    icon: const Icon(Icons.edit_note),

                    label: const Text('Edit Exam Questions'),

                    onPressed: () async {
                      if (widget.docId != null) {
                        context.go('/edit-question/${widget.docId}');
                      } else {
                        if (!mounted) return;

                        await AppDialog.alert(
                          context,
                          title: 'Save the exam first',
                          message:
                              'Create the exam before adding or editing questions.',
                          tone: AppTone.warning,
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TEXT FIELD
  // ============================================================

  Widget _classDropdown() {
    final selectedClassId =
        _classes.any((classDoc) => classDoc.id == _selectedClassId)
        ? _selectedClassId
        : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        key: ValueKey(selectedClassId),
        initialValue: selectedClassId,
        isExpanded: true,
        dropdownColor: AppTheme.header,
        iconEnabledColor: AppTheme.mutedText,
        style: TextStyle(color: AppTheme.text),
        decoration: AppTheme.inputDecoration(
          'Assigned class',
          icon: Icons.school_outlined,
          helper: _isLoadingTeacherProfile
              ? 'Loading your assigned classes...'
              : _classes.isEmpty
              ? 'Ask an administrator to assign you to a class first.'
              : null,
        ),
        items: _classes
            .map(
              (classDoc) => DropdownMenuItem(
                value: classDoc.id,
                child: Text(
                  [
                        _programLabel(classDoc.data()['program']),
                        classDoc.data()['yearBlock'],
                        classDoc.data()['subject'],
                      ]
                      .where(
                        (value) => value != null && value.toString().isNotEmpty,
                      )
                      .join(' · '),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            )
            .toList(),
        onChanged: _isLoadingTeacherProfile || _classes.isEmpty
            ? null
            : (classId) {
                if (classId == null) return;
                final classDoc = _classes.firstWhere(
                  (item) => item.id == classId,
                );
                setState(() {
                  _selectedClassId = classId;
                  _selectedProgram = (classDoc.data()['program'] ?? '')
                      .toString();
                  _yearBlockController.text =
                      (classDoc.data()['yearBlock'] ?? '').toString();
                  _subjectController.text = (classDoc.data()['subject'] ?? '')
                      .toString();
                  if (!_isSpecialExam) _refreshClassSchedule();
                });
              },
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return _classes.isEmpty
                ? 'You need an assigned class before creating an exam.'
                : 'Choose a class';
          }
          return null;
        },
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),

      child: TextFormField(
        controller: controller,

        cursorColor: AppTheme.accent,

        style: TextStyle(color: AppTheme.text),

        decoration: AppTheme.inputDecoration(label, icon: icon),

        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return 'Enter $label';
          }

          return null;
        },
      ),
    );
  }

  Widget _readOnlyField(
    TextEditingController controller,
    String label,
    IconData icon, {
    String? emptyMessage,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        style: TextStyle(color: AppTheme.text),
        decoration: AppTheme.inputDecoration(label, icon: icon),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return emptyMessage ?? 'Enter $label';
          }
          return null;
        },
      ),
    );
  }

  // ============================================================
  // DATE TIME FIELD
  // ============================================================

  Widget _dateTimePicker(String label, DateTime? dt, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,

      borderRadius: BorderRadius.circular(12),

      child: InputDecorator(
        decoration: AppTheme.inputDecoration(label, icon: Icons.event_outlined),

        child: Text(
          _formatDateTime(dt),

          style: TextStyle(
            color: dt == null ? AppTheme.mutedText : AppTheme.text,
          ),
        ),
      ),
    );
  }
}
