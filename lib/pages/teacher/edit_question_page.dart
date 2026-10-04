// lib/pages/edit_question_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../helpers/AppTheme.dart';

// Shared colors (same navy palette used in the rest of the app)
const _kText = Color(0xFFE6F0F8);
const _kMuted = Color(0xFF9DB8D1);
const _kAccent = Color(0xFF4DA3FF);
const _kFieldBg = Color(0xFF0D1524);
const _kMenuBg = Color(0xFF132033);

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
  String? _error;

  // Local model for editing
  final List<_QuestionLocal> _questions = [];

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
      // Wait for auth if currentUser is null
      var user = FirebaseAuth.instance.currentUser;
      user ??= await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null);
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _saveAll() async {
    // validate required fields
    for (final q in _questions) {
      if (q.isMarkedForDelete) continue;
      if (q.questionTextController.text.trim().isEmpty) {
        _snack('Please fill question text for all questions.');
        return;
      }
      if (q.type == 'multiple-choice' &&
          q.optionControllers.any((c) => c.text.trim().isEmpty)) {
        _snack('Please fill all options for multiple-choice questions.');
        return;
      }
      if (q.type == 'matching' && _poolItems(q.poolController.text).isEmpty) {
        _snack('Matching question pools cannot be empty.');
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

      _snack('Questions updated successfully.');

      // reload to refresh ids and state
      await _loadQuestions();
    } catch (e) {
      _snack('Error saving questions: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggleMarkForDelete(_QuestionLocal q) {
    if (q.docId == null) {
      // never saved -> just remove it
      setState(() => _questions.remove(q));
      WidgetsBinding.instance.addPostFrameCallback((_) => q.dispose());
      return;
    }
    setState(() => q.isMarkedForDelete = !q.isMarkedForDelete);
  }

  Future<void> _showAddQuestionDialog() async {
    final result = await showDialog<_QuestionLocal>(
      context: context,
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
        color: _kFieldBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kAccent.withOpacity(.4)),
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

  Widget _buildHero() {
    final mc = _byType('multiple-choice').length;
    final tf = _byType('true-false').length;
    final mt = _byType('matching').length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.heroDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.quiz_outlined, color: AppTheme.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'EXAM QUESTIONS',
                style: TextStyle(
                  color: AppTheme.accent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: .8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Question Editor',
            style: TextStyle(
              color: AppTheme.text,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Manage, update and organize exam questions.',
            style: TextStyle(color: AppTheme.mutedText),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statChip(Icons.checklist, '$mc Multiple Choice'),
              _statChip(Icons.rule, '$tf True / False'),
              _statChip(Icons.compare_arrows, '$mt Matching'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGroup(String type, List<_QuestionLocal> items) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        AppTheme.sectionHeader(_typeIcon(type), _typeLabel(type)),
        for (var i = 0; i < items.length; i++)
          _buildQuestionCard(items[i], i + 1),
      ],
    );
  }

  Widget _fieldLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: _kText,
          ),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _kAccent.withOpacity(.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Q$number',
                    style: const TextStyle(
                      color: _kAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (q.isNew) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                    backgroundColor:
                        (marked ? _kAccent : AppTheme.error).withOpacity(.15),
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
                  color: AppTheme.error.withOpacity(.15),
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
    final correct =
        (q.correctIndex != null && q.correctIndex! < count) ? q.correctIndex! : 0;

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
          onChanged:
              disabled ? null : (v) => setState(() => q.correctAnswer = v),
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.cardDecoration(),
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
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

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
                style: TextStyle(color: AppTheme.error),
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

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _buildHero(),
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
        _buildActionBar(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
      toolbarHeight: 80,
      titleSpacing: 16,
      backgroundColor: AppTheme.header,
      foregroundColor: AppTheme.text,
      surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            AppTheme.appBarIcon(Icons.quiz_outlined),
            const SizedBox(width: 12),
            const Text('Edit Exam Questions'),
          ],
        ),
      ),
      body: _buildBody(),
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
      correctAnswer = d['correctAnswer']?.toString() ??
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
      map['correctAnswer'] = (correctAnswer != null && pool.contains(correctAnswer))
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

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _attachListeners() {
    _temp.poolController.addListener(_rebuild);
    for (final c in _temp.optionControllers) {
      c.addListener(_rebuild);
    }
  }

  void _detachListeners() {
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

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _create() {
    if (_temp.questionTextController.text.trim().isEmpty) {
      _toast('Enter question text');
      return;
    }
    if (_temp.type == 'multiple-choice' &&
        _temp.optionControllers.any((c) => c.text.trim().isEmpty)) {
      _toast('Fill all multiple-choice options');
      return;
    }
    if (_temp.type == 'matching' &&
        _poolItems(_temp.poolController.text).isEmpty) {
      _toast('Enter pool items for matching');
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
    return AlertDialog(
      backgroundColor: _kMenuBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        color: _kText,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: const TextStyle(color: _kText),
      title: Row(
        children: [
          AppTheme.appBarIcon(Icons.add),
          const SizedBox(width: 12),
          const Text('Add Question'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
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
                  child: Text('Multiple Choice',
                      style: TextStyle(color: _kText)),
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
              decoration:
                  AppTheme.inputDecoration('Question', icon: Icons.help_outline),
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
                      value: (_temp.correctIndex != null &&
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
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: _kAccent),
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _kAccent,
            foregroundColor: Colors.white,
          ),
          onPressed: _create,
          child: const Text('Create'),
        ),
      ],
    );
  }
}