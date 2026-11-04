import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/manila_time.dart';
import 'app_ui.dart';

/// How many students came to campus each day, over the last 7 or 30 days,
/// with the late ones stacked on top. For the admin dashboard.
///
/// One bar per day, because days are separate counts, not a continuous
/// quantity. Two colours with a legend, never colour alone: every bar also
/// answers on hover with the day and both numbers. The two colours were run
/// through a colour-vision check for light and for dark mode.
class AttendanceTrendChart extends StatefulWidget {
  final String token;

  /// Every student in the system, for the share that came ("40%"). Zero
  /// while it is unknown, and then no share is shown.
  final int totalStudents;

  const AttendanceTrendChart({
    super.key,
    required this.token,
    this.totalStudents = 0,
  });

  @override
  State<AttendanceTrendChart> createState() => _AttendanceTrendChartState();
}

class _AttendanceTrendChartState extends State<AttendanceTrendChart> {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
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

  int _days = 7;

  /// Room under the bars for the day labels: the weekday and the date.
  static const double _labelHeight = 32;

  /// Room above the bars for each day's count, on the 7-day view only.
  double get _countSpace => _days <= 7 ? 16.0 : 0.0;
  bool _isLoading = true;
  String _error = '';
  List<_Day> _trend = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final result = await ApiService.getAttendanceTrend(
        token: widget.token,
        days: _days,
      );
      if (!mounted) return;
      setState(() {
        // Sundays are left out: there are no classes, so they would only ever
        // be empty bars between the weeks.
        _trend = (result['trend'] as List<dynamic>? ?? [])
            .map((item) => _Day.fromJson(Map<String, dynamic>.from(item as Map)))
            .where((day) => day.date?.weekday != DateTime.sunday)
            .toList();
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

  void _choose(int days) {
    if (days == _days) return;
    setState(() => _days = days);
    _load();
  }

  // On time and late. Checked for colour-blind separation and contrast:
  // light against a white panel, dark against a dark one.
  Color _onTimeColor(bool dark) =>
      dark ? const Color(0xFF43A574) : const Color(0xFF166F4A);
  Color _lateColor(bool dark) =>
      dark ? const Color(0xFFB9891A) : const Color(0xFFB07D10);

  /// A round top for the scale: 4, 5, 10, 15, 20, 25, 50 ...
  int _niceMax(int value) {
    if (value <= 4) return 4;
    for (final step in [5, 10, 25, 50, 100, 250, 500, 1000]) {
      if (value <= step * 4) return ((value + step - 1) ~/ step) * step;
    }
    return value;
  }

  /// "40%" of all students, or nothing when the total is not known.
  String _share(num count) {
    final total = widget.totalStudents;
    if (total <= 0) return '';
    return ' (${(count * 100 / total).toStringAsFixed(0)}%)';
  }

  String _dayLabel(DateTime date) => '${_weekdays[date.weekday - 1]}, '
      '${_months[date.month - 1]} ${date.day}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPanel(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpace.md,
            runSpacing: AppSpace.sm,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bar_chart_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Text(
                        'Attendance',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Students who timed in, Monday to Saturday',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
                segments: const [
                  ButtonSegment(value: 7, label: Text('7 days')),
                  ButtonSegment(value: 30, label: Text('30 days')),
                ],
                selected: {_days},
                onSelectionChanged: (chosen) => _choose(chosen.first),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          SizedBox(height: 240, child: _body(theme)),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load the chart.',
              style: theme.textTheme.bodyMedium,
            ),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }

    final dark = theme.brightness == Brightness.dark;
    final onTimeColor = _onTimeColor(dark);
    final lateColor = _lateColor(dark);
    final muted = theme.colorScheme.onSurfaceVariant;
    final top = _niceMax(
      _trend.fold<int>(0, (m, d) => d.students > m ? d.students : m),
    );
    final total = _trend.fold<int>(0, (s, d) => s + d.students);
    final lateTotal = _trend.fold<int>(0, (s, d) => s + d.lateCount);
    final average = _trend.isEmpty ? 0.0 : total / _trend.length;
    final today = ManilaTime.now();

    Widget swatch(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The figures worth reading without hovering, and the legend.
        Wrap(
          spacing: AppSpace.lg,
          runSpacing: AppSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${average.toStringAsFixed(1)} a day on average'
              '${_share(average)}  ·  $lateTotal late',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            swatch(onTimeColor, 'On time'),
            swatch(lateColor, 'Late'),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Expanded(
          // 8px of room above the top guide line, so its value is not cut
          // off at the edge of the plot.
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Three guide lines, each at exactly its value, behind
              // the bars. The bottom 32px are the day labels.
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final plot = constraints.maxHeight - _labelHeight;
                    // Clip.none: the top value sits half above the plot and
                    // was being cut off here, which made "4" look like "¬".
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final value in [top, top ~/ 2, 0])
                          Positioned(
                            left: 0,
                            right: 0,
                            // The same scale as the bars, which keep
                            // [_countSpace] free above them for the counts.
                            top: _countSpace +
                                (plot - _countSpace) * (1 - value / top) -
                                8,
                            height: 16,
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 28,
                                  child: Text(
                                    '$value',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: muted,
                                      height: 1,
                                    ),
                                  ),
                                ),
                                // Visible, but quieter than the bars: the
                                // bottom line is the baseline and is
                                // drawn a little stronger.
                                Expanded(
                                  child: Container(
                                    height: value == 0 ? 1.5 : 1,
                                    color: muted.withValues(
                                      alpha: value == 0 ? 0.45 : 0.22,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              Positioned.fill(
                left: 32,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < _trend.length; i++)
                      Expanded(
                        child: _bar(
                          theme,
                          _trend[i],
                          top: top,
                          onTimeColor: onTimeColor,
                          lateColor: lateColor,
                          isToday: _sameDay(_trend[i].date, today),
                          showLabel: _days <= 7 ||
                              i == _trend.length - 1 ||
                              (_trend.length - 1 - i) % 5 == 0,
                        ),
                      ),
                  ],
                ),
              ),
              if (total == 0)
                Center(
                  child: Text(
                    'No one has timed in during these days.',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ),
            ],
          ),
          ),
        ),
      ],
    );
  }

  bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  /// One day: the late part on top of the on-time part, a 2px gap between
  /// them, a rounded top, and the day under it. The whole column answers the
  /// pointer, not just the bar, so a short bar is as easy to hover as a tall
  /// one.
  Widget _bar(
    ThemeData theme,
    _Day day, {
    required int top,
    required Color onTimeColor,
    required Color lateColor,
    required bool isToday,
    required bool showLabel,
  }) {
    final date = day.date;
    final onTimeCount = (day.students - day.lateCount).clamp(0, day.students);
    // "Sat" over "31" for a week; the day of the month alone for 30 days,
    // where there is no room for the weekday.
    final weekday = date == null || _days > 7
        ? ''
        : _weekdays[date.weekday - 1];
    final dayOfMonth = date == null ? '' : '${date.day}';
    final tooltip = date == null
        ? ''
        : '${_dayLabel(date)}${isToday ? ' (today)' : ''}\n'
              '${day.students} ${day.students == 1 ? 'student' : 'students'}'
              '${_share(day.students)}  ·  ${day.lateCount} late';

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 150),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _days <= 7 ? 6 : 1.5),
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final full = constraints.maxHeight;
                  final width = constraints.maxWidth.clamp(0.0, 32.0);
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (context, t, _) {
                      // The 2px gap comes out of the bar's own height, so a
                      // full bar never runs past the top of the plot.
                      final gap = day.lateCount > 0 && onTimeCount > 0 ? 2.0 : 0.0;
                      // On a week, each day's count sits on top of its bar,
                      // so nobody has to read it off the scale. Thirty bars
                      // are too narrow for that; hovering tells instead.
                      // The space is kept on every bar, counted or not, so
                      // all bars and the guide lines share one scale.
                      final showCount = _days <= 7 && day.students > 0;
                      final countSpace = _countSpace;
                      final room = (full - gap - countSpace).clamp(0.0, full);
                      final lateHeight = room * day.lateCount / top * t;
                      final onTimeHeight = room * onTimeCount / top * t;
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          SizedBox(
                              height: countSpace,
                              child: !showCount
                                  ? null
                                  : Opacity(
                                opacity: t.clamp(0.0, 1.0),
                                child: Text(
                                  '${day.students}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: theme.colorScheme.onSurface,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          if (day.lateCount > 0)
                            Container(
                              width: width,
                              height: lateHeight,
                              decoration: BoxDecoration(
                                color: lateColor,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                ),
                              ),
                            ),
                          SizedBox(height: gap),
                          if (onTimeCount > 0)
                            Container(
                              width: width,
                              height: onTimeHeight,
                              decoration: BoxDecoration(
                                color: onTimeColor,
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(day.lateCount > 0 ? 0 : 4),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            SizedBox(
              height: _labelHeight,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: showLabel
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (weekday.isNotEmpty)
                              Text(
                                weekday,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  height: 1.2,
                                ),
                              ),
                            Text(
                              dayOfMonth,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: isToday
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: isToday
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Day {
  final DateTime? date;
  final int students;
  final int lateCount;

  const _Day({
    required this.date,
    required this.students,
    required this.lateCount,
  });

  factory _Day.fromJson(Map<String, dynamic> json) => _Day(
    // "2026-11-02", a Manila date as text.
    date: ManilaTime.parse(json['date']),
    students: (json['students'] as num?)?.toInt() ?? 0,
    lateCount: (json['late'] as num?)?.toInt() ?? 0,
  );
}
