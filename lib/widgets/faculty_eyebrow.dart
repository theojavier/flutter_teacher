import 'package:flutter/material.dart';

/// The small blue label above every faculty page title, e.g. "04 / FACULTY WORKSPACE".
class FacultyEyebrow extends StatelessWidget {
  const FacultyEyebrow(
    this.number, {
    super.key,
    this.label = 'FACULTY WORKSPACE',
  });

  final String number; // "01" ... "07"
  final String label;

  // Same blue as the dashboard and scaffold. Change here to retheme everywhere.
  static const Color blue = Color(0xFF153CFF);

  @override
  Widget build(BuildContext context) {
    return Text(
      '$number / $label',
      style: const TextStyle(
        color: blue,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}