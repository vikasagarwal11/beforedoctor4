import 'package:flutter/material.dart';

String formatShortDate(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$m-$d';
}

String formatTime(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String formatShortDateTime(DateTime dt) {
  return '${formatShortDate(dt)} • ${formatTime(dt)}';
}

String dayCounterLabel(DateTime startAt) {
  final diff = DateTime.now().difference(startAt).inDays;
  final day = diff < 0 ? 0 : diff + 1;
  return 'Day $day';
}

IconData iconForEventType(dynamic t) {
  switch (t.toString()) {
    case 'EventType.symptom':
      return Icons.sick_outlined;
    case 'EventType.medicationIssue':
      return Icons.medication_outlined;
    case 'EventType.vaccineReaction':
      return Icons.vaccines_outlined;
    default:
      return Icons.notes_outlined;
  }
}
