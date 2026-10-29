import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../helpers/AppTheme.dart';

class ReportableStudent {
  const ReportableStudent({
    required this.id,
    required this.name,
    required this.email,
    required this.strikes,
    required this.status,
  });

  final String id;
  final String name;
  final String email;
  final int strikes;
  final String status;

  String get label => name.isEmpty ? id : name;
}

class ReportableExam {
  const ReportableExam({
    required this.id,
    required this.title,
    required this.classId,
    required this.dateLabel,
    required this.students,
  });

  final String id;
  final String title;
  final String classId;
  final String dateLabel;
  final List<ReportableStudent> students;

  String get label => [
    title,
    if (classId.isNotEmpty) classId,
    if (dateLabel.isNotEmpty) dateLabel,
  ].join(' · ');
}

/// Returns the number of reports created, or null if cancelled.
Future<int?> showTeacherReportSheet(
  BuildContext context, {
  required List<ReportableExam> exams,
}) {
  final compact = MediaQuery.sizeOf(context).width < 680;
  if (compact) {
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      enableDrag: false, // drag-dismiss would bypass the discard prompt
      backgroundColor: AppTheme.header,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ReportForm(exams: exams, compact: true),
    );
  }
  return showDialog<int>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => Dialog(
      backgroundColor: AppTheme.header,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 780),
        child: _ReportForm(exams: exams, compact: false),
      ),
    ),
  );
}

enum _Kind { student, problem }

const _studentCategories = {
  'suspected_cheating': 'Suspected cheating',
  'suspicious_behavior': 'Suspicious behavior',
  'identity_concern': 'Identity concern',
  'misconduct': 'Misconduct or disruption',
  'technical_issue': 'Technical issue affecting the student',
  'other': 'Other',
};

const _problemCategories = {
  'system_bug': 'System bug',
  'monitoring_issue': 'Camera or monitoring issue',
  'content_error': 'Question or content error',
  'connectivity': 'Network or outage',
  'other': 'Other',
};

const _severities = {'low': 'Low', 'medium': 'Medium', 'high': 'High'};
const _maxStudents = 25;
const _noExam = '';

class _ReportException implements Exception {
  const _ReportException(this.message);
  final String message;
}

Future<Map<String, Map<String, String>>> _resolveProfiles(
  FirebaseFirestore db,
  List<ReportableStudent> students,
) async {
  final profiles = <String, Map<String, String>>{};
  await Future.wait(
    students.where((s) => s.name.isEmpty || s.email.isEmpty).map((s) async {
      final data = (await db.collection('users').doc(s.id).get()).data();
      profiles[s.id] = {
        'name': (data?['name'] ?? '').toString().trim(),
        'email': (data?['email'] ?? '').toString().trim(),
      };
    }),
  );
  return profiles;
}

class _ReportForm extends StatefulWidget {
  const _ReportForm({required this.exams, required this.compact});
  final List<ReportableExam> exams;
  final bool compact;

