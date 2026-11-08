import 'manila_time.dart';

/// Daily time record (DTR).
///
/// A student can time in and out more than once a day: the app times them in
/// when they are inside the campus and out when they leave. The DTR joins those
/// records into one row per day:
///   - [firstIn]  the first time in of the day
///   - [lastOut]  the last time out of the day (null while still inside)
///   - [minutes]  minutes on campus: the sum of every time in to time out, so
///                the time spent outside between two visits is not counted
///   - [sessions] every time in and time out of that day, in order
///
/// The server builds the same record for the teacher's report
/// (backend/src/services/dtr.js); this file builds it for the student, parent
/// and administrator screens from the plain attendance records they already load.
class DtrSession {
  final DateTime? timeIn;
  final DateTime? timeOut;
  final String status;

  /// The reason an administrator gave when correcting this record, or ''.
  final String remarks;

  const DtrSession({
    this.timeIn,
    this.timeOut,
    this.status = '',
    this.remarks = '',
  });

  factory DtrSession.fromJson(Map<String, dynamic> json) => DtrSession(
    timeIn: ManilaTime.parse(json['time_in']),
    timeOut: ManilaTime.parse(json['time_out']),
    status: json['status']?.toString().toLowerCase() ?? '',
    remarks: json['correction_remarks']?.toString().trim() ?? '',
  );
}

class DtrDay {
  /// "2026-11-04"
  final String date;
  final DateTime? firstIn;
  final DateTime? lastOut;
  final int minutes;
  final bool absent;

  /// True when the last visit of the day has no time out yet.
  final bool stillInside;
  final List<DtrSession> sessions;

  const DtrDay({
    required this.date,
    required this.firstIn,
    required this.lastOut,
    required this.minutes,
    required this.absent,
    required this.stillInside,
    required this.sessions,
  });

  /// A date with no time in at all, so the DTR shows every day of the month.
  const DtrDay.empty(this.date)
    : firstIn = null,
      lastOut = null,
      minutes = 0,
      absent = false,
      stillInside = false,
      sessions = const [];

  DateTime? get day => ManilaTime.parse(date);

  /// True for a day that has at least one time in.
  bool get hasRecord => sessions.isNotEmpty;

  /// True when an administrator corrected one of the day's records.
  bool get hasRemarks => sessions.any((session) => session.remarks.isNotEmpty);

  /// A day from the teacher report (the server already added the minutes up).
  factory DtrDay.fromJson(Map<String, dynamic> json) {
    final sessions = [
      for (final item in (json['sessions'] as List<dynamic>? ?? const []))
        DtrSession.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
    final today = _dateKey(ManilaTime.now());
    final date = json['date']?.toString() ?? '';
    return DtrDay(
      date: date,
      firstIn: ManilaTime.parse(json['first_in']),
      lastOut: ManilaTime.parse(json['last_out']),
      minutes: (json['minutes'] as num?)?.toInt() ?? 0,
      absent: json['absent'] == true,
      stillInside:
          date == today && sessions.isNotEmpty && sessions.last.timeOut == null,
      sessions: sessions,
    );
  }
}

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// Builds one [DtrDay] per date from attendance records (the "attendance" list
/// the API returns: attendance_date, time_in, time_out, status). Oldest day
/// first; reverse it to show the newest day first.
List<DtrDay> buildDtrDays(List<Map<String, dynamic>> records) {
  final now = ManilaTime.now();
  final today = _dateKey(now);

  final byDate = <String, List<Map<String, dynamic>>>{};
  for (final record in records) {
    final date = record['attendance_date']?.toString() ?? '';
    if (date.isEmpty || ManilaTime.parse(record['time_in']) == null) continue;
    byDate.putIfAbsent(date, () => []).add(record);
  }

  final days = <DtrDay>[];
  for (final entry in byDate.entries) {
    final list = entry.value
      ..sort((a, b) {
        final first = ManilaTime.parse(a['time_in']);
        final second = ManilaTime.parse(b['time_in']);
        if (first == null || second == null) return 0;
        return first.compareTo(second);
      });

    var minutes = 0;
    final sessions = <DtrSession>[];
    for (final record in list) {
      final timeIn = ManilaTime.parse(record['time_in']);
      final timeOut = ManilaTime.parse(record['time_out']);
      final status = record['status']?.toString().toLowerCase() ?? '';
      sessions.add(
        DtrSession(
          timeIn: timeIn,
          timeOut: timeOut,
          status: status,
          remarks: record['correction_remarks']?.toString().trim() ?? '',
        ),
      );
      if (status == 'absent' || timeIn == null) continue;
      // A visit that is still open counts until now, but only today. An old
      // record with no time out has no known end, so it adds nothing.
      final end = timeOut ?? (entry.key == today ? now : null);
      if (end != null && end.isAfter(timeIn)) {
        minutes += (end.difference(timeIn).inSeconds / 60).round();
      }
    }

    final allAbsent = sessions.every((session) => session.status == 'absent');
    days.add(
      DtrDay(
        date: entry.key,
        firstIn: sessions.first.timeIn,
        lastOut: sessions.last.timeOut,
        minutes: allAbsent ? 0 : minutes,
        absent: allAbsent,
        stillInside:
            entry.key == today &&
            sessions.isNotEmpty &&
            sessions.last.timeOut == null,
        sessions: sessions,
      ),
    );
  }

  days.sort((a, b) => a.date.compareTo(b.date));
  return days;
}

/// "8 h 05 min", "45 min", or "—" when nothing was recorded.
String formatDuration(int minutes) {
  if (minutes <= 0) return '—';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  return '$hours h ${rest.toString().padLeft(2, '0')} min';
}

/// Every date from [from] to [to] (never past today), oldest first, using the
/// day in [days] when there is one and an empty day otherwise, so the DTR reads
/// like a full calendar. When [from] is null it starts on the first day of the
/// month of the oldest day in [days]; with no days and no [from] nothing is
/// added.
List<DtrDay> fillCalendar(List<DtrDay> days, {DateTime? from, DateTime? to}) {
  final byDate = {for (final day in days) day.date: day};
  DateTime? start = from;
  if (start == null) {
    DateTime? oldest;
    for (final day in days) {
      final value = day.day;
      if (value != null && (oldest == null || value.isBefore(oldest))) {
        oldest = value;
      }
    }
    if (oldest == null) return days;
    start = DateTime(oldest.year, oldest.month, 1);
  }
  final now = ManilaTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var end = to == null ? today : DateTime(to.year, to.month, to.day);
  if (end.isAfter(today)) end = today;

  final result = <DtrDay>[];
  for (
    var date = DateTime(start.year, start.month, start.day);
    !date.isAfter(end);
    date = DateTime(date.year, date.month, date.day + 1)
  ) {
    final key = _dateKey(date);
    result.add(byDate[key] ?? DtrDay.empty(key));
  }
  return result;
}
