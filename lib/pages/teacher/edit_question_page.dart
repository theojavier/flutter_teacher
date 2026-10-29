// lib/pages/edit_question_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../helpers/AppTheme.dart';
import '../../widgets/app_dialog.dart';

const _kText = AppTheme.text;
const _kMuted = AppTheme.mutedText;
const _kAccent = AppTheme.accent;
const _kMenuBg = AppTheme.header;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
IconData _typeIcon(String type) {
  switch (type) {
    case 'multiple-choice':
      return Icons.checklist;
    case 'true-false':
      return Icons.rule;
    default:
      return Icons.compare_arrows;
  }
}

String _typeLabel(String type) {
  switch (type) {
    case 'multiple-choice':
      return 'Multiple Choice';
    case 'true-false':
      return 'True / False';
    default:
      return 'Matching';
  }
}

/// Comma separated text -> unique, trimmed, non-empty items.
List<String> _poolItems(String raw) => raw
    .split(',')
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toSet()
    .toList();

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------
class EditQuestionPage extends StatefulWidget {
  final String examDocId;
  const EditQuestionPage({super.key, required this.examDocId});

  @override
  State<EditQuestionPage> createState() => _EditQuestionPageState();
}

class _EditQuestionPageState extends State<EditQuestionPage> {
  final _db = FirebaseFirestore.instance;
  bool _loading = true;
  bool _saving = false;
  bool _submitting = false;
  bool _returningToDraft = false;
  String? _error;

  // Local model for editing
  final List<_QuestionLocal> _questions = [];
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _examStream = _db
      .collection('exams')
      .doc(widget.examDocId)
      .snapshots();
  late final Future<Map<String, String>> _programAcronymsFuture =
      _loadProgramAcronyms();

  @override
  void initState() {
    super.initState();
    FirebaseAuth.instance
        .authStateChanges()
        .firstWhere((u) => u != null)
        .then((_) => _loadQuestions())
        .catchError((_) {
          // fallback: try after a short delay
          Future.delayed(const Duration(seconds: 1), _loadQuestions);
        });
  }

  // -------------------------------------------------------------------------
  // Data
  // -------------------------------------------------------------------------
  Future<void> _loadQuestions() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final loaded = <_QuestionLocal>[];
    String? error;

    try {
      final exam = await _db.collection('exams').doc(widget.examDocId).get();
      final approvalStatus = (exam.data()?['approvalStatus'] ?? 'draft')
          .toString()
          .toLowerCase();
      if (approvalStatus == 'approved' || approvalStatus == 'pending') {
        await _showFeedback(
          'Questions are locked',
          'Approved or pending exams cannot be edited.',
          tone: AppTone.warning,
        );
        if (mounted) context.go('/teacher-exams');
        return;
      }

      // Wait for auth if currentUser is null
      var user = FirebaseAuth.instance.currentUser;
      user ??= await FirebaseAuth.instance.authStateChanges().firstWhere(
        (u) => u != null,
      );
      await user!.getIdToken(true);

      final functions = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      );
      final result = await functions.httpsCallable('loadExamQuestions').call({
        'examId': widget.examDocId,
      });

