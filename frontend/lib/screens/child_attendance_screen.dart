import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/attendance_history_view.dart';

/// A child's attendance, as their parent sees it. The list itself is the
/// same widget the student sees on their own Attendance screen.
class ChildAttendanceScreen extends StatelessWidget {
  final String token;
  final String studentId;
  final String studentName;

  const ChildAttendanceScreen({
    super.key,
    required this.token,
    required this.studentId,
    required this.studentName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: AttendanceHistoryView(
        name: studentName,
        forParent: true,
        load: () async {
          final result = await ApiService.getChildAttendance(
            token: token,
            studentId: studentId,
          );
          return result['attendance'] as List<dynamic>? ?? [];
        },
      ),
    );
  }
}
