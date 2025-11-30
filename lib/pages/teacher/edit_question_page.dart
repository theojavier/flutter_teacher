// lib/pages/edit_question_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EditQuestionPage extends StatefulWidget {
  final String? examDocId;
  const EditQuestionPage({Key? key, required this.examDocId}) : super(key: key);

  @override
  State<EditQuestionPage> createState() => _EditQuestionPageState();
}

class _EditQuestionPageState extends State<EditQuestionPage> {
  final _db = FirebaseFirestore.instance;
  bool _loading = true;
  String? _error;

  // Local model for editing
  final List<_QuestionLocal> _questions = [];
  final Map<String, _QuestionLocal> _existingMap = {}; // map by docId

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  Future<void> _loadQuestions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snap = await _db
          .collection('exams')
          .doc(widget.examDocId)
          .collection('questions')
          .orderBy('type')
          .get();

      _questions.clear();
      _existingMap.clear();

      for (final doc in snap.docs) {
        final q = _QuestionLocal.fromFirestore(doc.id, doc.data());
        _questions.add(q);
        _existingMap[doc.id] = q;
      }
    } catch (e) {
      _error = 'Failed to load questions: $e';
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  List<_QuestionLocal> _byType(String type) =>
      _questions.where((q) => q.type == type && !q.isDeletedTemp).toList();

  Future<void> _saveAll() async {
    // validate multiple-choice options and required fields
    for (final q in _questions) {
      if (q.isMarkedForDelete) continue;
      if (q.questionTextController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fill question text for all questions.'),
          ),
        );
        return;
      }
      if (q.type == 'multiple-choice') {
        if (q.optionControllers.any((c) => c.text.trim().isEmpty)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please fill all options for multiple-choice questions.',
              ),
            ),
          );
          return;
        }
      }
      if (q.type == 'matching') {
        if (q.poolController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Matching question pools cannot be empty.'),
            ),
          );
          return;
        }
      }
    }

    final batch = _db.batch();
    final colRef = _db
        .collection('exams')
        .doc(widget.examDocId)
        .collection('questions');

    try {
      for (final q in _questions) {
        if (q.isMarkedForDelete) {
          if (q.docId != null) {
            batch.delete(colRef.doc(q.docId));
          }
          continue;
        }

        final data = q.toFirestoreMap();

        if (q.isNew) {
          final newDocRef = colRef.doc();
          batch.set(newDocRef, data);
        } else {
          batch.update(colRef.doc(q.docId), data);
        }
      }

      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Questions updated successfully.')),
      );

      // reload to refresh ids and state
      await _loadQuestions();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving questions: $e')));
    }
  }

  void _toggleMarkForDelete(_QuestionLocal q) {
    setState(() => q.isMarkedForDelete = !q.isMarkedForDelete);
  }

  Future<void> _showAddQuestionDialog() async {
    final result = await showDialog<_QuestionLocal>(
      context: context,
      builder: (context) {
        return _AddQuestionDialog();
      },
    );

    if (result != null) {
      setState(() {
        _questions.add(result);
      });
    }
  }

  Widget _buildGroup(
    String title,
    List<_QuestionLocal> items, {
    EdgeInsets? indent,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFFE6F0F8),
          ),
        ),
        const SizedBox(height: 8),
        ...items.map((q) => _buildQuestionCard(q, indent: indent)).toList(),
      ],
    );
  }

  Widget _buildQuestionCard(_QuestionLocal q, {EdgeInsets? indent}) {
    return Card(
      color: const Color(0xFF132033),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // left content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // question text
                  TextFormField(
                    controller: q.questionTextController,
                    decoration: InputDecoration(
                      labelText: 'Question',
                      labelStyle: const TextStyle(color: Color(0xFF9DB8D1)),
                      filled: true,
                      fillColor: const Color(0xFF0D1524),
                      isDense: true,
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.shade700),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF4DA3FF)),
                      ),
                    ),
                    style: const TextStyle(color: Color(0xFFE6F0F8)),
                    minLines: 1,
                    maxLines: 3,
                  ),

                  const SizedBox(height: 8),

                  // type specific fields
                  if (q.type == 'multiple-choice') ...[
                    const Text(
                      'Options:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE6F0F8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...List.generate(q.optionControllers.length, (i) {
                      return Padding(
                        padding: EdgeInsets.only(
                          left: indent?.left ?? 0,
                          bottom: 6,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: q.optionControllers[i],
                                minLines: 1,
                                maxLines: 2,
                                decoration: InputDecoration(
                                  labelText: 'Option ${i + 1}',
                                  labelStyle: const TextStyle(
                                    color: Color(0xFF9DB8D1),
                                  ),
                                  filled: true,
                                  fillColor: const Color(0xFF0D1524),
                                  isDense: true,
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  focusedBorder: const OutlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Color(0xFF4DA3FF),
                                    ),
                                  ),
                                ),
                                style: const TextStyle(
                                  color: Color(0xFFE6F0F8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text(
                          'Correct answer: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE6F0F8),
                          ),
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          dropdownColor: Color(0xFF132033),
                          style: const TextStyle(color: Color(0xFFE6F0F8)),
                          value:
                              (q.correctIndex != null &&
                                  q.correctIndex! < q.optionControllers.length)
                              ? q.correctIndex
                              : 0,
                          items: List.generate(q.optionControllers.length, (i) {
                            final text =
                                q.optionControllers[i].text.trim().isEmpty
                                ? 'Option ${i + 1}'
                                : q.optionControllers[i].text.trim();
                            return DropdownMenuItem(
                              value: i,
                              child: Text(
                                text,
                                style: const TextStyle(
                                  color: Color(0xFFE6F0F8),
                                ),
                              ),
                            );
                          }),
                          onChanged: (v) =>
                              setState(() => q.correctIndex = v ?? 0),
                        ),
                      ],
                    ),
                  ] else if (q.type == 'true-false') ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: q.correctAnswer ?? 'True',
                          items: const [
                            DropdownMenuItem(
                              value: 'True',
                              child: Text('True'),
                            ),
                            DropdownMenuItem(
                              value: 'False',
                              child: Text('False'),
                            ),
                          ],
                          onChanged: (v) => setState(() => q.correctAnswer = v),
                        ),
                      ],
                    ),
                  ] else if (q.type == 'matching') ...[
                    const SizedBox(height: 6),
                    const Text(
                      'Pool (comma separated):',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE6F0F8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: q.poolController,
                      style: const TextStyle(color: Color(0xFFE6F0F8)),
                      decoration: const InputDecoration(
                        hintText: 'e.g. Tokyo, Osaka, Kyoto',
                        hintStyle: TextStyle(color: Color(0xFF9DB8D1)),
                        filled: true,
                        fillColor: Color(0xFF0D1524),
                        isDense: true,
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4DA3FF)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4DA3FF)),
                        ),
                      ),
                      minLines: 1,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),

                    // UPDATED: Ensure correctAnswer exists
                    Builder(
                      builder: (_) {
                        final poolItems = q.poolController.text
                            .split(',')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();
                        if (poolItems.isNotEmpty &&
                            (q.correctAnswer == null ||
                                !poolItems.contains(q.correctAnswer))) {
                          q.correctAnswer = poolItems.first;
                        }

                        return Row(
                          children: [
                            const Text(
                              'Correct answer:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFE6F0F8),
                              ),
                            ),
                            const SizedBox(width: 8),
                            DropdownButton<String>(
                              value: q.correctAnswer,
                              items: poolItems
                                  .map(
                                    (s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(
                                        s,
                                        style: const TextStyle(
                                          color: Color(0xFFE6F0F8),
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              dropdownColor: const Color(0xFF132033),
                              onChanged: (v) =>
                                  setState(() => q.correctAnswer = v),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),

            // right column (delete / checkbox)
            const SizedBox(width: 8),
            Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    // toggle a "delete confirmation" checkbox
                    setState(() {
                      q.showDeleteCheckbox = true;
                      q.isMarkedForDelete = !q.isMarkedForDelete;
                    });
                  },
                ),
                if (q.showDeleteCheckbox)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Delete'),
                      Checkbox(
                        value: q.isMarkedForDelete,
                        onChanged: (v) {
                          setState(() {
                            q.isMarkedForDelete = v ?? false;
                          });
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));

    final multiple = _byType('multiple-choice');
    final truefalse = _byType('true-false');
    final matching = _byType('matching');

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                _buildGroup('Multiple Choice', multiple),
                _buildGroup(
                  'True / False',
                  truefalse,
                  indent: const EdgeInsets.only(left: 18),
                ),
                _buildGroup('Matching', matching),
                const SizedBox(height: 24),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF4DA3FF)),
                  foregroundColor: const Color(0xFFE6F0F8),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add Question'),
                onPressed: _showAddQuestionDialog,
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4DA3FF),
                  foregroundColor: Colors.white,
                ),
                onPressed: _saveAll,
                child: const Text('Update'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (final q in _questions) q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color.fromARGB(255, 14, 45, 73),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B45),
        title: const Text(
          'Edit Exam Questions',
          style: TextStyle(color: Color(0xFFE6F0F8)),
        ),
        automaticallyImplyLeading: false,
      ),
      body: _buildBody(),
    );
  }
}

