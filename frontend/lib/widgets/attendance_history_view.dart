import 'package:flutter/material.dart';

import '../utils/manila_time.dart';
import 'app_ui.dart';
import 'date_filter_bar.dart';

/// A student's attendance, newest day first, grouped by month, with a date
/// filter and three counts above it.
///
/// The student's own Attendance screen and the parent's view of a child are
/// this one widget, so the two can never drift apart: a fix or a new column
/// lands in both at once. Only where the records come from, and a few words,
/// differ.
class AttendanceHistoryView extends StatefulWidget {
  /// Fetches the records (the "attendance" list the API returns).
  final Future<List<dynamic>> Function() load;

  /// Whose attendance this is, shown at the top.
  final String name;

  /// Profile photo as a data URL, or null for initials.
  final String? photo;

  /// True on the parent's screen, where the wording speaks of "your child".
  final bool forParent;

  /// A line under the name, for example "BSIT · Year 3 · 2023-00123". The
  /// administrator's report uses it; the student and parent leave it empty.
  final String subtitle;

  const AttendanceHistoryView({
    super.key,
    required this.load,
    required this.name,
    this.photo,
    this.forParent = false,
    this.subtitle = '',
  });

  @override
  State<AttendanceHistoryView> createState() => _AttendanceHistoryViewState();
}