      final List<dynamic> questionsData = result.data['questions'] ?? [];
      for (final raw in questionsData) {
        final qData = Map<String, dynamic>.from(raw as Map);
        final docId = qData['id'] as String;
        loaded.add(_QuestionLocal.fromFirestore(docId, qData));
      }
    } catch (e) {
      error = 'Failed to load questions: $e';
    }

    if (!mounted) {
      for (final q in loaded) {
        q.dispose();
      }
      return;
    }

    final old = List<_QuestionLocal>.of(_questions);
    setState(() {
      _questions
        ..clear()
        ..addAll(loaded);
      _error = error;
      _loading = false;
    });
    // dispose old controllers only after the frame that stops using them
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final q in old) {
        q.dispose();
      }
    });
  }

  List<_QuestionLocal> _byType(String type) =>
      _questions.where((q) => q.type == type).toList();

  Future<void> _showFeedback(
    String title,
    String message, {
    AppTone tone = AppTone.info,
  }) async {
    if (!mounted) return;
    await AppDialog.alert(context, title: title, message: message, tone: tone);
  }

  Future<Map<String, String>> _loadProgramAcronyms() async {
    final snapshot = await _db.collection('programs').get();
    final acronyms = <String, String>{};
    const ignoredWords = {'a', 'an', 'and', 'for', 'in', 'of', 'the', 'to'};
    for (final program in snapshot.docs) {
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

  Widget _examIdentityCard(
    Map<String, dynamic> data,
    Map<String, String> programAcronyms,
  ) {
    final subject = (data['subject'] ?? data['title'] ?? '').toString().trim();
    final programValue = (data['program'] ?? '').toString().trim();
    final program = programAcronyms[programValue];
    final yearBlock = (data['yearBlock'] ?? '').toString().trim();
    final schoolYear = (data['schoolYear'] ?? '').toString().trim();
    final semester = (data['semester'] ?? '').toString().trim();
    final status = (data['approvalStatus'] ?? 'draft').toString().toLowerCase();
    final isPendingReview = status == 'pending';
    final programTitle =
        program ?? (programValue.isEmpty ? 'EXAM' : 'PROGRAM $programValue');
    final examTitle = [
      '$programTitle${yearBlock.isNotEmpty ? '.$yearBlock' : ''}',
      if (subject.isNotEmpty) '($subject)',
    ].join(' ');

    Widget detail(String label, String value) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.line),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 11),
          children: [
            TextSpan(
              text: '$label  ',
              style: const TextStyle(
                color: AppTheme.mutedText,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: AppTheme.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );

    final details = <Widget>[
      if (schoolYear.isNotEmpty) detail('School year', schoolYear),
      if (semester.isNotEmpty) detail('Semester', semester),
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  examTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.display(25, ls: -0.045),
                ),
              ),
              if (isPendingReview) ...[
                const SizedBox(width: 10),
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB7791F).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFB7791F).withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    'IN REVIEW',
                    style: TextStyle(
                      color: Color(0xFFB7791F),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 9),
            Wrap(spacing: 7, runSpacing: 7, children: details),
          ],
        ],
      ),
    );
  }

  Future<void> _returnToDraft() async {
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Return exam to draft?',
      message:
          'This removes the exam from the admin review queue. You can edit it '
          'and submit it again later.',
      detail: 'The exam questions and schedule will not be deleted.',
      confirmLabel: 'Return to draft',
      tone: AppTone.warning,
      icon: Icons.undo_outlined,
    );
    if (!confirmed || !mounted) return;

    setState(() => _returningToDraft = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw StateError('No signed-in teacher was found.');
      }
      final userDoc = await _db.collection('users').doc(user.uid).get();
      final teacherId = userDoc.data()?['ID']?.toString();
      final examRef = _db.collection('exams').doc(widget.examDocId);

      await _db.runTransaction((transaction) async {
        final examSnapshot = await transaction.get(examRef);
        if (!examSnapshot.exists) {
          throw StateError('This exam no longer exists.');
        }
        final data = examSnapshot.data()!;
        final isOwner =
            data['createdBy'] == user.uid ||
            (teacherId != null && data['teacherId'] == teacherId);
        if (!isOwner) {
          throw StateError('You are not allowed to change this exam.');
        }
        if ((data['approvalStatus'] ?? 'draft').toString().toLowerCase() !=
            'pending') {
          throw StateError(
            'Only exams pending review can be returned to draft.',
          );
        }

        transaction.update(examRef, {
          'approvalStatus': 'draft',
          'submittedAt': FieldValue.delete(),
          'reviewNote': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (!mounted) return;
      await _showFeedback(
        'Returned to draft',
        'The exam is no longer waiting for review. You can edit it and submit it again.',
        tone: AppTone.success,
      );
    } catch (error) {
      await _showFeedback(
        'Unable to return exam to draft',
        '$error',
        tone: AppTone.error,
      );
    } finally {
      if (mounted) setState(() => _returningToDraft = false);
    }
  }

  Future<void> _saveAll() async {
    // validate required fields
    for (final q in _questions) {
      if (q.isMarkedForDelete) continue;
      if (q.questionTextController.text.trim().isEmpty) {
        await _showFeedback(
          'Question text required',
          'Please fill question text for all questions.',
          tone: AppTone.warning,
        );
        return;
      }
      if (q.type == 'multiple-choice' &&
          q.optionControllers.any((c) => c.text.trim().isEmpty)) {
        await _showFeedback(
          'Options required',
          'Please fill all options for multiple-choice questions.',
          tone: AppTone.warning,
        );
        return;
      }
      if (q.type == 'matching' && _poolItems(q.poolController.text).isEmpty) {
        await _showFeedback(
          'Matching pool required',
          'Matching question pools cannot be empty.',
          tone: AppTone.warning,
        );
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final functions = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      );

      for (final q in _questions) {
        if (q.isMarkedForDelete) {
          if (q.docId != null) {
            await _db
                .collection('exams')
                .doc(widget.examDocId)
                .collection('questions')
                .doc(q.docId!)
                .delete();
          }
          continue;
        }

        final data = q.toFirestoreMap();

        final result = await functions.httpsCallable('saveQuestion').call({
          'examId': widget.examDocId,
          'questionId': q.docId,
          'questionText': data['questionText'],
          'options': data['options'],
          'correctAnswer': data['correctAnswer'],
          'type': data['type'],
        });

        debugPrint('Save result: ${result.data}');
      }

      // reload to refresh ids and state
      await _loadQuestions();
      await _showFeedback(
        'Questions saved',
        'Questions updated successfully.',
        tone: AppTone.success,
      );
    } catch (e) {
      await _showFeedback(
        'Unable to save questions',
        'Error saving questions: $e',
        tone: AppTone.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitForReview() async {
    if (_questions.any((q) => q.docId == null || q.isMarkedForDelete)) {
      await _showFeedback(
        'Save your changes first',
        'Tap Save Changes so new, edited and deleted questions are stored before you submit.',
        tone: AppTone.warning,
      );
      return;
    }
    final ok = await AppDialog.confirm(
      context,
      title: 'Submit for review?',
      message:
          'An admin will review your questions. You can\'t edit '
          'them while the exam is pending.',
      confirmLabel: 'Submit',
      tone: AppTone.info,
    );
    if (!ok || !mounted) return;

    setState(() => _submitting = true);
    try {
      await FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('submitExamForReview').call({'examId': widget.examDocId});
      await _showFeedback(
        'Submitted',
        'Your exam is now waiting for admin review.',
        tone: AppTone.success,
      );
    } on FirebaseFunctionsException catch (e) {
      await _showFeedback(
        'Unable to submit',
        e.message ?? e.code,
        tone: AppTone.error,
      );
    } catch (e) {
      await _showFeedback('Unable to submit', '$e', tone: AppTone.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _toggleMarkForDelete(_QuestionLocal q) async {
    if (!q.isMarkedForDelete) {
      final confirmed = await AppDialog.confirm(
        context,
        title: q.docId == null ? 'Remove question?' : 'Delete question?',
        message: q.docId == null
            ? 'This unsaved question will be removed from the form.'
            : 'This question will be permanently deleted when you save changes.',
        confirmLabel: q.docId == null ? 'Remove' : 'Delete',
        tone: AppTone.danger,
      );
      if (!confirmed || !mounted) return;
    }

    if (q.docId == null) {
      // never saved -> just remove it
      setState(() => _questions.remove(q));
      WidgetsBinding.instance.addPostFrameCallback((_) => q.dispose());
      return;
    }
    setState(() => q.isMarkedForDelete = !q.isMarkedForDelete);
  }

  Future<void> _showAddQuestionDialog() async {
    final result = await AppDialog.custom<_QuestionLocal>(
      context,
      builder: (_) => _AddQuestionDialog(),
    );

    if (result != null && mounted) {
      setState(() => _questions.add(result));
    }
  }

  @override
  void dispose() {
    for (final q in _questions) {
      q.dispose();
    }
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // UI pieces
  // -------------------------------------------------------------------------
  Widget _statChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.redSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _kAccent.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: _kAccent),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: _kText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 10),
      Text(
        'FOTS / QUESTION / 04',
        style: AppTheme.mono(10, color: AppTheme.redDark),
      ),
      const SizedBox(height: 12),
      Text('Questions.', style: AppTheme.display(34, ls: -0.06)),
      const SizedBox(height: 6),
      const Text(
        'Manage, update and organize exam questions',
        style: TextStyle(color: AppTheme.mutedText, fontSize: 13, height: 1.6),
      ),
    ],
  );

  Widget _buildChips() {
    final mc = _byType('multiple-choice').length;
    final tf = _byType('true-false').length;
    final mt = _byType('matching').length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _statChip(Icons.checklist, '$mc Multiple Choice'),
        _statChip(Icons.rule, '$tf True / False'),
        _statChip(Icons.compare_arrows, '$mt Matching'),
      ],
    );
  }

  Widget _approvalCard() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _examStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration(),
            child: Text(
              'Could not load approval details: ${snapshot.error}',
              style: const TextStyle(color: AppTheme.error, fontSize: 13),
            ),
          );
        }
        if (!snapshot.hasData) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration(),
            child: const LinearProgressIndicator(color: AppTheme.accent),
          );
        }
        if (!snapshot.data!.exists) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration(),
            child: const Text(
              'Approval details are unavailable because this exam no longer exists.',
              style: TextStyle(color: AppTheme.mutedText, fontSize: 13),
            ),
          );
        }

        final data = snapshot.data!.data()!;
        final status = (data['approvalStatus'] ?? 'draft')
            .toString()
            .toLowerCase();
        final note = (data['reviewNote'] ?? '').toString().trim();
        final questionCount = _questions
            .where((q) => !q.isMarkedForDelete)
            .length;
        final submittedValue = data['submittedAt'];
        final submittedAt = submittedValue is Timestamp
            ? DateFormat('MMM d, yyyy · h:mm a').format(submittedValue.toDate())
            : null;

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

        return FutureBuilder<Map<String, String>>(
          future: _programAcronymsFuture,
          builder: (context, programSnapshot) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _examIdentityCard(data, programSnapshot.data ?? const {}),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: AppTheme.cardDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppTheme.sectionHeader(
                        Icons.fact_check_outlined,
                        'Approval details',
                      ),
                      Wrap(
                        spacing: 12,
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
                              border: Border.all(
                                color: color.withValues(alpha: 0.3),
                              ),
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
                            'Questions in editor: $questionCount',
                            style: const TextStyle(
                              color: AppTheme.mutedText,
                              fontSize: 12,
                            ),
                          ),
                          if (submittedAt != null)
                            Text(
                              'Submitted: $submittedAt',
                              style: const TextStyle(
                                color: AppTheme.mutedText,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                      if (note.isNotEmpty) ...[
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
                              Text(
                                'ADMIN REVIEW NOTE',
                                style: AppTheme.mono(
                                  9,
                                  color: AppTheme.redDark,
                                ).copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                note,
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
                      if (status == 'draft' ||
                          status == 'changes_requested') ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: AppTheme.primaryButton(),
                            onPressed: _submitting || _saving
                                ? null
                                : _submitForReview,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_outlined, size: 18),
                            label: Text(
                              status == 'changes_requested'
                                  ? 'Resubmit for review'
                                  : 'Submit for review',
                            ),
                          ),
                        ),
                      ],
                      if (status == 'pending') ...[
                        const SizedBox(height: 12),
                        const Text(
                          'Waiting for an admin to review this exam.',
                          style: TextStyle(
                            color: AppTheme.mutedText,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _returningToDraft || _saving
                                ? null
                                : _returnToDraft,
                            icon: _returningToDraft
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.undo_outlined, size: 18),
                            label: Text(
                              _returningToDraft
                                  ? 'Returning to draft...'
                                  : 'Return to draft',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildGroup(String type, List<_QuestionLocal> items) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        AppTheme.sectionHeader(
          _typeIcon(type),
          '${_typeLabel(type)} · ${items.length}',
        ),
        for (var i = 0; i < items.length; i++)
          _buildQuestionCard(items[i], i + 1),
      ],
    );
  }

  Widget _fieldLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, color: _kText),
    ),
  );

  Widget _buildQuestionCard(_QuestionLocal q, int number) {
    final marked = q.isMarkedForDelete;

    return Opacity(
      opacity: marked ? .6 : 1,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header: number, NEW badge, delete button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.redSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Q$number',
                    style: AppTheme.mono(
                      12,
                      color: AppTheme.redDark,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (q.isNew) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kAccent),
                    ),
                    child: const Text(
                      'NEW',
                      style: TextStyle(
                        color: _kAccent,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                IconButton(
                  tooltip: marked ? 'Undo delete' : 'Delete question',
                  style: IconButton.styleFrom(
                    backgroundColor: (marked ? _kAccent : AppTheme.error)
                        .withValues(alpha: 0.15),
                  ),
                  icon: Icon(
                    marked ? Icons.undo : Icons.delete_outline,
                    color: marked ? _kAccent : AppTheme.error,
                  ),
                  onPressed: () => _toggleMarkForDelete(q),
                ),
              ],
            ),

            if (marked)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.error),
                ),
                child: Text(
                  'Marked for deletion. It will be removed when you save.',
                  style: TextStyle(
                    color: AppTheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // question text
            TextFormField(
              controller: q.questionTextController,
              enabled: !marked,
              decoration: AppTheme.inputDecoration(
                'Question',
                icon: Icons.help_outline,
              ),
              style: const TextStyle(color: _kText),
              minLines: 1,
              maxLines: 3,
            ),

            const SizedBox(height: 12),

            // type specific fields
            if (q.type == 'multiple-choice')
              _buildMultipleChoiceFields(q, marked)
            else if (q.type == 'true-false')
              _buildTrueFalseFields(q, marked)
            else if (q.type == 'matching')
              _buildMatchingFields(q, marked),
          ],
        ),
      ),
    );
  }

  Widget _buildMultipleChoiceFields(_QuestionLocal q, bool disabled) {
    final count = q.optionControllers.length;
    final correct = (q.correctIndex != null && q.correctIndex! < count)
        ? q.correctIndex!
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Options'),
        ...List.generate(count, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextFormField(
              controller: q.optionControllers[i],
              enabled: !disabled,
              minLines: 1,
              maxLines: 2,
              style: const TextStyle(color: _kText),
              decoration: AppTheme.inputDecoration(
                'Option ${i + 1}',
                icon: i == correct
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              onChanged: (_) => setState(() {}), // refresh dropdown labels
            ),
          );
        }),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text(
              'Correct answer:',
              style: TextStyle(fontWeight: FontWeight.w600, color: _kText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<int>(
                isExpanded: true,
                dropdownColor: _kMenuBg,
                style: const TextStyle(color: _kText),
                value: correct,
                items: List.generate(count, (i) {
                  final text = q.optionControllers[i].text.trim().isEmpty
                      ? 'Option ${i + 1}'
                      : q.optionControllers[i].text.trim();
                  return DropdownMenuItem(
                    value: i,
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _kText),
                    ),
                  );
                }),
                onChanged: disabled
                    ? null
                    : (v) => setState(() => q.correctIndex = v ?? 0),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTrueFalseFields(_QuestionLocal q, bool disabled) {
    return Row(
      children: [
        const Text(
          'Correct answer:',
          style: TextStyle(fontWeight: FontWeight.w600, color: _kText),
        ),
        const SizedBox(width: 12),
        DropdownButton<String>(
          value: q.correctAnswer ?? 'True',
          dropdownColor: _kMenuBg,
          style: const TextStyle(color: _kText),
          items: const [
            DropdownMenuItem(
              value: 'True',
              child: Text('True', style: TextStyle(color: _kText)),
            ),
            DropdownMenuItem(
              value: 'False',
              child: Text('False', style: TextStyle(color: _kText)),
            ),
          ],
          onChanged: disabled
              ? null
              : (v) => setState(() => q.correctAnswer = v),
        ),
      ],
    );
  }

  Widget _buildMatchingFields(_QuestionLocal q, bool disabled) {
    final pool = _poolItems(q.poolController.text);
    // make sure the selected answer always exists in the pool
    if (pool.isNotEmpty &&
        (q.correctAnswer == null || !pool.contains(q.correctAnswer))) {
      q.correctAnswer = pool.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: q.poolController,
          enabled: !disabled,
          style: const TextStyle(color: _kText),
          decoration: AppTheme.inputDecoration(
            'Matching Pool',
            helper: 'Comma separated values',
            icon: Icons.list_alt,
          ),
          minLines: 1,
          maxLines: 2,
          onChanged: (_) => setState(() {}), // refresh correct-answer list
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text(
              'Correct answer:',
              style: TextStyle(fontWeight: FontWeight.w600, color: _kText),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: pool.isEmpty ? null : q.correctAnswer,
                dropdownColor: _kMenuBg,
                style: const TextStyle(color: _kText),
                hint: const Text(
                  'Add pool items first',
                  style: TextStyle(color: _kMuted),
                ),
                items: pool
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child: Text(
                          s,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _kText),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: disabled
                    ? null
                    : (v) => setState(() => q.correctAnswer = v),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.header,
        border: Border(top: BorderSide(color: AppTheme.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _kAccent),
                        foregroundColor: _kText,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Question'),
                      onPressed: _saving ? null : _showAddQuestionDialog,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: AppTheme.primaryButton(),
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(_saving ? 'Saving...' : 'Save Changes'),
                      onPressed: _saving ? null : _saveAll,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accent),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: AppTheme.error, size: 40),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.error),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _kAccent),
                  foregroundColor: _kText,
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                onPressed: _loadQuestions,
              ),
            ],
          ),
        ),
      );
    }

    final pad = MediaQuery.of(context).size.width < 600 ? 16.0 : 24.0;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: EdgeInsets.all(pad),
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _approvalCard(),
                  const SizedBox(height: 16),
                  _buildChips(),
                  if (_questions.isEmpty) ...[
                    const SizedBox(height: 16),
                    AppTheme.emptyCard(
                      Icons.quiz_outlined,
                      'No questions found for this exam.',
                    ),
                  ] else ...[
                    _buildGroup('multiple-choice', _byType('multiple-choice')),
                    _buildGroup('true-false', _byType('true-false')),
                    _buildGroup('matching', _byType('matching')),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
        _buildActionBar(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(child: _buildBody()),
    );
  }
}

