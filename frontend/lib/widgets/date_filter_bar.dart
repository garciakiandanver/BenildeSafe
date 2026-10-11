import 'package:flutter/material.dart';

enum DatePreset { all, today, week, month, custom }

/// A date filter shared by the Attendance History and Notifications screens.
class DateFilter {
  final DatePreset preset;
  final DateTimeRange? customRange;

  const DateFilter({this.preset = DatePreset.all, this.customRange});

  /// The selected dates as whole days, or null when the filter is "All".
  DateTimeRange? get range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (preset) {
      case DatePreset.today:
        return DateTimeRange(start: today, end: today);
      case DatePreset.week:
        // Monday to Sunday of the current week.
        final monday = DateTime(
          today.year,
          today.month,
          today.day - (today.weekday - 1),
        );
        return DateTimeRange(
          start: monday,
          end: DateTime(monday.year, monday.month, monday.day + 6),
        );
      case DatePreset.month:
        return DateTimeRange(
          start: DateTime(today.year, today.month, 1),
          end: DateTime(today.year, today.month + 1, 0),
        );
      case DatePreset.custom:
        return customRange;
      case DatePreset.all:
        return null;
    }
  }

  /// True when [value] (shown in the phone's local time) is inside the filter.
  bool matches(DateTime? value) {
    final selected = range;
    if (selected == null) return true;
    if (value == null) return false;
    final local = value.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    return !day.isBefore(selected.start) && !day.isAfter(selected.end);
  }
}

String formatDateRange(DateTimeRange range) {
  const months = [
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
  String one(DateTime d) => '${months[d.month - 1]} ${d.day}, ${d.year}';
  final sameDay =
      range.start.year == range.end.year &&
      range.start.month == range.end.month &&
      range.start.day == range.end.day;
  return sameDay
      ? one(range.start)
      : '${one(range.start)} - ${one(range.end)}';
}

/// Row of filter chips: All, Today, This week, This month, and a date-range
/// picker. [noun] is used in the result count, e.g. "record" or "notification".
class DateFilterBar extends StatelessWidget {
  final DateFilter filter;
  final ValueChanged<DateFilter> onChanged;
  final int? resultCount;
  final String noun;

  const DateFilterBar({
    super.key,
    required this.filter,
    required this.onChanged,
    this.resultCount,
    this.noun = 'record',
  });

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: filter.customRange,
      helpText: 'Filter by date',
    );
    if (picked == null) return;
    onChanged(DateFilter(preset: DatePreset.custom, customRange: picked));
  }

  Widget _chip(String label, DatePreset preset) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: filter.preset == preset,
        onSelected: (_) => onChanged(DateFilter(preset: preset)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final range = filter.range;
    final hasCustom =
        filter.preset == DatePreset.custom && filter.customRange != null;
    final count = resultCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
          child: Row(
            children: [
              _chip('All', DatePreset.all),
              _chip('Today', DatePreset.today),
              _chip('This week', DatePreset.week),
              _chip('This month', DatePreset.month),
              ChoiceChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(
                  hasCustom
                      ? formatDateRange(filter.customRange!)
                      : 'Pick dates',
                ),
                selected: filter.preset == DatePreset.custom,
                onSelected: (_) => _pickCustomRange(context),
              ),
            ],
          ),
        ),
        if (range != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              count == null
                  ? formatDateRange(range)
                  : '${formatDateRange(range)}  •  $count $noun${count == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}