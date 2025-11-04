import 'package:flutter/material.dart';

class FlagsPage extends StatefulWidget {
  const FlagsPage({super.key});

  @override
  State<FlagsPage> createState() => _FlagsPageState();
}

class _FlagsPageState extends State<FlagsPage> {
  // temporary mock data – you can replace this with data from Firebase later
  final List<Map<String, dynamic>> _flaggedStudents = [
    {
      'name': 'Juan Dela Cruz',
      'reason': 'Left the camera view during exam',
      'time': '10:32 AM',
      'severity': 'High',
    },
    {
      'name': 'Maria Santos',
      'reason': 'Multiple face detected',
      'time': '10:40 AM',
      'severity': 'Medium',
    },
  ];

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
              "Student Behavior Flags",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "List of students flagged during digital examinations.",
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _flaggedStudents.isEmpty
                  ? const Center(
                      child: Text(
                        'No flagged students yet.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _flaggedStudents.length,
                      itemBuilder: (context, index) {
                        final student = _flaggedStudents[index];
                        return Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _getSeverityColor(student['severity']),
                              child: const Icon(Icons.warning, color: Colors.white),
                            ),
                            title: Text(student['name']),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Reason: ${student['reason']}"),
                                Text("Time: ${student['time']}"),
                              ],
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'remove') {
                                  setState(() => _flaggedStudents.removeAt(index));
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Remove flag'),
                                ),
                              ],
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

  Color _getSeverityColor(String severity) {
    switch (severity) {
      case 'High':
        return Colors.redAccent;
      case 'Medium':
        return Colors.orangeAccent;
      default:
        return Colors.blueGrey;
    }
  }
}