// ---------------------------------------------------------------------------
// Local editable representation of a question
// ---------------------------------------------------------------------------
class _QuestionLocal {
  String? docId; // null => new doc
  String type;
  bool isNew;
  bool isMarkedForDelete = false;

  // controllers
  final TextEditingController questionTextController;
  final List<TextEditingController> optionControllers; // multiple-choice
  final TextEditingController poolController; // matching pool
  int? correctIndex; // for multiple-choice
  String? correctAnswer; // for true-false and matching

  _QuestionLocal._({
    this.docId,
    required this.type,
    required this.isNew,
    required this.questionTextController,
    required this.optionControllers,
    required this.poolController,
    this.correctIndex,
    this.correctAnswer,
  });

  factory _QuestionLocal.fromFirestore(String docId, Map<String, dynamic> d) {
    final type = (d['type'] as String?) ?? 'multiple-choice';
    final qController = TextEditingController(
      text: d['questionText'] as String? ?? '',
    );
    final optionsRaw =
        (d['options'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
        [];

    final optionControllers = <TextEditingController>[];
    if (type == 'multiple-choice') {
      final desired = optionsRaw.isNotEmpty ? optionsRaw.length : 4;
      for (var i = 0; i < desired; i++) {
        optionControllers.add(
          TextEditingController(
            text: i < optionsRaw.length ? optionsRaw[i] : '',
          ),
        );
      }
    }

    final poolText = optionsRaw.isNotEmpty
        ? optionsRaw.join(', ')
        : (d['options'] is String ? d['options'] as String : '');

    int? correctIndex;
    String? correctAnswer;
    if (type == 'multiple-choice') {
      if (d['correctAnswer'] != null) {
        final ca = d['correctAnswer'].toString();
        final idx = int.tryParse(ca);
        if (idx != null) {
          correctIndex = idx;
        } else {
          final idx2 = optionsRaw.indexOf(ca);
          if (idx2 >= 0) correctIndex = idx2;
        }
      } else if (d['correctIndex'] != null) {
        correctIndex = (d['correctIndex'] as int?) ?? 0;
      } else {
        correctIndex = 0;
      }
    } else {
      correctAnswer =
          d['correctAnswer']?.toString() ??
          (type == 'true-false' ? 'True' : null);
    }

    return _QuestionLocal._(
      docId: docId,
      type: type,
      isNew: false,
      questionTextController: qController,
      optionControllers: optionControllers,
      poolController: TextEditingController(text: poolText),
      correctIndex: correctIndex,
      correctAnswer: correctAnswer,
    );
  }

  factory _QuestionLocal.newQuestion({required String type}) {
    final options = <TextEditingController>[];
    if (type == 'multiple-choice') {
      for (var i = 0; i < 4; i++) {
        options.add(TextEditingController());
      }
    }
    return _QuestionLocal._(
      docId: null,
      type: type,
      isNew: true,
      questionTextController: TextEditingController(),
      optionControllers: options,
      poolController: TextEditingController(),
      correctIndex: type == 'multiple-choice' ? 0 : null,
      correctAnswer: type == 'true-false' ? 'True' : null,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    final map = <String, dynamic>{};
    map['type'] = type;
    map['questionText'] = questionTextController.text.trim();
    if (type == 'multiple-choice') {
      final options = optionControllers.map((c) => c.text.trim()).toList();
      final idx = correctIndex ?? 0;
      final correct = (idx >= 0 && idx < options.length) ? options[idx] : '';
      map['options'] = options;
      map['correctAnswer'] = correct;
    } else if (type == 'true-false') {
      map['correctAnswer'] = correctAnswer ?? 'True';
      map['options'] = ['True', 'False'];
    } else if (type == 'matching') {
      final pool = _poolItems(poolController.text);
      map['options'] = pool;
      map['correctAnswer'] =
          (correctAnswer != null && pool.contains(correctAnswer))
          ? correctAnswer
          : (pool.isNotEmpty ? pool.first : '');
    }
    return map;
  }

  void dispose() {
    questionTextController.dispose();
    for (final c in optionControllers) {
      c.dispose();
    }
    poolController.dispose();
  }
}

// ---------------------------------------------------------------------------
// Add Question Dialog
// ---------------------------------------------------------------------------
class _AddQuestionDialog extends StatefulWidget {
  @override
  State<_AddQuestionDialog> createState() => _AddQuestionDialogState();
}

class _AddQuestionDialogState extends State<_AddQuestionDialog> {
  String _type = 'multiple-choice';
  late _QuestionLocal _temp;
  bool _handedOff = false; // true once _temp is returned to the page
  String? _validationMessage;

  void _rebuild() {
    if (mounted) {
      setState(() => _validationMessage = null);
    }
  }

  void _attachListeners() {
    _temp.questionTextController.addListener(_rebuild);
    _temp.poolController.addListener(_rebuild);
    for (final c in _temp.optionControllers) {
      c.addListener(_rebuild);
    }
  }

  void _detachListeners() {
    _temp.questionTextController.removeListener(_rebuild);
    _temp.poolController.removeListener(_rebuild);
    for (final c in _temp.optionControllers) {
      c.removeListener(_rebuild);
    }
  }

  @override
  void initState() {
    super.initState();
    _temp = _QuestionLocal.newQuestion(type: _type);
    _attachListeners();
  }

  void _onTypeChanged(String? newType) {
    if (newType == null || newType == _type) return;

    final oldQuestion = _temp;
    final keepText = oldQuestion.questionTextController.text;
    _detachListeners();

    setState(() {
      _type = newType;
      _temp = _QuestionLocal.newQuestion(type: _type);
      _temp.questionTextController.text = keepText; // keep what was typed
      _attachListeners();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => oldQuestion.dispose());
  }

  @override
  void dispose() {
    _detachListeners();
    if (!_handedOff) _temp.dispose();
    super.dispose();
  }

  void _create() {
    if (_temp.questionTextController.text.trim().isEmpty) {
      setState(() => _validationMessage = 'Enter question text.');
      return;
    }
    if (_temp.type == 'multiple-choice' &&
        _temp.optionControllers.any((c) => c.text.trim().isEmpty)) {
      setState(() => _validationMessage = 'Fill all multiple-choice options.');
      return;
    }
    if (_temp.type == 'matching' &&
        _poolItems(_temp.poolController.text).isEmpty) {
      setState(() => _validationMessage = 'Enter pool items for matching.');
      return;
    }

    _handedOff = true; // the page now owns (and will dispose) these controllers
    Navigator.of(context).pop(_temp);
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(fontWeight: FontWeight.w600, color: _kText),
  );

  @override
  Widget build(BuildContext context) {
    return AppDialog.formCard(
      title: 'Add Question',
      icon: Icons.add,
      confirmLabel: 'Create',
      onCancel: () => Navigator.of(context).pop(),
      onConfirm: _create,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            isExpanded: true,
            decoration: AppTheme.inputDecoration('Type', icon: Icons.category),
            dropdownColor: _kMenuBg,
            style: const TextStyle(color: _kText),
            items: const [
              DropdownMenuItem(
                value: 'multiple-choice',
                child: Text('Multiple Choice', style: TextStyle(color: _kText)),
              ),
              DropdownMenuItem(
                value: 'true-false',
                child: Text('True / False', style: TextStyle(color: _kText)),
              ),
              DropdownMenuItem(
                value: 'matching',
                child: Text('Matching', style: TextStyle(color: _kText)),
              ),
            ],
            onChanged: _onTypeChanged,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _temp.questionTextController,
            style: const TextStyle(color: _kText),
            minLines: 1,
            maxLines: 3,
            decoration: AppTheme.inputDecoration(
              'Question',
              icon: Icons.help_outline,
            ),
          ),
          const SizedBox(height: 12),

          // ---- multiple choice ----
          if (_temp.type == 'multiple-choice') ...[
            ...List.generate(_temp.optionControllers.length, (i) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextFormField(
                  controller: _temp.optionControllers[i],
                  style: const TextStyle(color: _kText),
                  decoration: AppTheme.inputDecoration(
                    'Option ${i + 1}',
                    icon: Icons.radio_button_unchecked,
                  ),
                ),
              );
            }),
            const SizedBox(height: 4),
            Row(
              children: [
                _label('Correct:'),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    dropdownColor: _kMenuBg,
                    style: const TextStyle(color: _kText),
                    value:
                        (_temp.correctIndex != null &&
                            _temp.correctIndex! <
                                _temp.optionControllers.length)
                        ? _temp.correctIndex
                        : 0,
                    items: List.generate(_temp.optionControllers.length, (i) {
                      final text =
                          _temp.optionControllers[i].text.trim().isEmpty
                          ? 'Option ${i + 1}'
                          : _temp.optionControllers[i].text.trim();
                      return DropdownMenuItem(
                        value: i,
                        child: Text(
                          text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _kText),
                        ),
                      );
                    }),
                    onChanged: (v) =>
                        setState(() => _temp.correctIndex = v ?? 0),
                  ),
                ),
              ],
            ),
          ],

