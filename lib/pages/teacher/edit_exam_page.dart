import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

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

  final _programController = TextEditingController();
  final _subjectController = TextEditingController();
  final _yearBlockController = TextEditingController();
  final _creatorController = TextEditingController();
  final _statusController = TextEditingController();
  final _teacherIdController = TextEditingController();

  DateTime? _startTime;
  DateTime? _endTime;

  @override
  void initState() {
    super.initState();

    if (widget.docId != null) {
      _loadExam(widget.docId!);
    } else if (widget.existing != null) {
      _setControllers(widget.existing!);
    }
  }

  void _loadExam(String id) async {
    final doc = await FirebaseFirestore.instance
        .collection('exams')
        .doc(id)
        .get();
    if (doc.exists) {
      _setControllers(doc.data()!);
    }
  }

  void _setControllers(Map<String, dynamic> data) {
    setState(() {
      _programController.text = data['program'] ?? '';
      _subjectController.text = data['subject'] ?? '';
      _yearBlockController.text = data['yearBlock'] ?? '';
      _creatorController.text = data['creator'] ?? '';
      _statusController.text = data['status'] ?? '';
      _teacherIdController.text = data['teacherId'] ?? '';
      _startTime = (data['startTime'] as Timestamp?)?.toDate();
      _endTime = (data['endTime'] as Timestamp?)?.toDate();
    });
  }

  @override
  void dispose() {
    _programController.dispose();
    _subjectController.dispose();
    _yearBlockController.dispose();
    _teacherIdController.dispose();
    _creatorController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime(bool isStart) async {
    final current = isStart ? _startTime : _endTime;
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );

    if (date == null) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? DateTime.now()),
    );

    if (time == null) return;

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

  Future<void> _saveExam() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startTime == null || _endTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select start and end time')),
      );
      return;
    }

    final data = {
      'program': _programController.text.trim(),
      'subject': _subjectController.text.trim(),
      'yearBlock': _yearBlockController.text.trim(),
      'creator': _creatorController.text.trim(),
      'status': _statusController.text.trim(),
      'teacherId': _teacherIdController.text.trim(),
      'startTime': Timestamp.fromDate(_startTime!),
      'endTime': Timestamp.fromDate(_endTime!),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      if (widget.docId == null) {
        await _db.collection('exams').add({
          ...data,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _db.collection('exams').doc(widget.docId).update(data);
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Exam saved successfully!')));
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Select date/time';
    return DateFormat('MMM d, yyyy – hh:mm a').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.docId != null;

    return Scaffold(
      backgroundColor: Color.fromARGB(255, 14, 45, 73),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F2B45),
        title: Text(
          isEditing ? 'Edit Exam' : 'Add Exam',
          style: TextStyle(color: Color(0xFFE6F0F8)),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field(_programController, 'Program'),
                  _field(_subjectController, 'Subject'),
                  _field(_yearBlockController, 'Year/Block'),
                  _field(_creatorController, 'Creator (Teacher)'),
                  _field(_teacherIdController, 'Teacher ID'),
                  _field(_statusController, 'Status (optional)'),

                  const SizedBox(height: 20),

                  const Text(
                    'Start Time',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE6F0F8),
                    ),
                  ),
                  _dateTimePicker(_startTime, () => _pickDateTime(true)),
                  const SizedBox(height: 16),

                  const Text(
                    'End Time',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE6F0F8),
                    ),
                  ),
                  _dateTimePicker(_endTime, () => _pickDateTime(false)),

                  const SizedBox(height: 30),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Color(0xFFE6F0F8),
                          side: BorderSide(color: Color(0xFF4DA3FF)),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color.fromARGB(255, 0, 255, 13),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _saveExam,
                        child: const Text('Save'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  Center(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Color(0xFFE6F0F8),
                        side: const BorderSide(color: Color(0xFF4DA3FF)),
                      ),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Edit Exam Questions'),
                      onPressed: () {
                        if (widget.docId != null) {
                          context.go(
                            '/edit-question/${widget.docId}',
                            // extra: {'existing': widget.existing}, // optional
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Save the exam first before editing questions.',
                              ),
                            ),
                          );
                        }
                      },
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

  Widget _field(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: TextFormField(
        controller: c,
        style: const TextStyle(color: Color(0xFFE6F0F8)),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF9DB8D1)),
          filled: true,
          fillColor: const Color(0xFF132033),
          contentPadding: const EdgeInsets.fromLTRB(12, 24, 12, 16),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey.shade600),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF4DA3FF)),
          ),
        ),
        validator: (v) => v == null || v.isEmpty ? 'Enter $label' : null,
      ),
    );
  }

  Widget _dateTimePicker(DateTime? dt, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF132033),
          border: Border.all(color: Colors.grey.shade600),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          _formatDateTime(dt),
          style: const TextStyle(color: Color(0xFFE6F0F8)),
        ),
      ),
    );
  }
}
