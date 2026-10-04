
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../helpers/AppTheme.dart';

class EditExamPage extends StatefulWidget {
  final String? docId;
  final Map<String, dynamic>? existing;

  const EditExamPage({
    super.key,
    this.docId,
    this.existing,
  });

  @override
  State<EditExamPage> createState() => _EditExamPageState();
}

class _EditExamPageState extends State<EditExamPage> {
  final _formKey = GlobalKey<FormState>();
  final _db = FirebaseFirestore.instance;

  bool _isSaving = false;

  final _programController = TextEditingController();
  final _subjectController = TextEditingController();
  final _yearBlockController = TextEditingController();
  final _creatorController = TextEditingController();

  DateTime? _startTime;
  DateTime? _endTime;

  String? _teacherId;
  String _statusValue = 'ongoing';

  @override
  void initState() {
    super.initState();

    if (widget.docId != null) {
      _loadExam(widget.docId!);
    } else if (widget.existing != null) {
      _setControllers(widget.existing!);
    } else {
      _loadTeacherId();
    }
  }

  // ============================================================
  // LOAD TEACHER ID
  // ============================================================

  Future<void> _loadTeacherId() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) return;

    try {
      final doc = await _db
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!mounted) return;

      if (doc.exists) {
        setState(() {
          _teacherId = doc.data()?['ID']?.toString();
        });
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load teacher information: $e'),
        ),
      );
    }
  }

  // ============================================================
  // LOAD EXISTING EXAM
  // ============================================================

  Future<void> _loadExam(String id) async {
    try {
      final doc = await _db
          .collection('exams')
          .doc(id)
          .get();

      if (!mounted) return;

      if (doc.exists) {
        _setControllers(doc.data()!);
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to load exam: $e'),
        ),
      );
    }
  }

  // ============================================================
  // SET FORM DATA
  // ============================================================

  void _setControllers(Map<String, dynamic> data) {
    final statusValue =
        (data['status'] ?? 'ongoing').toString().toLowerCase();

    setState(() {
      _programController.text =
          (data['program'] ?? '').toString();

      _subjectController.text =
          (data['subject'] ?? '').toString();

      _yearBlockController.text =
          (data['yearBlock'] ?? '').toString();

      _creatorController.text =
          (data['creator'] ?? '').toString();

      _teacherId =
          data['teacherId']?.toString();

      _statusValue =
          statusValue == 'finished' ||
                  statusValue == 'finish' ||
                  statusValue == 'completed' ||
                  statusValue == 'complete'
              ? 'finished'
              : 'ongoing';

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
    _programController.dispose();
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

    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
      builder: _pickerBuilder,
    );

    if (!mounted || date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        current ?? DateTime.now(),
      ),
      builder: _pickerBuilder,
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

  Widget _pickerBuilder(
    BuildContext context,
    Widget? child,
  ) {
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select start and end time',
          ),
        ),
      );

      return;
    }

    if (!_endTime!.isAfter(_startTime!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'End time must be after start time',
          ),
        ),
      );

      return;
    }

    // If teacher ID was loaded from an existing exam,
    // use that. Otherwise load the current teacher ID.
    if (_teacherId == null || _teacherId!.trim().isEmpty) {
      await _loadTeacherId();
    }

    if (_teacherId == null || _teacherId!.trim().isEmpty) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Teacher ID is required',
          ),
        ),
      );

      return;
    }

    setState(() {
      _isSaving = true;
    });

    final data = {
      'program': _programController.text.trim(),
      'subject': _subjectController.text.trim(),
      'yearBlock': _yearBlockController.text.trim(),
      'creator': _creatorController.text.trim(),
      'status': _statusValue,
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
        await _db
            .collection('examResults')
            .doc(examId)
            .set(
          {
            'teacherId': _teacherId!.trim(),
            'examId': examId,
            'yearBlock': _yearBlockController.text.trim(),
            'program': _programController.text.trim(),
          },
          SetOptions(merge: true),
        );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Exam saved successfully!',
            ),
          ),
        );

        context.go('/Exams');
      }

      // ========================================================
      // UPDATE EXISTING EXAM
      // ========================================================

      else {
        examId = widget.docId!;

        await _db
            .collection('exams')
            .doc(examId)
            .update(data);

        // Update examResults
        await _db
            .collection('examResults')
            .doc(examId)
            .set(
          {
            'teacherId': _teacherId!.trim(),
            'examId': examId,
            'yearBlock': _yearBlockController.text.trim(),
            'program': _programController.text.trim(),
          },
          SetOptions(merge: true),
        );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Exam updated successfully!',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error: $e',
          ),
        ),
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

    return DateFormat(
      'MMM d, yyyy – hh:mm a',
    ).format(dt);
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
              isEditing
                  ? Icons.edit_note
                  : Icons.add_circle_outline,
            ),

            const SizedBox(width: 12),

            Text(
              isEditing ? 'Edit Exam' : 'Add Exam',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),

      // ========================================================
      // BODY
      // ========================================================

      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 640,
          ),

          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),

            child: Form(
              key: _formKey,

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,

                children: [
                  // ==================================================
                  // EXAM DETAILS CARD
                  // ==================================================

                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: AppTheme.cardDecoration(),

                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: [
                        AppTheme.sectionHeader(
                          Icons.info_outline,
                          'Exam Details',
                        ),

                        _field(
                          _programController,
                          'Program',
                          Icons.school_outlined,
                        ),

                        _field(
                          _subjectController,
                          'Subject',
                          Icons.menu_book_outlined,
                        ),

                        _field(
                          _yearBlockController,
                          'Year/Block',
                          Icons.groups_outlined,
                        ),

                        _field(
                          _creatorController,
                          'Creator (Teacher)',
                          Icons.person_outline,
                        ),

                        // ==========================================
                        // STATUS
                        // ==========================================

                        DropdownButtonFormField<String>(
                          key: ValueKey(_statusValue),

                          initialValue: _statusValue,

                          dropdownColor: AppTheme.header,

                          iconEnabledColor:
                              AppTheme.mutedText,

                          style: TextStyle(
                            color: AppTheme.text,
                          ),

                          decoration:
                              AppTheme.inputDecoration(
                            'Status',
                            icon: Icons.flag_outlined,
                          ),

                          items: const [
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
                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: [
                        AppTheme.sectionHeader(
                          Icons.schedule,
                          'Schedule',
                        ),

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

                                  context.go('/Exams');
                                },

                          child: const Text(
                            'Cancel',
                          ),
                        ),
                      ),

                      const SizedBox(width: 12),

                      // SAVE
                      Expanded(
                        flex: 2,

                        child: ElevatedButton.icon(
                          style: AppTheme.primaryButton(),

                          onPressed:
                              _isSaving ? null : _saveExam,

                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,

                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.save_outlined,
                                  size: 18,
                                ),

                          label: Text(
                            _isSaving
                                ? 'Saving...'
                                : 'Save',
                          ),
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

                      side: BorderSide(
                        color: AppTheme.accent.withOpacity(
                          0.6,
                        ),
                      ),

                      padding:
                          const EdgeInsets.symmetric(
                        vertical: 14,
                      ),

                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(12),
                      ),
                    ),

                    icon: const Icon(
                      Icons.edit_note,
                    ),

                    label: const Text(
                      'Edit Exam Questions',
                    ),

                    onPressed: () {
                      if (widget.docId != null) {
                        context.go(
                          '/edit-question/${widget.docId}',
                        );
                      } else {
                        if (!mounted) return;

                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Must Save First!',
                            ),
                          ),
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

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 14,
      ),

      child: TextFormField(
        controller: controller,

        cursorColor: AppTheme.accent,

        style: TextStyle(
          color: AppTheme.text,
        ),

        decoration:
            AppTheme.inputDecoration(
          label,
          icon: icon,
        ),

        validator: (value) {
          if (value == null ||
              value.trim().isEmpty) {
            return 'Enter $label';
          }

          return null;
        },
      ),
    );
  }

  // ============================================================
  // DATE TIME FIELD
  // ============================================================

  Widget _dateTimePicker(
    String label,
    DateTime? dt,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,

      borderRadius:
          BorderRadius.circular(12),

      child: InputDecorator(
        decoration:
            AppTheme.inputDecoration(
          label,
          icon: Icons.event_outlined,
        ),

        child: Text(
          _formatDateTime(dt),

          style: TextStyle(
            color: dt == null
                ? AppTheme.mutedText
                : AppTheme.text,
          ),
        ),
      ),
    );
  }
}