/// Local editable representation of a question
class _QuestionLocal {
  String? docId; // null => new doc
  String type;
  bool isNew;
  bool isMarkedForDelete = false;
  bool showDeleteCheckbox = false;
  bool isDeletedTemp = false; // internal

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
      // ensure 4 option controllers (fallback to available options)
      final desired = optionsRaw.isNotEmpty ? optionsRaw.length : 4;
      for (var i = 0; i < desired; i++) {
        optionControllers.add(
          TextEditingController(
            text: i < optionsRaw.length ? optionsRaw[i] : '',
          ),
        );
      }
    }

    final poolText = (optionsRaw.isNotEmpty)
        ? optionsRaw.join(', ')
        : (d['options'] is String ? d['options'] as String : '');

    final correct = (d['correctAnswer'] != null)
        ? d['correctAnswer'].toString()
        : (type == 'multiple-choice' ? (d['correctIndex']?.toString()) : null);

    int? correctIndex;
    String? correctAnswer;
    if (type == 'multiple-choice') {
      // try to parse as index or as value
      if (d['correctAnswer'] != null) {
        final ca = d['correctAnswer'].toString();
        final idx = int.tryParse(ca);
        if (idx != null)
          correctIndex = idx;
        else {
          // find matching option index
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
    final qController = TextEditingController();
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
      questionTextController: qController,
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
      // pool is comma separated in poolController
      final pool = poolController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      map['options'] = pool;
      map['correctAnswer'] =
          correctAnswer ?? (pool.isNotEmpty ? pool.first : '');
    }
    return map;
  }

  void dispose() {
    questionTextController.dispose();
    for (final c in optionControllers) c.dispose();
    poolController.dispose();
  }
}

