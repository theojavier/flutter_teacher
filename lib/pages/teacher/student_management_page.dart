import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StudentManagementPage extends StatefulWidget {
  final String teacherId;
  const StudentManagementPage({super.key, required this.teacherId});

  @override
  State<StudentManagementPage> createState() => _StudentManagementPageState();
}

class _StudentManagementPageState extends State<StudentManagementPage> {
  final db = FirebaseFirestore.instance;
  String filterType = 'all'; // all, flagged, strikes

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Management'),
        backgroundColor: Colors.blue,
      ),
      body: Column(
        children: [
          // Filter buttons
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(label: Text('All'), value: 'all'),
                      ButtonSegment(label: Text('Flagged'), value: 'flagged'),
                      ButtonSegment(label: Text('Strikes'), value: 'strikes'),
                    ],
                    selected: {filterType},
                    onSelectionChanged: (Set<String> newSelection) {
                      setState(() {
                        filterType = newSelection.first;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          // Students list
          Expanded(child: _buildStudentsList()),
        ],
      ),
    );
  }

  Widget _buildStudentsList() {
    Query query = db
        .collection('students')
        .where('teacherId', isEqualTo: widget.teacherId);

    if (filterType == 'flagged') {
      query = query.where('flagged', isEqualTo: true);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.people_outline, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  filterType == 'flagged'
                      ? 'No flagged students'
                      : 'No students found',
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        var students = snapshot.data!.docs;

        // Filter by strikes if needed
        if (filterType == 'strikes') {
          students = students
              .where((doc) => (doc['strikes'] ?? 0) > 0)
              .toList();
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: students.length,
          itemBuilder: (context, index) {
            final doc = students[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildStudentCard(doc.id, data);
          },
        );
      },
    );
  }

  Widget _buildStudentCard(String studentId, Map<String, dynamic> data) {
    final bool isFlagged = data['flagged'] ?? false;
    final int strikes = data['strikes'] ?? 0;
    final String reason = data['flagReason'] ?? 'No reason specified';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: isFlagged ? Colors.red.shade50 : Colors.white,
      child: ExpansionTile(
        leading: isFlagged
            ? const Icon(Icons.warning, color: Colors.red)
            : const Icon(Icons.person, color: Colors.blue),
        title: Text(
          data['name'] ?? 'Unknown',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isFlagged ? Colors.red : Colors.black,
          ),
        ),
        subtitle: Text(data['email'] ?? 'No email'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Status:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isFlagged ? Colors.red : Colors.green,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        isFlagged ? 'FLAGGED' : 'ACTIVE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Strikes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Strikes:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: strikes >= 3 ? Colors.red : Colors.orange,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$strikes',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Reason
                if (isFlagged)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Reason:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reason,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                // Action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Flag/Unflag button
                    ElevatedButton.icon(
                      onPressed: () => _toggleFlag(studentId, isFlagged),
                      icon: Icon(isFlagged ? Icons.check : Icons.warning),
                      label: Text(isFlagged ? 'Unflag' : 'Flag'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isFlagged
                            ? Colors.green
                            : Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    // Add strike button
                    ElevatedButton.icon(
                      onPressed: () => _addStrike(studentId, strikes),
                      icon: const Icon(Icons.add),
                      label: const Text('Strike'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (strikes > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _removeStrike(studentId, strikes),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Remove Strike'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFlag(String studentId, bool currentFlag) async {
    if (currentFlag) {
      // Unflag
      try {
        await db.collection('students').doc(studentId).update({
          'flagged': false,
          'flagReason': '',
        });
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Student unflagged')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    } else {
      // Flag
      _showFlagReasonDialog(studentId);
    }
  }

  void _showFlagReasonDialog(String studentId) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Flag Student'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter reason for flagging:'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: 'e.g., Cheating, Suspicious behavior',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _flagStudent(studentId, reasonController.text);
              Navigator.pop(context);
            },
            child: const Text('Flag'),
          ),
        ],
      ),
    );
  }

  Future<void> _flagStudent(String studentId, String reason) async {
    try {
      await db.collection('students').doc(studentId).update({
        'flagged': true,
        'flagReason': reason,
        'strikes': 1, // Start with 1 strike
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student flagged successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addStrike(String studentId, int currentStrikes) async {
    try {
      final newStrikes = currentStrikes + 1;
      await db.collection('students').doc(studentId).update({
        'strikes': newStrikes,
        'flagged': true, // Ensure flagged
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Strike added! Total: $newStrikes')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _removeStrike(String studentId, int currentStrikes) async {
    try {
      final newStrikes = (currentStrikes - 1).clamp(0, 999);
      await db.collection('students').doc(studentId).update({
        'strikes': newStrikes,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Strike removed! Total: $newStrikes')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