class _AttendanceHistoryViewState extends State<AttendanceHistoryView> {
  static const _months = [
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
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  bool _isLoading = true;
  String _error = '';
  List<Map<String, dynamic>> _attendance = [];

  // All dates by default. The counts above the list follow the filter, so
  // "This month" answers "how has this month gone" without the year's total
  // in the way.
  DateFilter _filter = const DateFilter();

  // A student can have years of days. Only the newest cards are built, and
  // the rest arrive 30 at a time, so the page stays quick on a phone. The
  // counts above always cover every day in the chosen dates.
  static const int _pageSize = 30;
  int _shown = _pageSize;

  List<Map<String, dynamic>> get _visible => _attendance
      .where(
        (record) => _filter.matches(ManilaTime.parse(record['attendance_date'])),
      )
      .toList();

  /// Days, not records: two visits on one date are one day.
  int get _visibleDayCount => {
    for (final record in _visible) record['attendance_date']?.toString() ?? '',
  }.where((date) => date.isNotEmpty).length;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final records = await widget.load();
      if (!mounted) return;
      setState(() {
        _attendance = records
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        _shown = _pageSize;
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

  // The server sends Manila time (for example 2026-10-18T22:59:00). It is
  // shown as it is, on any device and in any browser time zone.
  String _formatTime(dynamic value) => ManilaTime.time(value, fallback: '');

  String _status(Map<String, dynamic> record) =>
      record['status']?.toString().toLowerCase() ?? '';

  /// "timeout" is the server's word; a parent reads "Auto timed out".
  String _statusLabel(String status) {
    switch (status) {
      case 'timeout':
        return 'Auto timed out';
      case '':
        return 'Recorded';
      default:
        return status[0].toUpperCase() + status.substring(1);
    }
  }

  /// The same colours as the parent's home screen, so a day that is gold
  /// there is gold here too, and the same for the student and the parent.
  StatusLevel _statusLevel(String status) {
    switch (status) {
      case 'present':
        return StatusLevel.good;
      case 'late':
      case 'timeout':
        return StatusLevel.caution;
      case 'absent':
        return StatusLevel.stop;
      default:
        return StatusLevel.neutral;
    }
  }

  bool _isToday(DateTime? date) {
    if (date == null) return false;
    final now = ManilaTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  // ------------------------------------------------------------------ parts

  Widget _summary() {
    final theme = Theme.of(context);
    // A student can time in and out more than once a day, so these count
    // days, not records: two visits on October 31 are one day.
    Set<String> daysWhere(bool Function(Map<String, dynamic>) test) => {
      for (final record in _visible)
        if (test(record)) record['attendance_date']?.toString() ?? '',
    }..remove('');
    final dayCount = daysWhere((_) => true).length;
    final lateCount = daysWhere((r) => _status(r) == 'late').length;
    final timedOut = daysWhere((r) => _status(r) == 'timeout').length;
    final absent = daysWhere((r) => _status(r) == 'absent').length;

    Widget tile(String label, int value, Color color, IconData icon) {
      return Expanded(
        child: AppPanel(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: AppSpace.sm),
              CountUp(
                value: value,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final caution = StatusTone.forLevel(context, StatusLevel.caution).content;
    final stop = StatusTone.forLevel(context, StatusLevel.stop).content;
    return Row(
      children: [
        tile(
          'Days on campus',
          dayCount - absent,
          theme.colorScheme.primary,
          Icons.event_available_outlined,
        ),
        const SizedBox(width: AppSpace.sm),
        tile('Days late', lateCount, caution, Icons.schedule_rounded),
        const SizedBox(width: AppSpace.sm),
        tile('Days auto timed out', timedOut, caution, Icons.timer_off_outlined),
        // Only when the school has marked a day absent, so most students
        // keep the three tiles that fit a small phone.
        if (absent > 0) ...[
          const SizedBox(width: AppSpace.sm),
          tile('Days absent', absent, stop, Icons.event_busy_outlined),
        ],
      ],
    );
  }

  Widget _monthLabel(DateTime date) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg, bottom: AppSpace.sm),
      child: Text(
        '${_months[date.month - 1]} ${date.year}',
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _timeBlock(String label, String value, String empty) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          borderRadius: BorderRadius.circular(AppRadius.block),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value.isEmpty ? empty : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: value.isEmpty ? theme.colorScheme.onSurfaceVariant : null,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dayCard(Map<String, dynamic> record) {
    final theme = Theme.of(context);
    final date = ManilaTime.parse(record['attendance_date']);
    final status = _status(record);
    final level = _statusLevel(status);
    final tone = StatusTone.forLevel(context, level);
    final campus = record['campus_name']?.toString() ?? '';
    final today = _isToday(date);
    final stillInside = today && record['time_out'] == null;

    return AppPanel(
      accent: level == StatusLevel.neutral || level == StatusLevel.good
          ? null
          : tone.content,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date == null
                          ? 'Unknown date'
                          : today
                          ? 'Today'
                          : _weekdays[date.weekday - 1],
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      ManilaTime.longDate(
                        record['attendance_date'],
                        fallback: '',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              StatusBadge(label: _statusLabel(status), tone: tone),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              _timeBlock('Time in', _formatTime(record['time_in']), '—'),
              const SizedBox(width: AppSpace.sm),
              _timeBlock(
                'Time out',
                _formatTime(record['time_out']),
                stillInside ? 'Still inside' : '—',
              ),
            ],
          ),
          if ((record['correction_remarks'] ?? '').toString().trim().isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.edit_note_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    'Corrected: ${record['correction_remarks'].toString().trim()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (campus.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    campus,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The newest [_shown] days, with a month heading wherever the month
  /// changes. On a wide screen the cards sit two to a row.
  List<Widget> _days(double width) {
    final widgets = <Widget>[];
    final records = _visible.take(_shown).toList();
    final twoColumns = width >= 640;
    const gap = AppSpace.sm;
    final cardWidth = twoColumns ? (width - gap) / 2 : width;

    var order = 3;
    String? lastMonth;
    var group = <Widget>[];

    void flush() {
      if (group.isEmpty) return;
      widgets.add(
        Wrap(spacing: gap, runSpacing: gap, children: List.of(group)),
      );
      group = <Widget>[];
    }

    for (final record in records) {
      final date = ManilaTime.parse(record['attendance_date']);
      final month = date == null ? null : '${date.year}-${date.month}';
      if (date != null && month != lastMonth) {
        flush();
        widgets.add(Reveal(order: order, child: _monthLabel(date)));
        lastMonth = month;
      }
      group.add(
        SizedBox(
          width: cardWidth,
          child: Reveal(order: order++, child: _dayCard(record)),
        ),
      );
    }
    flush();
    return widgets;
  }

  Widget _header() {
    final theme = Theme.of(context);
    return Row(
      children: [
        ProfileAvatar(name: widget.name, radius: 24, photo: widget.photo),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              Text(
                widget.subtitle.isEmpty
                    ? 'Attendance history'
                    : widget.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load attendance',
        message: 'Unable to connect to the server. Please try again.',
        action: FilledButton.icon(
          onPressed: _loadAttendance,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAttendance,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final padding = constraints.maxWidth < 400
              ? AppSpace.lg
              : AppSpace.xl;
          final width = (constraints.maxWidth - padding * 2).clamp(
            0.0,
            960.0,
          );
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(padding),
            children: [
              Center(
                child: SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Reveal(order: 0, child: _header()),
                      const SizedBox(height: AppSpace.lg),
                      if (_attendance.isEmpty)
                        Reveal(
                          order: 1,
                          child: AppPanel(
                            padding: const EdgeInsets.symmetric(
                              vertical: AppSpace.lg,
                            ),
                            child: EmptyState(
                              icon: Icons.event_busy_outlined,
                              title: 'No attendance records yet',
                              message: widget.forParent
                                  ? 'Each day your child times in at a '
                                        'campus will appear here.'
                                  : 'Each day you time in at a campus will '
                                        'appear here.',
                            ),
                          ),
                        )
                      else ...[
                        Reveal(
                          order: 1,
                          child: DateFilterBar(
                            filter: _filter,
                            noun: 'day',
                            resultCount: _visibleDayCount,
                            onChanged: (value) => setState(() {
                              _filter = value;
                              _shown = _pageSize;
                            }),
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        if (_visible.isEmpty)
                          const AppPanel(
                            padding: EdgeInsets.symmetric(
                              vertical: AppSpace.lg,
                            ),
                            child: EmptyState(
                              icon: Icons.event_busy_outlined,
                              title: 'Nothing for these dates',
                              message:
                                  'Choose other dates, or All to see every day.',
                            ),
                          )
                        else ...[
                          Reveal(order: 2, child: _summary()),
                          ..._days(width),
                          if (_visible.length > _shown) ...[
                            const SizedBox(height: AppSpace.md),
                            Center(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    setState(() => _shown += _pageSize),
                                icon: const Icon(Icons.expand_more_rounded),
                                label: Text(
                                  'Show older days '
                                  '(${_visible.length - _shown} more)',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
