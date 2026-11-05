import 'package:flutter/material.dart';

import '../utils/dtr.dart';
import '../utils/manila_time.dart';
import 'app_ui.dart';

/// One month of a daily time record (DTR): a row for every day with the first
/// time in, the last time out and the hours on campus, like the paper DTR.
/// Tap a day with more than one visit to see each time in and time out.
///
/// The student's own history, the parent's view of a child, the administrator's
/// student report and the teacher's report all use this one table.
class DtrTable extends StatefulWidget {
  /// The days to show, in the order they should appear.
  final List<DtrDay> days;

  const DtrTable({super.key, required this.days});

  @override
  State<DtrTable> createState() => _DtrTableState();
}

class _DtrTableState extends State<DtrTable> {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  final Set<String> _open = {};

  Widget _cell(
    String text, {
    required int flex,
    TextStyle? style,
    TextAlign align = TextAlign.left,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: style,
      ),
    );
  }

  Widget _header() {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      child: Row(
        children: [
          _cell('Date', flex: 3, style: style),
          _cell('Time in', flex: 3, style: style),
          _cell('Time out', flex: 3, style: style),
          _cell('Hours', flex: 3, style: style, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _row(DtrDay day) {
    final theme = Theme.of(context);
    final date = day.day;
    final label = date == null
        ? day.date
        : '${_weekdays[date.weekday - 1]} ${date.day}';
    final muted = theme.colorScheme.onSurfaceVariant;
    final strong = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final visits = day.sessions.length;
    final expandable = visits > 1 || day.hasRemarks;
    final expanded = _open.contains(day.date);

    final timeOut = day.absent
        ? 'Absent'
        : day.stillInside
        ? 'Still inside'
        : day.lastOut == null
        ? '—'
        : ManilaTime.clock(day.lastOut!);

    final summary = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: strong,
                  ),
                ),
                if (day.hasRemarks) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.edit_note_rounded, size: 16, color: muted),
                ],
                if (expandable) ...[
                  const SizedBox(width: 2),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                    color: muted,
                  ),
                ],
              ],
            ),
          ),
          _cell(
            day.firstIn == null ? '—' : ManilaTime.clock(day.firstIn!),
            flex: 3,
            style: strong,
          ),
          _cell(
            timeOut,
            flex: 3,
            style: strong?.copyWith(
              color: day.stillInside || day.absent ? muted : null,
              fontWeight: day.stillInside || day.absent
                  ? FontWeight.w500
                  : FontWeight.w700,
            ),
          ),
          _cell(
            day.absent ? '—' : formatDuration(day.minutes),
            flex: 3,
            style: strong,
            align: TextAlign.right,
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        expandable
            ? InkWell(
                onTap: () => setState(() {
                  if (!_open.add(day.date)) _open.remove(day.date);
                }),
                child: summary,
              )
            : summary,
        if (expandable && expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.md,
              0,
              AppSpace.md,
              AppSpace.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < day.sessions.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Visit ${i + 1}:  '
                      '${day.sessions[i].timeIn == null ? '—' : ManilaTime.clock(day.sessions[i].timeIn!)}'
                      '  to  '
                      '${day.sessions[i].timeOut == null ? 'still inside' : ManilaTime.clock(day.sessions[i].timeOut!)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  ),
                  if (day.sessions[i].remarks.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Corrected: ${day.sessions[i].remarks}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.5)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          for (final day in widget.days) _row(day),
        ],
      ),
    );
  }
}
