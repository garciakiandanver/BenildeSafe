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

  // Schedule filters. null means "All".
  String? _courseFilter;
  String? _yearFilter;

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
        _sanitizeFilters();
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
        final byCourse = _text(a['course']).toLowerCase().compareTo(
          _text(b['course']).toLowerCase(),
        );
        if (byCourse != 0) return byCourse;
        final byYear = _compareYears(_text(a['year_level']), _text(b['year_level']));
        if (byYear != 0) return byYear;
        final bySection = _text(a['section']).toLowerCase().compareTo(
          _text(b['section']).toLowerCase(),
        );
        if (bySection != 0) return bySection;
        return _text(a['subject']).toLowerCase().compareTo(
          _text(b['subject']).toLowerCase(),
        );
      });
    return result;
  }

  String _text(dynamic value) => (value?.toString() ?? '').trim();

  // "2" before "10"; anything that is not a number sorts by its text.
  int _compareYears(String a, String b) {
    final numberA = int.tryParse(a);
    final numberB = int.tryParse(b);
    if (numberA != null && numberB != null) return numberA.compareTo(numberB);
    return a.toLowerCase().compareTo(b.toLowerCase());
  }

  bool _sameText(dynamic a, String? b) =>
      b != null && _text(a).toUpperCase() == b.toUpperCase();

  List<String> get _courseOptions {
    final seen = <String, String>{};
    for (final item in _classes) {
      final course = _text(item['course']);
      if (course.isNotEmpty) seen.putIfAbsent(course.toUpperCase(), () => course);
    }
    return seen.values.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  // Years offered depend on the course picked, so the list stays short.
  List<String> get _yearOptions {
    final seen = <String, String>{};
    for (final item in _classes) {
      if (_courseFilter != null && !_sameText(item['course'], _courseFilter)) {
        continue;
      }
      final year = _text(item['year_level']);
      if (year.isNotEmpty) seen.putIfAbsent(year.toUpperCase(), () => year);
    }
    return seen.values.toList()..sort(_compareYears);
  }

  List<Map<String, dynamic>> get _visibleClasses => _classes.where((item) {
    if (_courseFilter != null && !_sameText(item['course'], _courseFilter)) {
      return false;
    }
    if (_yearFilter != null && !_sameText(item['year_level'], _yearFilter)) {
      return false;
    }
    return true;
  }).toList();

  void _sanitizeFilters() {
    if (_courseFilter != null && !_courseOptions.contains(_courseFilter)) {
      _courseFilter = null;
    }
    if (_yearFilter != null && !_yearOptions.contains(_yearFilter)) {
      _yearFilter = null;
    }
  }

  void _clearFilters() {
    setState(() {
      _courseFilter = null;
      _yearFilter = null;
    });
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

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        selectedColor: scheme.primaryContainer,
        backgroundColor: scheme.surface,
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? scheme.primary : scheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildFilterRow({
    required String label,
    required String allLabel,
    required List<String> options,
    required String? selected,
    required String Function(String) optionLabel,
    required ValueChanged<String?> onSelected,
  }) {
    return SizedBox(
      height: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _filterChip(allLabel, selected == null, () => onSelected(null)),
                  ...options.map(
                    (option) => _filterChip(
                      optionLabel(option),
                      _sameText(option, selected),
                      () => onSelected(option),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(int shown) {
    final theme = Theme.of(context);
    final hasFilter = _courseFilter != null || _yearFilter != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          _buildFilterRow(
            label: 'Course',
            allLabel: 'All courses',
            options: _courseOptions,
            selected: _courseFilter,
            optionLabel: (value) => value,
            onSelected: (value) => setState(() {
              _courseFilter = value;
              if (_yearFilter != null && !_yearOptions.contains(_yearFilter)) {
                _yearFilter = null;
              }
            }),
          ),
          const SizedBox(height: 6),
          _buildFilterRow(
            label: 'Year',
            allLabel: 'All years',
            options: _yearOptions,
            selected: _yearFilter,
            optionLabel: (value) => 'Year $value',
            onSelected: (value) => setState(() => _yearFilter = value),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Showing $shown of ${_classes.length} '
                  '${_classes.length == 1 ? 'class' : 'classes'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (hasFilter)
                TextButton(
                  onPressed: _clearFilters,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Clear filters'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // "BSIT • Year 2" heading shown above each course / year group.
  Widget _buildGroupHeader(Map<String, dynamic> item) {
    final theme = Theme.of(context);
    final year = _text(item['year_level']);
    final label = [
      _text(item['course']),
      if (year.isNotEmpty) 'Year $year',
    ].where((part) => part.isNotEmpty).join(' • ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Text(
        label.isEmpty ? 'Other classes' : label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildClassList() {
    final visible = _visibleClasses;
    return Column(
      children: [
        _buildFilters(visible.length),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadSchedule,
            child: visible.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      EmptyState(
                        icon: Icons.filter_alt_off_outlined,
                        title: 'No classes match',
                        message:
                            'There are no classes for the selected course and year.',
                        action: OutlinedButton(
                          onPressed: _clearFilters,
                          child: const Text('Clear filters'),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      final previous = index > 0 ? visible[index - 1] : null;
                      final newGroup =
                          previous == null ||
                          _text(previous['course']).toUpperCase() !=
                              _text(item['course']).toUpperCase() ||
                          _text(previous['year_level']).toUpperCase() !=
                              _text(item['year_level']).toUpperCase();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (newGroup) _buildGroupHeader(item),
                          _buildClass(item),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ],
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
          : _buildClassList(),
    );
  }
}