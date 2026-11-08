import 'package:flutter/material.dart';

import '../widgets/app_ui.dart';
import 'admin_student_report_screen.dart';

/// Admin: the students of one course, grouped by year level. Tapping a student
/// opens the same attendance report (DTR) as the Attendance reports module.
class AdminCourseStudentsScreen extends StatefulWidget {
  final String token;
  final String courseCode;
  final String courseName;

  /// The students of this course (from GET /admin/students).
  final List<Map<String, dynamic>> students;

  const AdminCourseStudentsScreen({
    super.key,
    required this.token,
    required this.courseCode,
    required this.courseName,
    required this.students,
  });

  @override
  State<AdminCourseStudentsScreen> createState() =>
      _AdminCourseStudentsScreenState();
}

class _AdminCourseStudentsScreenState extends State<AdminCourseStudentsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _name(Map<String, dynamic> student) => [
    student['last_name'],
    student['first_name'],
  ].where((part) => (part ?? '').toString().trim().isNotEmpty).join(', ');

  String _year(Map<String, dynamic> student) {
    final value = (student['year_level'] ?? '').toString().trim();
    return value.isEmpty ? 'No year level' : 'Year $value';
  }

  void _open(Map<String, dynamic> student) {
    final first = (student['first_name'] ?? '').toString().trim();
    final last = (student['last_name'] ?? '').toString().trim();
    final year = (student['year_level'] ?? '').toString().trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminUserAttendanceReportScreen(
          token: widget.token,
          userId: student['user_id'].toString(),
          userName: [first, last].where((p) => p.isNotEmpty).join(' '),
          idNumber: (student['student_number'] ?? '').toString(),
          classLabel: [
            widget.courseCode,
            if (year.isNotEmpty) 'Year $year',
          ].join(' • '),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.trim().toLowerCase();
    final shown = widget.students.where((student) {
      if (query.isEmpty) return true;
      final text = [
        student['first_name'],
        student['middle_name'],
        student['last_name'],
        student['student_number'],
      ].join(' ').toLowerCase();
      return text.contains(query);
    }).toList();

    // Year 1, Year 2, ... then students without a year level.
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final student in shown) {
      groups.putIfAbsent(_year(student), () => []).add(student);
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (a == 'No year level') return 1;
        if (b == 'No year level') return -1;
        return a.compareTo(b);
      });

    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: TextField(
          controller: _search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Search name or student number',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (value) => setState(() => _query = value),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Text(
          '${widget.students.length} '
          '${widget.students.length == 1 ? 'student' : 'students'} • '
          'Tap a student to open the attendance report.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ];

    if (widget.students.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.all(24),
          child: EmptyState(
            icon: Icons.groups_outlined,
            title: 'No students yet',
            message: 'Students of this course appear here after the import.',
          ),
        ),
      );
    } else if (shown.isEmpty) {
      children.add(
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No student matches the search.')),
        ),
      );
    }

    var index = 0;
    for (final key in keys) {
      final list = groups[key]!
        ..sort((a, b) => _name(a).toLowerCase().compareTo(_name(b).toLowerCase()));
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Text(
            '$key (${list.length})',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      );
      for (final student in list) {
        final active = student['status'] == 'active';
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: AppCard(
              index: index++,
              child: ListTile(
                title: Text(_name(student)),
                subtitle: Text(
                  [
                    (student['student_number'] ?? '').toString(),
                    if ((student['section'] ?? '').toString().trim().isNotEmpty)
                      'Section ${student['section']}',
                    if (!active) 'Inactive',
                  ].where((part) => part.isNotEmpty).join(' • '),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(student),
              ),
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.courseName.isEmpty ? widget.courseCode : widget.courseName,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: children,
      ),
    );
  }
}
