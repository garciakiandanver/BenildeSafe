import 'package:flutter/material.dart';

import '../utils/dtr.dart';
import '../utils/manila_time.dart';
import 'app_ui.dart';
import 'date_filter_bar.dart';
import 'dtr_table.dart';

/// A student's attendance as a daily time record (DTR), newest day first,
/// one table for each month, with a date filter and counts above it.
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

  /// One entry per day, oldest first. Two visits on one date are one day.
  List<DtrDay> get _visibleDays => buildDtrDays(_visible);

  int get _visibleDayCount => _visibleDays.length;

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

  // ------------------------------------------------------------------ parts

  Widget _summary() {
    final theme = Theme.of(context);
    final days = _visibleDays;
    final absent = days.where((day) => day.absent).length;
    final onCampus = days.length - absent;
    final totalMinutes = days.fold<int>(0, (sum, day) => sum + day.minutes);

    Widget tile(String label, Widget value, Color color, IconData icon) {
      return Expanded(
        child: AppPanel(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: AppSpace.sm),
              value,
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

    final valueStyle = theme.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1,
    );
    final stop = StatusTone.forLevel(context, StatusLevel.stop).content;
    return Row(
      children: [
        tile(
          'Days on campus',
          CountUp(value: onCampus, style: valueStyle),
          theme.colorScheme.primary,
          Icons.event_available_outlined,
        ),
        const SizedBox(width: AppSpace.sm),
        tile(
          'Hours on campus',
          Text(formatDuration(totalMinutes), style: valueStyle),
          theme.colorScheme.primary,
          Icons.schedule_rounded,
        ),
        // Only when the school has marked a day absent, so most students
        // keep the two tiles that fit a small phone.
        if (absent > 0) ...[
          const SizedBox(width: AppSpace.sm),
          tile(
            'Days absent',
            CountUp(value: absent, style: valueStyle),
            stop,
            Icons.event_busy_outlined,
          ),
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

  /// Each month is a heading and a DTR table, newest day first. Only the newest
  /// [_shown] days are built; the rest arrive 30 at a time.
  List<Widget> _days(double width) {
    final widgets = <Widget>[];
    final days = _visibleDays.reversed.take(_shown).toList();

    var order = 3;
    String? lastMonth;
    var group = <DtrDay>[];

    void flush() {
      if (group.isEmpty) return;
      widgets.add(Reveal(order: order++, child: DtrTable(days: List.of(group))));
      group = <DtrDay>[];
    }

    for (final day in days) {
      final date = day.day;
      final month = date == null ? null : '${date.year}-${date.month}';
      if (date != null && month != lastMonth) {
        flush();
        widgets.add(Reveal(order: order, child: _monthLabel(date)));
        lastMonth = month;
      }
      group.add(day);
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
                                  ? 'The days your child is on campus will '
                                        'appear here.'
                                  : 'The days you are on campus will appear '
                                        'here.',
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
                          if (_visibleDays.length > _shown) ...[
                            const SizedBox(height: AppSpace.md),
                            Center(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    setState(() => _shown += _pageSize),
                                icon: const Icon(Icons.expand_more_rounded),
                                label: Text(
                                  'Show older days '
                                  '(${_visibleDays.length - _shown} more)',
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
