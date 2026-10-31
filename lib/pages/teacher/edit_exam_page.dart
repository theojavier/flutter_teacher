import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../helpers/app_theme.dart';
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
  List<String> _programs = [];
  String? _selectedProgram;

  DateTime? _startTime;
  DateTime? _endTime;

  String? _teacherId;
  String _statusValue = 'upcoming';
  bool _isPc = true;

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
      final data = doc.data()!;
      final rawPrograms = data['programs'];
      final programs = rawPrograms is List
          ? rawPrograms
                .map((program) => program.toString().trim())
                .where((program) => program.isNotEmpty)
                .toSet()
                .toList()
          : <String>[];
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
        _programs = programs;
        _selectedProgram = programs.contains(_selectedProgram)
            ? _selectedProgram
            : (programs.isEmpty ? null : programs.first);
        _yearBlockController.text = (data['yearBlock'] ?? '').toString();
        _creatorController.text = name;
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
      _isPc = data['isPc'] is bool ? data['isPc'] as bool : true;

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
      }

      if (end is Timestamp) {
        _endTime = end.toDate();
      }
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

    if (_startTime == null || _endTime == null) {
      await AppDialog.alert(
        context,
        title: 'Exam time required',
        message: 'Please select start and end time',
        tone: AppTone.warning,
      );

      return;
    }

    if (!_endTime!.isAfter(_startTime!)) {
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
      'program': _selectedProgram!.trim(),
      'subject': _subjectController.text.trim(),
      'yearBlock': _yearBlockController.text.trim(),
      'creator': _creatorController.text.trim(),
      'status': _statusValue,
      'isPc': _isPc,
      'teacherId': _teacherId!.trim(),
      'startTime': Timestamp.fromDate(_startTime!),
      'endTime': Timestamp.fromDate(_endTime!),
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
          'yearBlock': _yearBlockController.text.trim(),
          'program': _selectedProgram!.trim(),
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
          'yearBlock': _yearBlockController.text.trim(),
          'program': _selectedProgram!.trim(),
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
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
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

                        _programDropdown(),

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
                          color: Colors.black.withValues(alpha: 0.22),
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                          ),
                          child: SwitchListTile(
                            value: _isPc,
                            activeThumbColor: AppTheme.accent,
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

                  // ==================================================
                  // SCHEDULE CARD
                  // ==================================================
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: AppTheme.cardDecoration(),

                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        AppTheme.sectionHeader(Icons.schedule, 'Schedule'),

                        _dateTimePicker(
                          'Start Time',
                          _startTime,
                          () => _pickDateTime(true),
                        ),

                        const SizedBox(height: 14),

                        _dateTimePicker(
                          'End Time',
                          _endTime,
                          () => _pickDateTime(false),
                        ),
                      ],
                    ),
                  ),

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

                      side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.6)),

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

  Widget _programDropdown() {
    final selectedProgram = _programs.contains(_selectedProgram)
        ? _selectedProgram
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        key: ValueKey(selectedProgram),
        initialValue: selectedProgram,
        isExpanded: true,
        dropdownColor: AppTheme.header,
        iconEnabledColor: AppTheme.mutedText,
        style: TextStyle(color: AppTheme.text),
        decoration: AppTheme.inputDecoration(
          'Program',
          icon: Icons.school_outlined,
          helper: _isLoadingTeacherProfile
              ? 'Loading programs from your teacher profile...'
              : _programs.isEmpty
              ? 'No programs are assigned to your teacher profile.'
              : null,
        ),
        items: _programs
            .map(
              (program) => DropdownMenuItem(
                value: program,
                child: Text(program, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: _isLoadingTeacherProfile || _programs.isEmpty
            ? null
            : (program) => setState(() => _selectedProgram = program),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return _programs.isEmpty
                ? 'Add a program to your teacher profile first.'
                : 'Choose a program';
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
