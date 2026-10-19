import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Home dashboard card with the daily schedule: one time window per school day
/// (first class start to last class end), not one entry per class.
///
/// Students see the time the day starts and the time after which a time in is
/// marked late. Teachers see the same window for the classes they teach.
class DailyScheduleCard extends StatefulWidget {
  final String token;
  final bool isTeacher;

  const DailyScheduleCard({
    super.key,
    required this.token,
    this.isTeacher = false,
  });

  @override
  State<DailyScheduleCard> createState() => _DailyScheduleCardState();
}

class _DailyScheduleCardState extends State<DailyScheduleCard> {
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
  bool _hasSchedule = false;
  Map<String, dynamic>? _today;
  Map<String, dynamic>? _nextDay;
  List<Map<String, dynamic>> _week = [];
  bool _showWeek = false;
  DateTime _fetchedAt = DateTime.now();
  Timer? _timer;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _load();
    // Keeps the countdown fresh and reloads when the school day starts or ends.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _ticks++;
      if (_ticks % 10 == 0 || _stateHasChanged()) {
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
      final result = await ApiService.getDailySchedule(token: widget.token);
      if (!mounted) return;
      setState(() {
        _hasSchedule = result['has_schedule'] == true;
        _today = _asMap(result['today']);
        _nextDay = _asMap(result['next_day']);
        _week = (result['week'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList()
          ..sort((a, b) => _weekOrder(a).compareTo(_weekOrder(b)));
        _fetchedAt = DateTime.now();
        _error = '';
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      // A failed background refresh keeps what is already on screen.
      if (silent && !_isLoading && _error.isEmpty) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic>? _asMap(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  // Monday first, Sunday last.
  int _weekOrder(Map<String, dynamic> item) {
    final weekday = (item['weekday'] as num?)?.toInt() ?? 0;
    return weekday == 0 ? 7 : weekday;
  }

  int get _minutesSinceLoad => DateTime.now().difference(_fetchedAt).inMinutes;

  // Today's state, kept up to date between reloads using the minutes the
  // server counted when it answered. Only differences are used here, so the
  // phone's own timezone never matters.
  String _currentState() {
    final today = _today;
    if (today == null) return 'none';
    final state = today['state']?.toString() ?? 'none';
    final elapsed = _minutesSinceLoad;
    if (state == 'upcoming') {
      final until = (today['minutes_until_start'] as num?)?.toInt() ?? 0;
      return until - elapsed > 0 ? 'upcoming' : 'in_session';
    }
    if (state == 'in_session') {
      final left = (today['minutes_until_end'] as num?)?.toInt() ?? 0;
      return left - elapsed > 0 ? 'in_session' : 'finished';
    }
    return state;
  }

  bool _stateHasChanged() {
    final today = _today;
    if (today == null) return false;
    return _currentState() != today['state']?.toString();
  }

  int _minutesUntilStart() {
    final today = _today;
    final base = (today?['minutes_until_start'] as num?)?.toInt() ?? 0;
    return base - _minutesSinceLoad;
  }

  int _minutesUntilEnd() {
    final today = _today;
    final left = (today?['minutes_until_end'] as num?)?.toInt();
    if (left != null) return left - _minutesSinceLoad;
    // The day started after the data was loaded: count from the day's length.
    final until = (today?['minutes_until_start'] as num?)?.toInt() ?? 0;
    final start = _minutesOfDay(today?['start_time']);
    final end = _minutesOfDay(today?['end_time']);
    final length = (start == null || end == null) ? 0 : end - start;
    return until + length - _minutesSinceLoad;
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
    final weekday = (item['weekday'] as num?)?.toInt() ?? 0;
    final name = _weekdays[weekday % 7];
    if (offset == 0) return 'Today';
    if (offset == 1) return 'Tomorrow';
    return offset >= 7 ? 'Next $name' : name;
  }

  String _duration(int minutes) {
    if (minutes < 1) return 'less than a minute';
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours h' : '$hours h $rest min';
  }

  Widget _iconBox(ThemeData theme, {IconData icon = Icons.event_note_outlined}) {
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

  Widget _simpleCard(
    ThemeData theme, {
    required IconData icon,
    required String title,
    String? message,
    Widget? trailing,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            _iconBox(theme, icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      message,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(ThemeData theme, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 7),
          Flexible(child: Text(text)),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _weekList(ThemeData theme) {
    return Column(
      children: _week.map((item) {
        final weekday = (item['weekday'] as num?)?.toInt() ?? 0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  _weekdays[weekday % 7],
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                child: Text(
                  _timeRange(item),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return _simpleCard(
        theme,
        icon: Icons.event_note_outlined,
        title: 'Loading your schedule...',
        trailing: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_error.isNotEmpty) {
      return _simpleCard(
        theme,
        icon: Icons.event_busy_outlined,
        title: 'Could not load your schedule.',
        trailing: TextButton(onPressed: _load, child: const Text('Retry')),
      );
    }

    if (!_hasSchedule) {
      return _simpleCard(
        theme,
        icon: Icons.event_available_outlined,
        title: 'No schedule yet',
        message: widget.isTeacher
            ? 'The days you teach this term will show up here.'
            : 'Your school days for this term will show up here.',
      );
    }

    final state = _currentState();
    final today = state == 'none' ? null : _today;
    // After the school day (or on a day without classes) show the next one.
    final showingToday = today != null && state != 'finished';
    final shown = showingToday ? today : _nextDay;

    final Color accent;
    final String badge;
    final String heading;
    if (showingToday && state == 'in_session') {
      accent = const Color(0xFF248A5A);
      heading = 'TODAY\'S SCHEDULE';
      badge = 'In session';
    } else if (showingToday) {
      accent = theme.colorScheme.primary;
      heading = 'TODAY\'S SCHEDULE';
      final until = _minutesUntilStart();
      badge = until < 1 ? 'Starting now' : 'Starts in ${_duration(until)}';
    } else if (shown != null) {
      accent = theme.colorScheme.primary;
      heading = today != null ? 'DONE FOR TODAY' : 'NO CLASSES TODAY';
      badge = _dayLabel(shown);
    } else {
      accent = theme.colorScheme.onSurfaceVariant;
      heading = 'DONE FOR TODAY';
      badge = 'No more days this week';
    }

    final classCount = (shown?['class_count'] as num?)?.toInt() ?? 0;
    final campus = shown?['campus_name']?.toString().trim() ?? '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    heading,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const Spacer(),
                _badge(badge, accent),
              ],
            ),
            const SizedBox(height: 12),
            if (shown != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _iconBox(theme),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!showingToday)
                          Text(
                            'Next school day: ${_dayLabel(shown)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        Text(
                          _timeRange(shown),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (!widget.isTeacher &&
                            _formatTime(shown['late_after']) != '--')
                          _infoRow(
                            theme,
                            Icons.schedule_outlined,
                            'Late after ${_formatTime(shown['late_after'])}',
                          ),
                        if (showingToday && state == 'in_session')
                          _infoRow(
                            theme,
                            Icons.hourglass_bottom_rounded,
                            'Ends in ${_duration(_minutesUntilEnd())}',
                          ),
                        if (widget.isTeacher && classCount > 0)
                          _infoRow(
                            theme,
                            Icons.menu_book_outlined,
                            classCount == 1 ? '1 class' : '$classCount classes',
                          ),
                        if (campus.isNotEmpty)
                          _infoRow(theme, Icons.location_on_outlined, campus),
                      ],
                    ),
                  ),
                ],
              )
            else
              Text(
                'Your classes for this week are done.',
                style: theme.textTheme.bodyMedium,
              ),
            if (_week.length > 1) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _showWeek = !_showWeek),
                  icon: Icon(
                    _showWeek
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                  label: Text(_showWeek ? 'Hide weekly schedule' : 'Weekly schedule'),
                ),
              ),
              if (_showWeek) _weekList(theme),
            ],
          ],
        ),
      ),
    );
  }
}
