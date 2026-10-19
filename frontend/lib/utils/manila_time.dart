/// Everything the app shows about time is Philippine time (Asia/Manila, UTC+8,
/// no daylight saving), whatever timezone the phone or browser is set to.
///
/// The DateTime values returned here are "wall clock" values: read `.hour`,
/// `.minute`, `.day` ... straight from them. Do not call `.toLocal()` or
/// `.toUtc()` on them.
class ManilaTime {
  ManilaTime._();

  static const Duration _offset = Duration(hours: 8);

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static const List<String> _longMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// The current Manila time.
  static DateTime now() => _wallClock(DateTime.now().toUtc().add(_offset));

  /// Reads a time sent by the API.
  ///
  /// - `2026-10-18T14:59:00Z` or `...+08:00` (a real moment in time) is
  ///   converted to Manila time.
  /// - `2026-10-18T22:59:00` or `2026-10-18 22:59:00` (no zone) is already
  ///   Manila time and is kept as it is. The server sends attendance time in
  ///   and time out this way.
  /// - `2026-10-18` (a date only) is kept as it is.
  ///
  /// Returns null when the value is empty or not a date.
  static DateTime? parse(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return _wallClock(parsed.isUtc ? parsed.add(_offset) : parsed);
  }

  // Drops the UTC flag so the value is only a set of Manila wall clock fields.
  static DateTime _wallClock(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
    value.hour,
    value.minute,
    value.second,
  );

  /// "10:59 PM", or [fallback] when the value cannot be read.
  static String time(dynamic value, {String fallback = 'N/A'}) {
    final date = parse(value);
    if (date == null) return fallback;
    return clock(date);
  }

  /// "10:59 PM" from a Manila wall clock DateTime.
  static String clock(DateTime date) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';
  }

  /// "October 18, 2026", or [fallback] when the value cannot be read.
  static String longDate(dynamic value, {String fallback = 'N/A'}) {
    final date = parse(value);
    if (date == null) return fallback;
    return '${_longMonths[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// "Oct 18, 2026", or [fallback] when the value cannot be read.
  static String shortDate(dynamic value, {String fallback = 'N/A'}) {
    final date = parse(value);
    if (date == null) return fallback;
    return '${_months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// "Oct 18, 2026 • 10:59 PM", or [fallback] when the value cannot be read.
  static String dateTime(dynamic value, {String fallback = ''}) {
    final date = parse(value);
    if (date == null) return fallback;
    return '${_months[date.month - 1]} ${date.day}, ${date.year} • ${clock(date)}';
  }
}
