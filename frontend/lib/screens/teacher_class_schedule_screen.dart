import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/app_ui.dart';
import 'teacher_class_attendance_screen.dart';

class TeacherClassScheduleScreen extends StatefulWidget {
  final String token;

  const TeacherClassScheduleScreen({super.key, required this.token});

  @override
  State<TeacherClassScheduleScreen> createState() =>
      _TeacherClassScheduleScreenState();
}

class _TeacherClassScheduleScreenState
    extends State<TeacherClassScheduleScreen> {
  static const _weekdays = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  bool _isLoading = true;
  String _error = '';
  List<Map<String, dynamic>> _classes = [];

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final result = await ApiService.getMyClassSchedule(token: widget.token);
      if (!mounted) return;
      setState(() {
        _classes = _groupClasses(result['schedules'] as List<dynamic>? ?? []);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  // The server returns one row per weekly meeting. Group the meetings of the
  // same subject / course / year / section into a single class.
  List<Map<String, dynamic>> _groupClasses(List<dynamic> schedules) {
    final groups = <String, Map<String, dynamic>>{};
    for (final item in schedules) {
      final meeting = Map<String, dynamic>.from(item as Map);
      final key = [
        meeting['course'],
        meeting['year_level'],
        meeting['section'],
        meeting['subject'],
      ].map((value) => (value?.toString() ?? '').trim().toUpperCase()).join('|');
      final group = groups.putIfAbsent(
        key,
        () => {...meeting, 'meetings': <Map<String, dynamic>>[]},
      );
      (group['meetings'] as List<Map<String, dynamic>>).add(meeting);
    }

    final result = groups.values.toList()
      ..sort((a, b) {
        final bySubject = (a['subject'] ?? '')
            .toString()
            .toLowerCase()
            .compareTo((b['subject'] ?? '').toString().toLowerCase());
        if (bySubject != 0) return bySubject;
        return '${a['course']} ${a['year_level']} ${a['section']}'.compareTo(
          '${b['course']} ${b['year_level']} ${b['section']}',
        );
      });
    return result;
  }

  String _formatTime(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.length < 5) return text.isEmpty ? '--' : text;
    final parts = text.substring(0, 5).split(':');
    final hour = int.tryParse(parts[0]);
    final minute = parts.length > 1 ? parts[1] : '';
    if (hour == null || minute.isEmpty) return text;
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$hour12:$minute ${hour < 12 ? 'AM' : 'PM'}';
  }

  String _weekday(dynamic value) {
    final day = value is num ? value.toInt() : int.tryParse('$value');
    if (day == null || day < 0 || day >= _weekdays.length) {
      return 'Unknown day';
    }
    return _weekdays[day];
  }

  String _classGroupLabel(Map<String, dynamic> group) {
    final section = group['section']?.toString().trim() ?? '';
    return [
      group['course']?.toString(),
      if (group['year_level'] != null) 'Year ${group['year_level']}',
      if (section.isNotEmpty) 'Section $section',
    ].where((value) => value != null && value.isNotEmpty).join(' • ');
  }

  void _openAttendance(Map<String, dynamic> group) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => TeacherClassAttendanceScreen(
          token: widget.token,
          scheduleId: group['id'].toString(),
          subject: group['subject']?.toString() ?? 'Class',
          classGroup: _classGroupLabel(group),
        ),
      ),
    );
  }

  Widget _buildMeeting(Map<String, dynamic> meeting) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 7),
          Text(
            _weekday(meeting['weekday']),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 14),
          Icon(
            Icons.schedule_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              '${_formatTime(meeting['start_time'])} - ${_formatTime(meeting['end_time'])}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClass(Map<String, dynamic> group) {
    final classGroup = _classGroupLabel(group);
    final meetings = group['meetings'] as List<Map<String, dynamic>>;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openAttendance(group),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group['subject']?.toString() ?? 'Class',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (classGroup.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        classGroup,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ...meetings.map(_buildMeeting),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.fact_check_outlined,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'View student attendance',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Class Schedule'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadSchedule,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh schedule',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? Center(
              child: EmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load your schedule',
                message: _error,
                action: FilledButton.icon(
                  onPressed: _loadSchedule,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ),
            )
          : _classes.isEmpty
          ? RefreshIndicator(
              onRefresh: _loadSchedule,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 100),
                  EmptyState(
                    icon: Icons.event_busy_outlined,
                    title: 'No classes assigned',
                    message:
                        'Your classes for the current term will appear here.',
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadSchedule,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                itemCount: _classes.length,
                itemBuilder: (context, index) => _buildClass(_classes[index]),
              ),
            ),
    );
  }
}