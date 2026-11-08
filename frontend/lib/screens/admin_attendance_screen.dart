import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/dtr.dart';
import '../utils/manila_time.dart';
import '../widgets/app_ui.dart';
import 'admin_student_report_screen.dart';

/// One day of attendance, for the administrator to check and correct.
///
/// It opens on today (in Manila) rather than on every record ever kept: with
/// a whole school timing in, "everything" is thousands of cards and a slow
/// page. Another day is one tap away, and a student's whole history is in
/// Attendance Reports.
class AdminAttendanceScreen extends StatefulWidget {
  final String token;

  const AdminAttendanceScreen({super.key, required this.token});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> {
  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
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

  /// Rows drawn at first; "Show more" adds this many again. Keeps a busy day
  /// quick to open.
  static const _pageSize = 50;

  bool _isLoading = true;
  String _error = '';
  List<dynamic> _attendance = [];
  // Students who verified the selected day with a photo, by user id.
  Map<String, Map<String, dynamic>> _photos = {};
  late DateTime _selectedDate = _today;
  int _attendanceRequestId = 0;
  int _shown = _pageSize;

  final _searchController = TextEditingController();
  String _search = '';

  static const String _anyDepartment = 'All departments';
  static const String _anyCourse = 'All courses';
  static const String _anyYear = 'All year levels';
  String _selectedDepartment = _anyDepartment;
  String _selectedCourse = _anyCourse;
  String _selectedYear = _anyYear;

  DateTime get _today {
    final now = ManilaTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isToday => _sameDay(_selectedDate, _today);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // YYYY-MM-DD, with no time zone conversion.
  String _dateToString(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  String _dayTitle(DateTime date) =>
      '${_weekdays[date.weekday - 1]}, ${_months[date.month - 1]} ${date.day}, '
      '${date.year}';

  Future<void> _loadAttendance() async {
    final requestId = ++_attendanceRequestId;
    setState(() {
      _isLoading = true;
      _error = '';
      _shown = _pageSize;
    });
    try {
      final result = await ApiService.getAdminAttendance(
        token: widget.token,
        date: _dateToString(_selectedDate),
      );
      if (!mounted || requestId != _attendanceRequestId) return;
      setState(() {
        _attendance = result['attendance'] ?? [];
        _isLoading = false;
      });
      _loadPhotos(requestId);
    } catch (error) {
      if (!mounted || requestId != _attendanceRequestId) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  // Optional: the day still loads if the photos cannot be read.
  Future<void> _loadPhotos(int requestId) async {
    try {
      final result = await ApiService.getAdminPhotos(
        token: widget.token,
        date: _dateToString(_selectedDate),
      );
      if (!mounted || requestId != _attendanceRequestId) return;
      final map = <String, Map<String, dynamic>>{};
      for (final item in (result['photos'] as List? ?? [])) {
        final row = Map<String, dynamic>.from(item as Map);
        map[row['user_id'].toString()] = row;
      }
      setState(() => _photos = map);
    } catch (_) {
      if (!mounted || requestId != _attendanceRequestId) return;
      setState(() => _photos = {});
    }
  }

  Future<void> _showPhoto(dynamic record) async {
    final userId = record['user_id']?.toString() ?? '';
    final date = _dateToString(_selectedDate);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text((record['full_name'] ?? 'Verification photo').toString()),
        content: FutureBuilder<Map<String, dynamic>>(
          future: ApiService.getAdminPhoto(
            token: widget.token,
            userId: userId,
            date: date,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return Text(
                snapshot.error.toString().replaceFirst('Exception: ', ''),
              );
            }
            final data = snapshot.data ?? {};
            final photo = data['photo']?.toString();
            final caption = [
              'Taken ${_formatTime(data['captured_at']?.toString())}',
              if (data['campus_name'] != null) 'at ${data['campus_name']}',
            ].join(' ');
            return SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (photo != null && photo.contains(','))
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        base64Decode(photo.split(',').last),
                        fit: BoxFit.contain,
                      ),
                    )
                  else
                    const Text(
                      'The image was removed after 30 days. The day stays verified.',
                    ),
                  const SizedBox(height: 8),
                  Text(caption),
                  const SizedBox(height: 4),
                  const Text(
                    'The location was checked by the server when the photo was taken.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _goToDay(DateTime day) {
    if (day.isAfter(_today)) return;
    setState(() => _selectedDate = day);
    _loadAttendance();
  }

  Future<void> _pickDate() async {
    // Manila time, so "today" in the picker is the school's today whatever
    // time zone the device is set to.
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: _today,
    );
    if (!mounted || picked == null) return;
    _goToDay(DateTime(picked.year, picked.month, picked.day));
  }

  // ── filtering ────────────────────────────────────────────────────

  /// The choices a filter offers, taken from the day's records, so it never
  /// offers a department, course or year that would show nothing.
  List<String> _optionsFor(String field, {List<dynamic>? within}) {
    final values = (within ?? _attendance)
        .map((record) => (record[field] ?? '').toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    values.sort((left, right) {
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      return left.toUpperCase().compareTo(right.toUpperCase());
    });
    return values;
  }

  String _safeValue(String selected, String fallback, List<String> options) =>
      options.contains(selected) ? selected : fallback;

  bool _matches(dynamic record, String field, String chosen, String any) =>
      chosen == any || (record[field] ?? '').toString().trim() == chosen;

  bool _matchesSearch(dynamic record) {
    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return true;
    return '${record['full_name'] ?? ''} ${record['id_number'] ?? ''}'
        .toLowerCase()
        .contains(query);
  }

  // ── formatting ───────────────────────────────────────────────────

  String _formatTime(String? timeStr) {
    // The server sends the time as text already in Manila time.
    final manila = ManilaTime.time(timeStr, fallback: '');
    if (manila.isNotEmpty) return manila;
    final time = _timeForEditing(timeStr);
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(time);
    if (match == null) return '';
    final hour24 = int.tryParse(match.group(1)!);
    if (hour24 == null || hour24 > 23) return '';
    final hour = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour:${match.group(2)} ${hour24 >= 12 ? 'PM' : 'AM'}';
  }

  String _timeForEditing(String? value) {
    if (value == null || value.isEmpty) return '';
    final match = RegExp(r'(?:T|\s|^)(\d{2}):(\d{2})').firstMatch(value.trim());
    if (match == null) return '';
    final hour = int.tryParse(match.group(1)!);
    if (hour == null || hour > 23) return '';
    return '${match.group(1)}:${match.group(2)}';
  }

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

  String _status(dynamic record) =>
      (record['status'] ?? '').toString().toLowerCase();

  // ── editing ──────────────────────────────────────────────────────

  /// The time part of a stored value, as a time of day (null if there is none).
  TimeOfDay? _timeOfDay(String? value) {
    final hhmm = _timeForEditing(value);
    if (hhmm.isEmpty) return null;
    final parts = hhmm.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  /// 7:30 AM, the way people read a clock.
  String _clock(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.period == DayPeriod.am ? 'AM' : 'PM'}';
  }

  /// 07:30, the way the server stores it.
  String _hhmm(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;

  Future<void> _editRecord(dynamic record) async {
    final originalIn = _timeOfDay(record['time_in']?.toString());
    final originalOut = _timeOfDay(record['time_out']?.toString());
    TimeOfDay? timeIn = originalIn;
    TimeOfDay? timeOut = originalOut;
    final remarksController = TextEditingController();
    // Late no longer exists. An old record that was marked late is shown as
    // present, and saving the correction keeps it that way.
    const statuses = ['present', 'absent', 'timeout'];
    var selectedStatus = statuses.contains(_status(record))
        ? _status(record)
        : 'present';
    var problem = '';

    String cleanRemarks() =>
        remarksController.text.trim().replaceAll(RegExp(r'\s+'), ' ');

    // Checked before anything is sent: a time out before the time in, or a
    // correction with no reason given.
    String check() {
      if (timeIn != null &&
          timeOut != null &&
          _minutes(timeOut!) <= _minutes(timeIn!)) {
        return 'Time out must be later than time in.';
      }
      if (cleanRemarks().length < 3) {
        return 'Write the reason for this correction in Remarks.';
      }
      return '';
    }

    // A tap-to-pick field that shows 7:30 AM. The picker always uses
    // AM / PM, whatever the phone or browser is set to.
    Widget timeField({
      required BuildContext dialogContext,
      required String label,
      required IconData icon,
      required TimeOfDay? value,
      required String emptyText,
      required ValueChanged<TimeOfDay> onPicked,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () async {
          final picked = await showTimePicker(
            context: dialogContext,
            initialTime: value ?? const TimeOfDay(hour: 7, minute: 30),
            helpText: label.toUpperCase(),
            initialEntryMode: TimePickerEntryMode.input,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(alwaysUse24HourFormat: false),
              child: child!,
            ),
          );
          if (picked != null) onPicked(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            prefixIcon: Icon(icon),
            isDense: true,
          ),
          child: Text(
            value == null ? emptyText : _clock(value),
            style: value == null
                ? TextStyle(
                    color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  )
                : const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
          ),
        ),
      );
    }

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) {
          final theme = Theme.of(dialogContext);
          final narrow = MediaQuery.sizeOf(dialogContext).width < 420;
          final inField = timeField(
            dialogContext: dialogContext,
            label: 'Time in',
            icon: Icons.login_rounded,
            value: timeIn,
            emptyText: 'Not set',
            onPicked: (t) => setStateDialog(() {
              timeIn = t;
              problem = '';
            }),
          );
          final outField = timeField(
            dialogContext: dialogContext,
            label: 'Time out',
            icon: Icons.logout_rounded,
            value: timeOut,
            emptyText: 'Still inside',
            onPicked: (t) => setStateDialog(() {
              timeOut = t;
              problem = '';
            }),
          );
          return AlertDialog(
            title: Text(record['full_name']?.toString() ?? 'Edit record'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        ManilaTime.longDate(
                          record['attendance_date'],
                          fallback: '',
                        ),
                        record['campus_name']?.toString() ?? '',
                      ].where((p) => p.isNotEmpty).join('  ·  '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpace.lg),
                    // Side by side on a laptop, one above the other on a
                    // small phone so "12:45 PM" is never cut off.
                    if (narrow) ...[
                      inField,
                      const SizedBox(height: AppSpace.sm),
                      outField,
                    ] else
                      Row(
                        children: [
                          Expanded(child: inField),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(child: outField),
                        ],
                      ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      'Tap a time to change it. Manila time.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (timeIn != originalIn || timeOut != originalOut)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setStateDialog(() {
                            timeIn = originalIn;
                            timeOut = originalOut;
                            problem = '';
                          }),
                          icon: const Icon(Icons.undo_rounded, size: 16),
                          label: const Text('Undo time changes'),
                        ),
                      ),
                    const SizedBox(height: AppSpace.lg),
                    Text(
                      'Status',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Wrap(
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.sm,
                      children: [
                        for (final s in statuses)
                          ChoiceChip(
                            label: Text(_statusLabel(s)),
                            selected: selectedStatus == s,
                            onSelected: (_) =>
                                setStateDialog(() => selectedStatus = s),
                          ),
                      ],
                    ),
                    // Marking a day absent keeps the time in on record, so a
                    // time in that should not count (made from home, or by
                    // someone else) is overruled without being erased.
                    if (selectedStatus == 'absent') ...[
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        'The time in stays on record, but this day will '
                        'count as absent.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: StatusTone.forLevel(
                            dialogContext,
                            StatusLevel.stop,
                          ).content,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpace.lg),
                    TextField(
                      controller: remarksController,
                      onChanged: (_) => setStateDialog(() => problem = ''),
                      maxLength: 300,
                      minLines: 2,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Remarks (required)',
                        hintText: 'e.g. Excused, with excuse letter',
                        helperText:
                            'The student and parent will see this reason.',
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (problem.isNotEmpty) ...[
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        problem,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final issue = check();
                  if (issue.isNotEmpty) {
                    setStateDialog(() => problem = issue);
                    return;
                  }
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(dialogContext);
                  final date = record['attendance_date']
                      ?.toString()
                      .substring(0, 10);
                  final remarks = cleanRemarks();
                  navigator.pop();
                  try {
                    final result = await ApiService.correctAttendance(
                      token: widget.token,
                      attendanceId: record['id'].toString(),
                      timeIn: timeIn != null && date != null
                          ? '${date}T${_hhmm(timeIn!)}:00'
                          : null,
                      timeOut: timeOut != null && date != null
                          ? '${date}T${_hhmm(timeOut!)}:00'
                          : null,
                      status: selectedStatus,
                      remarks: remarks,
                    );
                    final warning =
                        (result['notificationWarning'] ?? '').toString();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          warning.isEmpty
                              ? 'Attendance updated. The student and parent '
                                  'were notified.'
                              : warning,
                        ),
                        backgroundColor:
                            warning.isEmpty ? Colors.green : Colors.orange,
                      ),
                    );
                    if (mounted) _loadAttendance();
                  } catch (error) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          error.toString().replaceFirst('Exception: ', ''),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                child: const Text('Save changes'),
              ),
            ],
          );
        },
      ),
    );

    remarksController.dispose();
  }

  // ── parts ────────────────────────────────────────────────────────

  /// The day being shown, with the days either side one tap away.
  Widget _dayBar() {
    final theme = Theme.of(context);
    return AppPanel(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.xs,
        vertical: AppSpace.xs,
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous day',
            onPressed: _isLoading
                ? null
                : () => _goToDay(
                    _selectedDate.subtract(const Duration(days: 1)),
                  ),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.block),
              onTap: _pickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                child: Column(
                  children: [
                    Text(
                      _isToday ? 'Today' : _weekdays[_selectedDate.weekday - 1],
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 13,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _dayTitle(_selectedDate),
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!_isToday)
            TextButton(
              onPressed: _isLoading ? null : () => _goToDay(_today),
              child: const Text('Today'),
            ),
          IconButton(
            tooltip: 'Next day',
            onPressed: _isLoading || _isToday
                ? null
                : () => _goToDay(_selectedDate.add(const Duration(days: 1))),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  /// The day in four numbers: who came, who is still inside, who was marked
  /// absent, and who was timed out by the system. Students, not records: two
  /// visits are one student.
  Widget _summary(List<dynamic> records) {
    final theme = Theme.of(context);
    Set<String> who(bool Function(dynamic) test) => {
      for (final r in records)
        if (test(r)) (r['id_number'] ?? r['full_name'] ?? '').toString(),
    };
    final came = who((_) => true).length;
    final inside = who((r) => r['time_out'] == null).length;
    final absentCount = who((r) => _status(r) == 'absent').length;
    final timedOut = who((r) => _status(r) == 'timeout').length;

    Widget tile(String label, int value, IconData icon, Color color) => AppPanel(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.block),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CountUp(
                  value: value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final good = StatusTone.forLevel(context, StatusLevel.good).content;
    final caution = StatusTone.forLevel(context, StatusLevel.caution).content;
    final stop = StatusTone.forLevel(context, StatusLevel.stop).content;
    final tiles = [
      tile('Students', came, Icons.groups_outlined, theme.colorScheme.primary),
      tile('Still inside', inside, Icons.location_on_outlined, good),
      tile('Absent', absentCount, Icons.event_busy_outlined, stop),
      tile('Auto timed out', timedOut, Icons.timer_off_outlined, caution),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720 ? 4 : 2;
        const gap = AppSpace.sm;
        final width =
            ((constraints.maxWidth - gap * (columns - 1)) / columns).floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: width, child: t)],
        );
      },
    );
  }

  /// One time in, as a single line on a laptop and a short card on a phone.
  // ── one row per student ──────────────────────────────────────────

  /// A student who left and came back has several records on one day. The list
  /// shows one row per student, like a DTR: the first time in, the last time
  /// out (or "Still inside"), the number of visits and the minutes on campus.
  /// The records themselves stay in '_visits' for the correction.
  List<Map<String, dynamic>> _byStudent(List<dynamic> records) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final item in records) {
      final record = Map<String, dynamic>.from(item as Map);
      final key = (record['user_id'] ?? record['id_number'] ?? record['id'])
          .toString();
      groups.putIfAbsent(key, () => []).add(record);
    }
    final rows = <Map<String, dynamic>>[];
    for (final visits in groups.values) {
      visits.sort(
        (a, b) => (a['time_in'] ?? '').toString().compareTo(
          (b['time_in'] ?? '').toString(),
        ),
      );
      final last = visits.last;
      final open = (last['time_out'] ?? '').toString().isEmpty;
      var minutes = 0;
      for (final visit in visits) {
        final start = ManilaTime.parse(visit['time_in']);
        final end = ManilaTime.parse(visit['time_out']) ??
            (_isToday ? ManilaTime.now() : null);
        if (start != null && end != null && end.isAfter(start)) {
          minutes += end.difference(start).inMinutes;
        }
      }
      final remarks = visits
          .map((v) => (v['correction_remarks'] ?? '').toString().trim())
          .where((r) => r.isNotEmpty)
          .toList();
      rows.add({
        ...last,
        'time_in': visits.first['time_in'],
        'time_out': open ? null : last['time_out'],
        'status': open && _status(last) != 'absent' ? 'present' : last['status'],
        'correction_remarks': remarks.isEmpty ? null : remarks.last,
        '_visits': visits,
        '_minutes': minutes,
      });
    }
    rows.sort(
      (a, b) => (b['time_in'] ?? '').toString().compareTo(
        (a['time_in'] ?? '').toString(),
      ),
    );
    return rows;
  }

  /// One visit: correct it at once. Several: choose the visit first.
  Future<void> _openRow(Map<String, dynamic> row) async {
    final visits = (row['_visits'] as List?)?.cast<Map<String, dynamic>>() ??
        [row];
    if (visits.length == 1) {
      _editRecord(visits.first);
      return;
    }
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              '${row['full_name'] ?? 'Student'}: choose the visit to correct',
              style: Theme.of(sheetContext).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < visits.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(
                  '${_formatTime(visits[i]['time_in']?.toString())}  to  '
                  '${_formatTime(visits[i]['time_out']?.toString()).isEmpty ? 'still inside' : _formatTime(visits[i]['time_out']?.toString())}',
                ),
                subtitle: Text(_statusLabel(_status(visits[i]))),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => Navigator.pop(sheetContext, visits[i]),
              ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) _editRecord(chosen);
  }

  Widget _row(dynamic record, int index, {required bool wide}) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final status = _status(record);
    final level = _statusLevel(status);
    final timeIn = _formatTime(record['time_in']?.toString());
    final timeOutRaw = _formatTime(record['time_out']?.toString());
    final timeOut = timeOutRaw.isEmpty ? 'Still inside' : timeOutRaw;
    final classLine = [
      (record['course'] ?? '').toString(),
      if ((record['year_level'] ?? '').toString().trim().isNotEmpty)
        'Year ${record['year_level']}',
    ].where((p) => p.trim().isNotEmpty).join(' · ');
    final campus = (record['campus_name'] ?? '').toString();
    final name = (record['full_name'] ?? '--').toString();
    final remarks = (record['correction_remarks'] ?? '').toString().trim();
    final Widget? remarksLine = remarks.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.edit_note_rounded, size: 15, color: muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Corrected: $remarks',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: muted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          );
    final badge = StatusBadge(
      label: _statusLabel(status),
      tone: StatusTone.forLevel(context, level),
    );
    final timeStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
      // An absent day keeps its times only as a record of what happened.
      decoration: status == 'absent' ? TextDecoration.lineThrough : null,
      color: status == 'absent' ? muted : null,
    );

    final who = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          (record['id_number'] ?? '').toString(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        if (((record['_visits'] as List?)?.length ?? 1) > 1 ||
            (record['_minutes'] ?? 0) > 0)
          Text(
            [
              if (((record['_visits'] as List?)?.length ?? 1) > 1)
                '${(record['_visits'] as List).length} visits',
              if ((record['_minutes'] ?? 0) > 0)
                formatDuration(record['_minutes'] as int),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        if (_photos.containsKey(record['user_id']?.toString()))
          InkWell(
            onTap: () => _showPhoto(record),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_rounded,
                    size: 15,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Photo verified',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    final Widget body = wide
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
            children: [
              Expanded(flex: 4, child: who),
              Expanded(
                flex: 2,
                child: Text(
                  classLine,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              Expanded(flex: 2, child: Text(timeIn, style: timeStyle)),
              Expanded(
                flex: 2,
                child: Text(
                  timeOut,
                  style: timeOutRaw.isEmpty
                      ? theme.textTheme.bodySmall?.copyWith(
                          color: StatusTone.forLevel(
                            context,
                            StatusLevel.good,
                          ).content,
                          fontWeight: FontWeight.w700,
                        )
                      : timeStyle,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  campus,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(alignment: Alignment.centerLeft, child: badge),
              ),
              Icon(Icons.edit_outlined, size: 18, color: muted),
            ],
              ),
              ?remarksLine,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: who),
                  const SizedBox(width: AppSpace.sm),
                  badge,
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  Icon(Icons.login_rounded, size: 15, color: muted),
                  const SizedBox(width: 4),
                  Text(timeIn, style: timeStyle),
                  const SizedBox(width: AppSpace.lg),
                  Icon(Icons.logout_rounded, size: 15, color: muted),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      timeOut,
                      overflow: TextOverflow.ellipsis,
                      style: timeOutRaw.isEmpty
                          ? theme.textTheme.bodySmall?.copyWith(
                              color: StatusTone.forLevel(
                                context,
                                StatusLevel.good,
                              ).content,
                              fontWeight: FontWeight.w700,
                            )
                          : timeStyle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                [classLine, campus].where((p) => p.isNotEmpty).join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
              ?remarksLine,
            ],
          );

    return AppCard(
      index: index,
      margin: const EdgeInsets.only(bottom: AppSpace.xs + 2),
      child: InkWell(
        onTap: () => _openRow(Map<String, dynamic>.from(record as Map)),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.md,
          ),
          child: body,
        ),
      ),
    );
  }

  /// The column names above the rows, on a laptop.
  Widget _tableHeader() {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg + 18,
        AppSpace.sm,
      ),
      child: Row(
        children: [
          Expanded(flex: 4, child: Text('STUDENT', style: style)),
          Expanded(flex: 2, child: Text('CLASS', style: style)),
          Expanded(flex: 2, child: Text('TIME IN', style: style)),
          Expanded(flex: 2, child: Text('TIME OUT', style: style)),
          Expanded(flex: 2, child: Text('CAMPUS', style: style)),
          Expanded(flex: 2, child: Text('STATUS', style: style)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Each filter is built from what the one before it leaves, so a course
    // outside the chosen department is never offered.
    final departmentOptions = _optionsFor('department');
    final department = _safeValue(
      _selectedDepartment,
      _anyDepartment,
      departmentOptions,
    );
    final inDepartment = _attendance
        .where((r) => _matches(r, 'department', department, _anyDepartment))
        .toList();
    final courseOptions = _optionsFor('course', within: inDepartment);
    final course = _safeValue(_selectedCourse, _anyCourse, courseOptions);
    final inCourse = inDepartment
        .where((r) => _matches(r, 'course', course, _anyCourse))
        .toList();
    final yearOptions = _optionsFor('year_level', within: inCourse);
    final year = _safeValue(_selectedYear, _anyYear, yearOptions);

    final filtered = inCourse
        .where((r) => _matches(r, 'year_level', year, _anyYear))
        .toList();
    final visible = _byStudent(filtered.where(_matchesSearch).toList());
    final shown = visible.take(_shown).toList();

    final search = TextField(
      controller: _searchController,
      onChanged: (value) => setState(() {
        _search = value;
        _shown = _pageSize;
      }),
      decoration: InputDecoration(
        hintText: 'Search name or student number',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.block),
        ),
        suffixIcon: _search.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.clear),
                onPressed: () => setState(() {
                  _search = '';
                  _searchController.clear();
                }),
              ),
      ),
    );

    final filters = FilterBar(
      children: [
        if (departmentOptions.isNotEmpty)
          FilterDropdown(
            value: department,
            options: [_anyDepartment, ...departmentOptions],
            icon: Icons.apartment_outlined,
            onChanged: (chosen) => setState(() {
              _selectedDepartment = chosen;
              _selectedCourse = _anyCourse;
              _selectedYear = _anyYear;
              _shown = _pageSize;
            }),
          ),
        FilterDropdown(
          value: course,
          options: [_anyCourse, ...courseOptions],
          icon: Icons.school_outlined,
          onChanged: (chosen) => setState(() {
            _selectedCourse = chosen;
            _selectedYear = _anyYear;
            _shown = _pageSize;
          }),
        ),
        FilterDropdown(
          value: year,
          options: [_anyYear, ...yearOptions],
          icon: Icons.format_list_numbered_rounded,
          onChanged: (chosen) => setState(() {
            _selectedYear = chosen;
            _shown = _pageSize;
          }),
        ),
      ],
    );

    Widget list(bool wide) {
      if (_isLoading) {
        return const Padding(
          padding: EdgeInsets.only(top: 60),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (_error.isNotEmpty) {
        return EmptyState(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load the records',
          message: _error,
          action: OutlinedButton(
            onPressed: _loadAttendance,
            child: const Text('Try again'),
          ),
        );
      }
      if (visible.isEmpty) {
        return EmptyState(
          icon: _attendance.isEmpty
              ? Icons.event_available_outlined
              : Icons.search_off_rounded,
          title: _attendance.isEmpty
              ? (_isToday ? 'No one has timed in yet' : 'No one timed in')
              : 'No records match',
          message: _attendance.isEmpty
              ? 'Records appear here as students time in.'
              : 'Clear the search or the filters to see everyone.',
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Text(
              '${visible.length} ${visible.length == 1 ? 'student' : 'students'}'
              '  ·  tap one to correct a record',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (wide) _tableHeader(),
          for (var i = 0; i < shown.length; i++) _row(shown[i], i, wide: wide),
          if (visible.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Center(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _shown += _pageSize),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(
                    'Show more (${visible.length - shown.length} left)',
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily records'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadAttendance,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    AdminStudentReportScreen(token: widget.token),
              ),
            ),
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'Attendance reports',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadAttendance,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pad = constraints.maxWidth < 400 ? AppSpace.md : AppSpace.xl;
            final wide = constraints.maxWidth >= 900;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(pad, AppSpace.md, pad, AppSpace.xl),
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Reveal(order: 0, child: _dayBar()),
                        const SizedBox(height: AppSpace.md),
                        if (!_isLoading && _error.isEmpty) ...[
                          Reveal(order: 1, child: _summary(filtered)),
                          const SizedBox(height: AppSpace.md),
                        ],
                        Reveal(order: 2, child: search),
                        const SizedBox(height: AppSpace.sm),
                        Reveal(order: 2, child: filters),
                        const SizedBox(height: AppSpace.lg),
                        list(wide),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
