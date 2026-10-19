import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Home dashboard reminder of the user's upcoming class / subject.
/// Works for both students and teachers (the server picks the right classes).
class NextClassCard extends StatefulWidget {
  final String token;

  const NextClassCard({super.key, required this.token});

  @override
  State<NextClassCard> createState() => _NextClassCardState();
}

class _NextClassCardState extends State<NextClassCard> {
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
  DateTime _fetchedAt = DateTime.now();
  Timer? _timer;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _load();
    // Keeps the countdown fresh and reloads when the current class is over.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _ticks++;
      if (_ticks % 10 == 0 || _firstClassIsOver()) {
        _load(silent: true);
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = '';
      });
    }
    try {
      final result = await ApiService.getNextClass(token: widget.token);
      if (!mounted) return;
      setState(() {
        _classes = (result['classes'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _fetchedAt = DateTime.now();
        _error = '';
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      // A failed background refresh keeps what is already on screen.
      if (silent && _classes.isNotEmpty) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  // Minutes until the class starts, counted from when the data was loaded.
  int _minutesUntil(Map<String, dynamic> item) {
    final base = (item['minutes_until'] as num?)?.toInt() ?? 0;
    return base - DateTime.now().difference(_fetchedAt).inMinutes;
  }

  int _durationMinutes(Map<String, dynamic> item) {
    final start = _minutesOfDay(item['start_time']);
    final end = _minutesOfDay(item['end_time']);
    if (start == null || end == null) return 0;
    return end - start;
  }

  bool _firstClassIsOver() {
    if (_classes.isEmpty) return false;
    final first = _classes.first;
    return _minutesUntil(first) + _durationMinutes(first) <= 0;
  }

  int? _minutesOfDay(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.length < 5) return null;
    final parts = text.substring(0, 5).split(':');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts.length > 1 ? parts[1] : '');
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  String _formatTime(dynamic value) {
    final minutes = _minutesOfDay(value);
    if (minutes == null) return '--';
    final hour = minutes ~/ 60;
    final minute = (minutes % 60).toString().padLeft(2, '0');
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$hour12:$minute ${hour < 12 ? 'AM' : 'PM'}';
  }

  String _timeRange(Map<String, dynamic> item) =>
      '${_formatTime(item['start_time'])} - ${_formatTime(item['end_time'])}';

  String _dayLabel(Map<String, dynamic> item) {
    final offset = (item['day_offset'] as num?)?.toInt() ?? 0;
    if (offset == 0) return 'Today';
    if (offset == 1) return 'Tomorrow';
    final weekday = (item['weekday'] as num?)?.toInt() ?? 0;
    final name = _weekdays[weekday % 7];
    return offset >= 7 ? 'Next $name' : name;
  }

  String _countdown(int minutes) {
    if (minutes < 1) return 'Starting now';
    if (minutes < 60) return 'in $minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? 'in $hours h' : 'in $hours h $rest min';
  }

  String _classGroup(Map<String, dynamic> item) {
    final section = item['section']?.toString().trim() ?? '';
    final year = item['year_level']?.toString().trim() ?? '';
    return [
      item['course']?.toString().trim(),
      if (year.isNotEmpty) 'Year $year',
      if (section.isNotEmpty) 'Section $section',
    ].where((value) => value != null && value.isNotEmpty).join(' • ');
  }

  Widget _iconBox(ThemeData theme, {IconData icon = Icons.menu_book_outlined}) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: theme.colorScheme.primary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              _iconBox(theme, icon: Icons.event_note_outlined),
              const SizedBox(width: 14),
              const Expanded(child: Text('Loading your next class...')),
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        ),
      );
    }

    if (_error.isNotEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              _iconBox(theme, icon: Icons.event_busy_outlined),
              const SizedBox(width: 14),
              const Expanded(child: Text('Could not load your next class.')),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_classes.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              _iconBox(theme, icon: Icons.event_available_outlined),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No upcoming classes',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your classes for this term will show up here.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final next = _classes.first;
    final minutes = _minutesUntil(next);
    final isNow = minutes <= 0;
    final offset = (next['day_offset'] as num?)?.toInt() ?? 0;
    final group = _classGroup(next);
    final teacher = next['teacher_name']?.toString().trim() ?? '';
    final campus = next['campus_name']?.toString().trim() ?? '';
    final accent = isNow ? const Color(0xFF248A5A) : theme.colorScheme.primary;
    final later = _classes.skip(1).toList();

    final String badge;
    if (isNow) {
      badge = 'Now';
    } else if (offset == 0) {
      badge = _countdown(minutes);
    } else {
      badge = _dayLabel(next);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isNow ? 'CURRENT CLASS' : 'NEXT CLASS',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _iconBox(theme),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        next['subject']?.toString() ?? 'Class',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (group.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          group,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_outlined,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              '${_dayLabel(next)}, ${_timeRange(next)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (teacher.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 7),
                            Flexible(child: Text(teacher)),
                          ],
                        ),
                      ],
                      if (campus.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 7),
                            Flexible(child: Text(campus)),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (later.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Text(
                'AFTER THIS',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
              ...later.map(
                (item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['subject']?.toString() ?? 'Class',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${_dayLabel(item)}, ${_formatTime(item['start_time'])}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}