import 'package:flutter/material.dart';

class ManageActivityPage extends StatefulWidget {
  const ManageActivityPage({super.key});

  @override
  State<ManageActivityPage> createState() => _ManageActivityPageState();
}

class _ManageActivityPageState extends State<ManageActivityPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _questionController = TextEditingController();
  final TextEditingController _answerController = TextEditingController();

  final List<Map<String, String>> _questions = []; // local storage

  void _addQuestion() {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _questions.add({
          'question': _questionController.text.trim(),
          'answer': _answerController.text.trim(),
        });
      });
      _questionController.clear();
      _answerController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Question added successfully!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Manage Exam Activities",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _questionController,
                    decoration: InputDecoration(
                      labelText: "Enter Exam Question",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a question';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _answerController,
                    decoration: InputDecoration(
                      labelText: "Enter Correct Answer",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter the correct answer';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 15),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _addQuestion,
                      icon: const Icon(Icons.add),
                      label: const Text("Add Question"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 10),
            const Text(
              "Question List",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _questions.isEmpty
                  ? const Center(
                      child: Text(
                        'No questions added yet.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _questions.length,
                      itemBuilder: (context, index) {
                        final item = _questions[index];
                        return Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.deepPurple,
                              child: Text('${index + 1}',
                                  style: const TextStyle(color: Colors.white)),
                            ),
                            title: Text(item['question'] ?? ''),
                            subtitle: Text("Answer: ${item['answer']}"),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _questions.removeAt(index);
                                });
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
