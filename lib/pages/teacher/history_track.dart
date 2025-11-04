import 'package:flutter/material.dart';

class HistoryTrackPage extends StatelessWidget {
  const HistoryTrackPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'History / Track',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: 8,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, i) => ListTile(
                  leading: const Icon(Icons.event_note),
                  title: Text('Event ${i + 1}'),
                  subtitle: Text(
                    'Occurred at ${DateTime.now().subtract(Duration(days: i))}',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