  @override
  State<_ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<_ReportForm> {
  final _formKey = GlobalKey<FormState>();
  final _details = TextEditingController();
  final _search = TextEditingController();

  late _Kind _kind;
  String _examId = _noExam;
  String? _category;
  String _severity = 'medium';
  final Set<String> _selected = {};
  String _query = '';
  String? _studentError;
  String? _formError;
  bool _submitting = false;

  bool get _hasStudentExams => widget.exams.any((e) => e.students.isNotEmpty);
  bool get _dirty =>
      _details.text.trim().isNotEmpty ||
      _category != null ||
      _examId != _noExam ||
      _selected.isNotEmpty;

  ReportableExam? get _exam =>
      widget.exams.where((e) => e.id == _examId).firstOrNull;

  List<ReportableExam> get _examOptions => _kind == _Kind.student
      ? widget.exams.where((e) => e.students.isNotEmpty).toList()
      : widget.exams;

  @override
  void initState() {
    super.initState();
    _kind = _hasStudentExams ? _Kind.student : _Kind.problem;
    _details.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _details.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Discard this report?'),
        content: const Text('What you have written has not been sent.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final pad = widget.compact ? 18.0 : 24.0;
    final categories = _kind == _Kind.student
        ? _studentCategories
        : _problemCategories;
    final exam = _exam;

    final body = PopScope(
      canPop: !_dirty && !_submitting,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _submitting) return;
        final navigator = Navigator.of(context);
        final discard = await _confirmDiscard();
        if (!mounted || !discard) return;
        navigator.pop();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 18, 8, 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.headerLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.line),
                  ),
                  child: const Icon(
                    Icons.flag_outlined,
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Report to admin',
                        style: AppTheme.display(
                          18,
                          ls: -0.045,
                          color: AppTheme.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'Flag students or raise a problem. An admin reviews every report.',
                        style: TextStyle(
                          color: AppTheme.mutedText,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.line),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(pad),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SegmentedButton<_Kind>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(
                          value: _Kind.student,
                          enabled: _hasStudentExams,
                          icon: const Icon(
                            Icons.person_search_outlined,
                            size: 17,
                          ),
                          label: const Text('Student'),
                        ),
                        const ButtonSegment(
                          value: _Kind.problem,
                          icon: Icon(Icons.report_problem_outlined, size: 17),
                          label: Text('Problem'),
                        ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: _submitting
                          ? null
                          : (value) => setState(() {
                              _kind = value.first;
                              _category = null;
                              _studentError = null;
                              _selected.clear();
                              if (_kind == _Kind.student &&
                                  (exam == null || exam.students.isEmpty)) {
                                _examId = _noExam;
                              }
                            }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _kind == _Kind.student
                          ? 'Flag one or more students from an exam. Each student becomes a separate case the admin can decide on individually.'
                          : 'Report a system, monitoring, or exam problem that is not about a specific student.',
                      style: const TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _label(_kind == _Kind.student ? 'Exam' : 'Exam (optional)'),
                    DropdownButtonFormField<String>(
                      initialValue: _examOptions.any((e) => e.id == _examId)
                          ? _examId
                          : (_kind == _Kind.problem ? _noExam : null),
                      isExpanded: true,
                      decoration: _decoration(
                        hint: _kind == _Kind.student
                            ? 'Choose an exam'
                            : 'Not about a specific exam',
                      ),
                      items: [
                        if (_kind == _Kind.problem)
                          const DropdownMenuItem(
                            value: _noExam,
                            child: Text('General (no specific exam)'),
                          ),
                        for (final e in _examOptions)
                          DropdownMenuItem(
                            value: e.id,
                            child: Text(
                              e.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() {
                              _examId = value ?? _noExam;
                              _selected.clear();
                              _studentError = null;
                            }),
                      validator: (value) =>
                          _kind == _Kind.student &&
                              (value == null || value.isEmpty)
                          ? 'Choose an exam'
                          : null,
                    ),
                    if (_kind == _Kind.student) ...[
                      const SizedBox(height: 18),
                      _studentPicker(exam),
                    ],
                    const SizedBox(height: 18),
                    _label('Category'),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_kind),
                      initialValue: _category,
                      isExpanded: true,
                      decoration: _decoration(hint: 'Choose a category'),
                      items: [
                        for (final entry in categories.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _category = value),
                      validator: (value) =>
                          value == null ? 'Choose a category' : null,
                    ),
                    const SizedBox(height: 18),
                    _label('Priority'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final entry in _severities.entries)
                          ChoiceChip(
                            label: Text(entry.value),
                            selected: _severity == entry.key,
                            onSelected: _submitting
                                ? null
                                : (_) => setState(() => _severity = entry.key),
                            selectedColor: AppTheme.headerLight,
                            side: BorderSide(
                              color: _severity == entry.key
                                  ? AppTheme.accent
                                  : AppTheme.line,
                            ),
                            labelStyle: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _severity == entry.key
                                  ? AppTheme.accent
                                  : AppTheme.text,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _label('Details'),
                    TextFormField(
                      controller: _details,
                      enabled: !_submitting,
                      minLines: 4,
                      maxLines: 8,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _decoration(
                        hint: _kind == _Kind.student
                            ? 'What did you observe? When did it happen?'
                            : 'Describe the problem and what you were doing when it happened.',
                      ),
                      validator: (value) => (value ?? '').trim().length < 10
                          ? 'Add at least 10 characters so the admin has context.'
                          : null,
                    ),
                    if (_kind == _Kind.student && _selected.length > 1)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'This message is attached to every selected student.',
                          style: TextStyle(
                            color: AppTheme.mutedText,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      'Automated signals alone do not prove a violation. Report what you observed.',
                      style: TextStyle(
                        color: AppTheme.mutedText,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: AppTheme.line),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 12, pad, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_formError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _formError!,
                      style: const TextStyle(
                        color: AppTheme.error,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, size: 16),
                      label: Text(
                        _submitting
                            ? 'Sending...'
                            : _kind == _Kind.student && _selected.length > 1
                            ? 'Send ${_selected.length} reports'
                            : 'Send report',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 46),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (!widget.compact) return body;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: body,
    );
  }

  // ───────────────────────── student picker ─────────────────────────

  Widget _studentPicker(ReportableExam? exam) {
    if (exam == null) {
      return _hint('Choose an exam to list the students who attempted it.');
    }
    final q = _query.trim().toLowerCase();
    final visible = exam.students
        .where(
          (s) =>
              q.isEmpty ||
              '${s.name} ${s.id} ${s.email}'.toLowerCase().contains(q),
        )
        .toList();
    final picked = exam.students
        .where((s) => _selected.contains(s.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _label(
                'Students (${_selected.length}/$_maxStudents)',
                pad: 0,
              ),
            ),
            TextButton(
              onPressed: _submitting
                  ? null
                  : () => setState(() {
                      for (final s in exam.students.where(
                        (s) => s.strikes > 0,
                      )) {
                        if (_selected.length < _maxStudents) {
                          _selected.add(s.id);
                        }
                      }
                      _studentError = null;
                    }),
              child: const Text('Select flagged'),
            ),
            TextButton(
              onPressed: _submitting || _selected.isEmpty
                  ? null
                  : () => setState(_selected.clear),
              child: const Text('Clear'),
            ),
          ],
        ),
        TextField(
          controller: _search,
          enabled: !_submitting,
          onChanged: (v) => setState(() => _query = v),
          decoration: _decoration(hint: 'Search name or ID').copyWith(
            prefixIcon: const Icon(Icons.search, size: 19),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            border: Border.all(
              color: _studentError != null ? AppTheme.error : AppTheme.line,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: visible.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: _hint('No students match your search.'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: visible.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppTheme.line),
                  itemBuilder: (context, i) {
                    final s = visible[i];
                    final on = _selected.contains(s.id);
                    return CheckboxListTile(
                      dense: true,
                      value: on,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppTheme.accent,
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() {
                              if (value == true) {
                                if (_selected.length >= _maxStudents) {
                                  _studentError =
                                      'You can report up to $_maxStudents students at once.';
                                  return;
                                }
                                _selected.add(s.id);
                              } else {
                                _selected.remove(s.id);
                              }
                              _studentError = null;
                            }),
                      title: Text(
                        s.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${s.id} · ${s.status.isEmpty ? 'no status' : s.status}'
                        '${s.strikes > 0 ? ' · ${s.strikes} flag${s.strikes == 1 ? '' : 's'}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: s.strikes > 0
                              ? AppTheme.error
                              : AppTheme.mutedText,
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_studentError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _studentError!,
              style: const TextStyle(color: AppTheme.error, fontSize: 12),
            ),
          ),
        if (picked.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in picked)
                InputChip(
                  label: Text(s.label, style: const TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  onDeleted: _submitting
                      ? null
                      : () => setState(() => _selected.remove(s.id)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 6),
        const Text(
          'Only students who attempted this exam are listed. For anyone else, use a Problem report and name them in the details.',
          style: TextStyle(
            color: AppTheme.mutedText,
            fontSize: 11,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  // ───────────────────────── helpers ─────────────────────────

  Widget _label(String text, {double pad = 6}) => Padding(
    padding: EdgeInsets.only(bottom: pad),
    child: Text(
      text,
      style: const TextStyle(
        color: AppTheme.text,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _hint(String text) => Text(
    text,
    style: const TextStyle(
      color: AppTheme.mutedText,
      fontSize: 12,
      height: 1.5,
    ),
  );

  InputDecoration _decoration({required String hint}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppTheme.mutedText, fontSize: 13),
    filled: true,
    fillColor: AppTheme.bg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppTheme.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppTheme.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppTheme.accent, width: 1.5),
    ),
  );

  // ───────────────────────── submit ─────────────────────────

  Future<void> _submit() async {
    if (_submitting) return; // blocks double taps
    FocusScope.of(context).unfocus();

    final formOk = _formKey.currentState?.validate() ?? false;
    String? studentError;
    if (_kind == _Kind.student && _selected.isEmpty) {
      studentError = 'Select at least one student.';
    }
    setState(() => _studentError = studentError);
    if (!formOk || studentError != null) return;

    setState(() {
      _submitting = true;
      _formError = null;
    });

    try {
      final db = FirebaseFirestore.instance;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw const _ReportException(
          'Your session expired. Sign in again to send a report.',
        );
      }

      final profile =
          (await db.collection('users').doc(user.uid).get()).data() ?? {};
      final reporterName =
          (profile['name'] ?? user.displayName ?? user.email ?? 'Teacher')
              .toString()
              .trim();
      final teacherId = (profile['ID'] ?? '').toString().trim();
      if (profile['role']?.toString().toLowerCase() != 'teacher' ||
          teacherId.isEmpty) {
        throw const _ReportException(
          'Only a signed-in teacher with a valid teacher profile can submit this report.',
        );
      }

      final col = db.collection('incidentReports');
      final exam = _exam;
      final isStudent = _kind == _Kind.student;
      final students = !isStudent || exam == null
          ? <ReportableStudent>[]
          : exam.students.where((s) => _selected.contains(s.id)).toList();

      // Loophole: same teacher re-reporting the same student while a case is still pending.
      if (isStudent && exam != null) {
        final dupes = await Future.wait(
          students.map((s) async {
            final existing = await col
                .where('reportedBy', isEqualTo: user.uid)
                .where('examId', isEqualTo: exam.id)
                .where('studentId', isEqualTo: s.id)
                .where('status', isEqualTo: 'pending')
                .limit(1)
                .get();
            return existing.docs.isEmpty ? null : s.label;
          }),
        );
        final names = dupes.whereType<String>().toList();
        if (names.isNotEmpty) {
          throw _ReportException(
            'You already have a pending report for ${names.join(', ')}. '
            'Deselect them or wait for the admin to review it.',
          );
        }
      }

      final profiles = isStudent
          ? await _resolveProfiles(db, students)
          : <String, Map<String, String>>{};
      final batchId = col.doc().id;
      final base = <String, dynamic>{
        'reportType': isStudent ? 'student' : 'problem',
        'category': _category,
        'severity': _severity,
        'reason': _details.text.trim(),
        'status': 'pending',
        'reportedBy': user.uid,
        'reportedByName': reporterName,
        'teacherId': teacherId,
        'batchId': batchId,
        'source': 'teacher_reports',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (exam != null) ...{
          'examId': exam.id,
          'examTitle': exam.title,
          'classId': exam.classId,
        },
      };

      final batch = db.batch();
      if (isStudent && exam != null) {
        for (final s in students) {
          final name = s.name.isNotEmpty
              ? s.name
              : profiles[s.id]?['name'] ?? '';
          final email = s.email.isNotEmpty
              ? s.email
              : profiles[s.id]?['email'] ?? '';
          batch.set(col.doc(), {
            ...base,
            'batchSize': students.length,
            'studentId': s.id,
            'studentName': name,
            if (email.isNotEmpty) 'studentEmail': email,
            'resultPath': 'examResults/${exam.id}/students/${s.id}',
            'strikeCountAtReport': s.strikes,
          });
        }
      } else {
        batch.set(col.doc(), {
          ...base,
          'batchSize': 1,
          'studentName': 'General report',
        });
      }

      await batch.commit().timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw const _ReportException(
          'This is taking too long. Check your connection and try again.',
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(isStudent ? students.length : 1);
    } on _ReportException catch (error) {
      if (mounted) setState(() => _formError = error.message);
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(
          () => _formError = error.code == 'permission-denied'
              ? 'You do not have permission to send this report.'
              : 'Could not send the report (${error.code}). Your text is still here, so you can try again.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _formError =
              'Could not send the report. Your text is still here, so you can try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