/// Add Question Dialog
class _AddQuestionDialog extends StatefulWidget {
  @override
  State<_AddQuestionDialog> createState() => _AddQuestionDialogState();
}

class _AddQuestionDialogState extends State<_AddQuestionDialog> {
  String _type = 'multiple-choice';
  late _QuestionLocal _temp;
  VoidCallback? _poolListener;

  @override
  void initState() {
    super.initState();
    _temp = _QuestionLocal.newQuestion(type: _type);
    _attachPoolListener();
    _attachOptionListeners();
  }

  void _attachPoolListener() {
    _poolListener = () {
      if (mounted) setState(() {});
    };
    _temp.poolController.addListener(_poolListener!);
  }

  void _onTypeChanged(String? newType) {
    if (newType == null) return;

    // Detach old listener before disposing
    if (_poolListener != null) {
      _temp.poolController.removeListener(_poolListener!);
    }

    // Dispose the old question safely
    _temp.dispose();

    // Create new question and attach fresh listener
    setState(() {
      _type = newType;
      _temp = _QuestionLocal.newQuestion(type: _type);
      _attachPoolListener();
      _attachOptionListeners();
    });
  }

  void _attachOptionListeners() {
    for (final c in _temp.optionControllers) {
      c.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    if (_poolListener != null) {
      _temp.poolController.removeListener(_poolListener!);
    }
    _temp.dispose();
    super.dispose();
  }

  void _create() {
    if (_temp.questionTextController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter question text')));
      return;
    }
    if (_temp.type == 'multiple-choice' &&
        _temp.optionControllers.any((c) => c.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill all multiple-choice options')),
      );
      return;
    }
    if (_temp.type == 'matching' && _temp.poolController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter pool items for matching')),
      );
      return;
    }

    // Clone data before disposing
    final newQuestion = _QuestionLocal.newQuestion(type: _temp.type);
    newQuestion.questionTextController.text = _temp.questionTextController.text;
    for (var i = 0; i < _temp.optionControllers.length; i++) {
      if (i < newQuestion.optionControllers.length) {
        newQuestion.optionControllers[i].text = _temp.optionControllers[i].text;
      }
    }
    newQuestion.poolController.text = _temp.poolController.text;
    newQuestion.correctIndex = _temp.correctIndex;
    newQuestion.correctAnswer = _temp.correctAnswer;

    // Pop the cloned question (controllers are still active)
    Navigator.of(context).pop(newQuestion);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF132033),
      titleTextStyle: const TextStyle(color: Color(0xFFE6F0F8), fontSize: 20),
      contentTextStyle: const TextStyle(color: Color(0xFFE6F0F8)),
      title: const Text('Add Question'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(
                labelText: 'Type',
                labelStyle: TextStyle(color: Color(0xFF9DB8D1)),
                filled: true,
                fillColor: Color(0xFF0D1524),
              ),
              dropdownColor: const Color(0xFF132033), 
              style: const TextStyle(color: Color(0xFFE6F0F8)), 
              items: const [
                DropdownMenuItem(
                  value: 'multiple-choice',
                  child: Text(
                    'Multiple Choice',
                    style: TextStyle(color: Color(0xFFE6F0F8)),
                  ),
                ),
                DropdownMenuItem(
                  value: 'true-false',
                  child: Text(
                    'True / False',
                    style: TextStyle(color: Color(0xFFE6F0F8)),
                  ),
                ),
                DropdownMenuItem(
                  value: 'matching',
                  child: Text(
                    'Matching',
                    style: TextStyle(color: Color(0xFFE6F0F8)),
                  ),
                ),
              ],
              onChanged: _onTypeChanged,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _temp.questionTextController,
              style: const TextStyle(color: Color(0xFFE6F0F8)),
              decoration: const InputDecoration(
                labelText: 'Question',
                labelStyle: TextStyle(color: Color(0xFF9DB8D1)),
                filled: true,
                fillColor: Color(0xFF0D1524),
              ),
            ),