          // ---- true / false ----
          if (_temp.type == 'true-false')
            Row(
              children: [
                _label('Correct:'),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  dropdownColor: _kMenuBg,
                  style: const TextStyle(color: _kText),
                  value: _temp.correctAnswer ?? 'True',
                  items: const [
                    DropdownMenuItem(
                      value: 'True',
                      child: Text('True', style: TextStyle(color: _kText)),
                    ),
                    DropdownMenuItem(
                      value: 'False',
                      child: Text('False', style: TextStyle(color: _kText)),
                    ),
                  ],
                  onChanged: (v) => setState(() => _temp.correctAnswer = v),
                ),
              ],
            ),

          // ---- matching ----
          if (_temp.type == 'matching') ...[
            TextFormField(
              controller: _temp.poolController,
              style: const TextStyle(color: _kText),
              decoration: AppTheme.inputDecoration(
                'Matching Pool',
                helper: 'Comma separated values',
                icon: Icons.list_alt,
              ),
            ),
            Builder(
              builder: (_) {
                final pool = _poolItems(_temp.poolController.text);
                if (pool.isEmpty) return const SizedBox.shrink();
                if (_temp.correctAnswer == null ||
                    !pool.contains(_temp.correctAnswer)) {
                  _temp.correctAnswer = pool.first;
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      _label('Correct:'),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: _temp.correctAnswer,
                          dropdownColor: _kMenuBg,
                          style: const TextStyle(color: _kText),
                          items: pool
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(
                                    s,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: _kText),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _temp.correctAnswer = v),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          if (_validationMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _validationMessage!,
              style: TextStyle(
                color: AppTheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
