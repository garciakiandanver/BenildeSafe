import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/profile_state.dart';
import '../widgets/attendance_history_view.dart';

/// The student's own attendance. The list is the same widget a parent sees
/// for their child, so both look and count the same way.
class AttendanceHistoryScreen extends StatelessWidget {
  final String token;

  /// The student's name, shown at the top. Falls back to the saved profile.
  final String name;

  const AttendanceHistoryScreen({
    super.key,
    required this.token,
    this.name = '',
  });

  @override
  Widget build(BuildContext context) {
    final profile = ProfileState.instance;
    final shownName = name.trim().isNotEmpty ? name.trim() : profile.fullName;
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: AttendanceHistoryView(
        name: shownName,
        photo: profile.photo,
        load: () async {
          final result = await ApiService.getAttendanceHistory(token: token);
          return result['attendance'] as List<dynamic>? ?? [];
        },
      ),
    );
  }
}
