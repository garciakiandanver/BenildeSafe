import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/app_ui.dart';

/// Teacher portal: attendance of every student in one class, for a day, a week
/// (Monday to Sunday) or a whole month.
class TeacherClassAttendanceScreen extends StatefulWidget {
  final String token;
  final String scheduleId;
  final String subject;
  final String classGroup;

  const TeacherClassAttendanceScreen({
    super.key,
    required this.token,
    required this.scheduleId,
    required this.subject,
    required this.classGroup,
  });

  @override
  State<TeacherClassAttendanceScreen> createState() =>
      _TeacherClassAttendanceScreenState();
}

class _TeacherClassAttendanceScreenState
    extends State<TeacherClassAttendanceScreen> {
  static const _weekdaysShort = [
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];
  static const _monthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const _monthsLong = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  String _period = 'weekly';
  DateTime _anchor = DateTime.now();
  bool _isLoading = true;
  String _error = '';
  Map<String, dynamic>? _data;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Ignore answers to older requests if the teacher changes the filter quickly.
    final requestId = ++_requestId;
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final result = await ApiService.getTeacherClassAttendance(
        token: widget.token,
        scheduleId: widget.scheduleId,
        period: _period,
        date: _dateString(_anchor),
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _data = result;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _shift(int direction) {
    setState(() {
      if (_period == 'daily') {
        _anchor = DateTime(_anchor.year, _anchor.month, _anchor.day + direction);
      } else if (_period == 'weekly') {
        _anchor = DateTime(
          _anchor.year,
          _anchor.month,
          _anchor.day + 7 * direction,
        );
      } else {
        _anchor = DateTime(_anchor.year, _anchor.month + direction, 1);
      }
    });
    _load();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchor,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => _anchor = picked);
    _load();
  }

  // ---------------------------------------------------------------- helpers

  String _dateString(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }

  DateTime? _parseDate(String? value) =>
      DateTime.tryParse('${value ?? ''}T00:00:00');

  String _shortDate(DateTime date) =>
      '${_weekdaysShort[date.weekday % 7]}, ${_monthsShort[date.month - 1]} ${date.day}';

  String _rangeLabel() {
    final a = _anchor;
    if (_period == 'daily') return '${_shortDate(a)}, ${a.year}';
    if (_period == 'monthly') return '${_monthsLong[a.month - 1]} ${a.year}';
    final monday = DateTime(a.year, a.month, a.day - (a.weekday - 1));
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    return '${_monthsShort[monday.month - 1]} ${monday.day} - '
        '${_monthsShort[sunday.month - 1]} ${sunday.day}, ${sunday.year}';
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

  Color _statusColor(String status) {
    switch (status) {
      case 'present':
        return Colors.green.shade700;
      case 'late':
        return Colors.orange.shade800;
      case 'absent':
        return Colors.red.shade700;
      default:
        return Colors.grey.shade600;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'present':
        return 'Present';
      case 'late':
        return 'Late';
      case 'absent':
        return 'Absent';
      case 'pending':
        return 'In progress';
      default:
        return 'Upcoming';
    }
  }

  // ---------------------------------------------------------------- widgets

  Widget _statusChip(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _countChip(String label, dynamic count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '$label ${count ?? 0}',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildControls() {
    final theme = Theme.of(context);
    final data = _data;
    final totals = data == null
        ? null
        : Map<String, dynamic>.from((data['totals'] as Map?) ?? {});
    final studentCount = (data?['students'] as List<dynamic>?)?.length ?? 0;
    final sessionCount = (data?['sessions'] as List<dynamic>?)?.length ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.classGroup.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                widget.classGroup,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'daily', label: Text('Daily')),
                ButtonSegment(value: 'weekly', label: Text('Weekly')),
                ButtonSegment(value: 'monthly', label: Text('Monthly')),
              ],
              selected: {_period},
              onSelectionChanged: (selection) {
                setState(() => _period = selection.first);
                _load();
              },
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Previous',
                onPressed: _isLoading ? null : () => _shift(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text(_rangeLabel()),
                ),
              ),
              IconButton(
                tooltip: 'Next',
                onPressed: _isLoading ? null : () => _shift(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (totals != null && !_isLoading && _error.isEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _countChip('Present', totals['present'], Colors.green.shade700),
                _countChip('Late', totals['late'], Colors.orange.shade800),
                _countChip('Absent', totals['absent'], Colors.red.shade700),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$studentCount students  •  $sessionCount class meeting(s) in this period',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecord(Map<String, dynamic> record) {
    final date = _parseDate(record['date']?.toString());
    final status = record['status']?.toString() ?? 'upcoming';
    final timeIn = record['time_in']?.toString();
    final timeOut = record['time_out']?.toString();
    final details = <String>[
      '${_formatTime(record['start_time'])} - ${_formatTime(record['end_time'])}',
      if (timeIn != null) 'In ${_formatTime(timeIn)}',
      if (timeOut != null) 'Out ${_formatTime(timeOut)}',
    ];
    return ListTile(
      dense: true,
      title: Text(
        date == null ? (record['date']?.toString() ?? '') : _shortDate(date),
      ),
      subtitle: Text(details.join('  •  ')),
      trailing: _statusChip(status),
    );
  }

  Widget _buildStudent(Map<String, dynamic> student) {
    final records = (student['attendance'] as List<dynamic>? ?? [])
        .map((record) => Map<String, dynamic>.from(record as Map))
        .toList();
    final summary = Map<String, dynamic>.from(
      (student['summary'] as Map?) ?? {},
    );

    final Widget trailing;
    if (_period == 'daily' && records.length == 1) {
      trailing = _statusChip(records.first['status']?.toString() ?? 'upcoming');
    } else {
      trailing = Text(
        'P ${summary['present'] ?? 0}  •  L ${summary['late'] ?? 0}  •  A ${summary['absent'] ?? 0}',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          student['name']?.toString() ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(student['student_number']?.toString() ?? ''),
        trailing: trailing,
        children: records.map(_buildRecord).toList(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load attendance',
          message: _error,
          action: FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
      );
    }

    final data = _data;
    if (data == null) return const SizedBox.shrink();
    final students = data['students'] as List<dynamic>? ?? [];
    final sessions = data['sessions'] as List<dynamic>? ?? [];

    if (students.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.people_outline,
          title: 'No students found',
          message:
              "No students match this class's course, year level and section.",
        ),
      );
    }
    if (sessions.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'No class meetings',
          message: 'This class does not meet in the selected period.',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: students.length,
        itemBuilder: (context, index) => _buildStudent(
          Map<String, dynamic>.from(students[index] as Map),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildControls(),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }
}