            const SizedBox(height: 8),
            if (_temp.type == 'multiple-choice') ...[
              const SizedBox(height: 6),
              ...List.generate(_temp.optionControllers.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TextFormField(
                    controller: _temp.optionControllers[i],
                    style: const TextStyle(color: Color(0xFFE6F0F8)),
                    decoration: InputDecoration(
                      labelText: 'Option ${i + 1}',
                      labelStyle: const TextStyle(color: Color(0xFF9DB8D1)),
                      filled: true,
                      fillColor: const Color(0xFF0D1524),
                      isDense: true,
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.grey.shade700),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF4DA3FF)),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('Correct:'),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    dropdownColor: const Color(0xFF132033),
                    style: const TextStyle(color: Color(0xFFE6F0F8)),
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
                      return DropdownMenuItem(value: i, child: Text(text));
                    }),
                    onChanged: (v) =>
                        setState(() => _temp.correctIndex = v ?? 0),
                  ),
                ],
              ),
            ],
            if (_temp.type == 'true-false') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Correct:'),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    dropdownColor: Color(0xFF132033),
                    style: const TextStyle(color: Color(0xFFE6F0F8)),
                    value: _temp.correctAnswer ?? 'True',
                    items: const [
                      DropdownMenuItem(value: 'True', child: Text('True')),
                      DropdownMenuItem(value: 'False', child: Text('False')),
                    ],
                    onChanged: (v) => setState(() => _temp.correctAnswer = v),
                  ),
                ],
              ),
            ],
            if (_temp.type == 'matching') ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _temp.poolController,
                style: const TextStyle(color: Color(0xFFE6F0F8)),
                decoration: const InputDecoration(
                  labelText: 'Pool (comma separated)',
                  labelStyle: TextStyle(color: Color(0xFFE6F0F8)),
                  filled: true,
                  fillColor: Color(0xFF0D1524),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF4DA3FF)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF4DA3FF)),
                  ),
                ),
              ),

              const SizedBox(height: 8),
              if (_temp.poolController.text.isNotEmpty)
                Row(
                  children: [
                    const Text(
                      'Correct:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFE6F0F8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _temp.correctAnswer,
                      items: _temp.poolController.text
                          .split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                s,
                                style: const TextStyle(
                                  color: Color(0xFFE6F0F8),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      dropdownColor: const Color(0xFF132033),
                      onChanged: (v) => setState(() => _temp.correctAnswer = v),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Color(0xFF4DA3FF)),
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4DA3FF),
            foregroundColor: Colors.white,
          ),
          child: const Text('Create'),
          onPressed: _create,
        ),
      ],
    );
  }
}
