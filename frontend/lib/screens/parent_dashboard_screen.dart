import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import 'child_attendance_screen.dart';
import 'notifications_screen.dart';
import 'login_screen.dart';
import '../widgets/app_ui.dart';
import 'account_settings_screen.dart';
import '../services/profile_state.dart';
import '../services/session_service.dart';
import '../utils/manila_time.dart';

class ParentDashboardScreen extends StatefulWidget {
  final String token;
  final String email;
  final String fullName;
  final String firstName;

  const ParentDashboardScreen({
    super.key,
    required this.token,
    required this.email,
    this.fullName = '',
    this.firstName = '',
  });

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  static const _monthsShort = [
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

  bool _isLoading = true;
  String _error = '';
  List<dynamic> _children = [];
  List<Map<String, dynamic>> _linkRequests = [];
  // Today's status of each child, keyed by student id.
  Map<String, Map<String, dynamic>> _todayByChild = {};
  bool _todayLoaded = false;
  int _selectedNavigationIndex = 0; // 0 = Home, 1 = Children
  int _unreadCount = 0;
  Timer? _notificationTimer;

  String get _displayName =>
      widget.fullName.trim().isNotEmpty ? widget.fullName.trim() : widget.email;

  @override
  void initState() {
    super.initState();
    _releaseKeyboard();
    ProfileState.instance.addListener(_onProfileChanged);
    ProfileState.instance.refresh(widget.token);
    _loadAll();
    // While Home is open, check every 15 seconds for new notifications and
    // for each child's status today, so a time in shows on the child's card
    // without pressing refresh.
    _notificationTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadUnreadCount();
      if (_children.isNotEmpty) _loadTodayStatuses();
    });
  }

  // Coming from the login or change password screen, the browser can keep the
  // old text field focused, so the keyboard pops up on every tap. Let go of it.
  void _releaseKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      TextInput.finishAutofillContext(shouldSave: false);
      SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    });
  }

  String get _firstName =>
      SessionService.resolveFirstName(widget.firstName, widget.fullName);

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ProfileState.instance.removeListener(_onProfileChanged);
    _notificationTimer?.cancel();
    super.dispose();
  }

  // ------------------------------------------------------------------ loading

  Future<void> _loadUnreadCount() async {
    try {
      final result = await ApiService.getNotifications(token: widget.token);
      if (!mounted) return;
      setState(() {
        _unreadCount = (result['unreadCount'] as num?)?.toInt() ?? 0;
      });
    } catch (error) {
      // Stay quiet: this also runs on a timer, so a snackbar would be noisy.
      debugPrint('Unable to load unread notification count: $error');
    }
  }

  Future<void> _loadAll() async {
    _loadUnreadCount();
    try {
      final result = await ApiService.getChildren(token: widget.token);
      if (!mounted) return;
      setState(() {
        _children = result['children'] ?? [];
        _error = '';
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
      return;
    }
    // Extra information: a failure here must not hide the children.
    await Future.wait([_loadLinkRequests(), _loadTodayStatuses()]);
  }

  Future<void> _loadLinkRequests() async {
    try {
      final result = await ApiService.getMyChildLinkRequests(
        token: widget.token,
      );
      if (!mounted) return;
      setState(() {
        _linkRequests = (result['requests'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      });
    } catch (error) {
      debugPrint('Unable to load child link requests: $error');
    }
  }

  Future<void> _loadTodayStatuses() async {
    final entries = await Future.wait(
      _children.map((child) async {
        final id = child['id'].toString();
        try {
          final result = await ApiService.getChildAttendance(
            token: widget.token,
            studentId: id,
          );
          return MapEntry(
            id,
            _summarizeToday(result['attendance'] as List<dynamic>? ?? []),
          );
        } catch (error) {
          debugPrint('Unable to load attendance for $id: $error');
          return MapEntry(id, <String, dynamic>{'state': 'unknown'});
        }
      }),
    );
    if (!mounted) return;
    setState(() {
      _todayByChild = {for (final entry in entries) entry.key: entry.value};
      _todayLoaded = true;
    });
  }

  // Manila time, whatever time zone the phone or browser uses.
  DateTime? _parseLocal(dynamic value) => ManilaTime.parse(value);

  // What a child did today, from their attendance records (newest first).
  Map<String, dynamic> _summarizeToday(List<dynamic> attendance) {
    final now = ManilaTime.now(); // "today" is today in Manila
    final todays = attendance
        .map((record) => Map<String, dynamic>.from(record as Map))
        .where((record) {
          final date = _parseLocal(record['attendance_date']);
          return date != null &&
              date.year == now.year &&
              date.month == now.month &&
              date.day == now.day;
        })
        .toList();
    if (todays.isEmpty) return {'state': 'none'};

    final latest = todays.first;
    final campus = latest['campus_name']?.toString();
    final timeIn = _parseLocal(latest['time_in']);
    final timeOut = _parseLocal(latest['time_out']);
    if (latest['time_out'] == null) {
      return {'state': 'on_campus', 'timeIn': timeIn, 'campus': campus};
    }
    return {
      'state': latest['status'] == 'timeout' ? 'timed_out' : 'checked_out',
      'timeIn': timeIn,
      'timeOut': timeOut,
      'campus': campus,
    };
  }

  // ------------------------------------------------------------------ helpers

  String _getFullName(dynamic child) {
    final first = child['first_name'] ?? '';
    final middle = child['middle_name'] ?? '';
    final last = child['last_name'] ?? '';
    if (middle.isEmpty) {
      return '$first $last';
    }
    return '$first $middle $last';
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '';
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _formatDate(dynamic value) {
    final date = _parseLocal(value);
    if (date == null) return '';
    return '${_monthsShort[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// "BSIT · Year 3", or nothing when the record has neither.
  String _classLine(dynamic child) {
    return [
      child['course']?.toString(),
      if (child['year_level'] != null) 'Year ${child['year_level']}',
    ].whereType<String>().where((value) => value.trim().isNotEmpty).join(
      '  ·  ',
    );
  }

  /// The name a parent is greeted by: the first word of their first name.
  ///
  /// A parent imported from the masterlist has their whole name in one box,
  /// so "Maria Santos" can land in the first name. "Hello, Maria" reads like
  /// a greeting; "Hello, Maria Santos" reads like a form. "Ma." on its own is
  /// not a name, so "Ma. Cristina" keeps both words.
  String get _greetingName {
    final words = _firstName.trim().split(RegExp(r'\s+'))
      ..removeWhere((word) => word.isEmpty);
    if (words.isEmpty) return '';
    final first = words.first.toLowerCase();
    if ((first == 'ma.' || first == 'ma') && words.length > 1) {
      return '${words[0]} ${words[1]}';
    }
    return words.first;
  }

  String get _greeting =>
      _greetingName.isNotEmpty ? 'Hello, $_greetingName' : 'Hello';

  void _openChild(dynamic child) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChildAttendanceScreen(
          token: widget.token,
          studentId: child['id'],
          studentName: _getFullName(child),
        ),
      ),
    );
  }

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NotificationsScreen(token: widget.token),
      ),
    ).then((_) {
      if (mounted) _loadUnreadCount();
    });
  }

  void _openAccountSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AccountSettingsScreen(
          email: widget.email,
          role: 'Parent',
          fullName: widget.fullName,
          token: widget.token,
          onSignOut: () {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
              (route) => false,
            );
          },
        ),
      ),
    );
  }

  Future<void> _addChild() async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _AddChildDialog(token: widget.token),
    );
    if (!mounted || message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
    await _loadLinkRequests();
  }

  // -------------------------------------------------------------- shared parts

  Widget _emptyChildrenCard() {
    return AppPanel(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
      child: EmptyState(
        icon: Icons.family_restroom_outlined,
        title: 'No children linked yet',
        message:
            'Tap "Add child" and enter your child\'s student number. '
            'The administrator will review your request.',
        action: FilledButton.icon(
          onPressed: _addChild,
          icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
          label: const Text('Add child'),
        ),
      ),
    );
  }

  /// Lays [cards] out two to a row when there is room, one when there is not.
  Widget _grid(double width, List<Widget> cards) {
    final columns = width >= 720 ? 2 : 1;
    final itemWidth =
        ((width - AppSpace.md * (columns - 1)) / columns).floorToDouble();
    return Wrap(
      spacing: AppSpace.md,
      runSpacing: AppSpace.md,
      children: [
        for (final card in cards) SizedBox(width: itemWidth, child: card),
      ],
    );
  }

  // --------------------------------------------------------------------- Home

  Widget _statTile({
    required IconData icon,
    required String label,
    required int? value,
    required Color color,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Hoverable(
      onTap: onTap,
      builder: (context, hovered) => AppPanel(
        hovered: hovered,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.block),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(height: AppSpace.sm),
            value == null
                ? Text(
                    '-',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  )
                : CountUp(
                    value: value,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1,
                      letterSpacing: -0.5,
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

  /// One time of the day, with its name above it: "Time in / 7:32 AM".
  Widget _timeBlock(String label, String value, {String empty = '—'}) {
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

  /// Today, for one child: where they are, when they came in and when they
  /// left. This is the card a parent opens the app for.
  Widget _todayCard(dynamic child) {
    final theme = Theme.of(context);
    final id = child['id'].toString();
    final status = _todayByChild[id];
    final state = status?['state']?.toString();
    final timeIn = _formatTime(status?['timeIn'] as DateTime?);
    final timeOut = _formatTime(status?['timeOut'] as DateTime?);
    final campus = status?['campus']?.toString() ?? '';

    final String label;
    final String detail;
    final StatusLevel level;
    switch (state) {
      case 'on_campus':
        label = 'On campus';
        detail = campus.isNotEmpty ? 'Inside $campus' : 'Inside the campus';
        level = StatusLevel.good;
        break;
      case 'checked_out':
        label = 'Checked out';
        detail = campus.isNotEmpty ? 'Left $campus' : 'Left the campus';
        level = StatusLevel.neutral;
        break;
      case 'timed_out':
        label = 'Auto timed out';
        detail = 'Did not time out, so the system closed the day for them.';
        level = StatusLevel.caution;
        break;
      case 'none':
        label = 'Not yet in';
        detail = 'No check-in yet today.';
        level = StatusLevel.neutral;
        break;
      default:
        label = _todayLoaded ? 'Unavailable' : 'Checking';
        detail = _todayLoaded
            ? 'Could not load today\'s status. Pull down to try again.'
            : 'Checking today\'s status...';
        level = StatusLevel.neutral;
    }
    final tone = StatusTone.forLevel(context, level);
    final classLine = _classLine(child);

    return Hoverable(
      onTap: () => _openChild(child),
      builder: (context, hovered) => AppPanel(
        hovered: hovered,
        accent: level == StatusLevel.neutral ? null : tone.content,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProfileAvatar(name: _getFullName(child), radius: 22),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getFullName(child),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (classLine.isNotEmpty)
                        Text(
                          classLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                StatusBadge(label: label, tone: tone),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                _timeBlock('Time in', timeIn),
                const SizedBox(width: AppSpace.sm),
                _timeBlock(
                  'Time out',
                  timeOut,
                  empty: state == 'on_campus' ? 'Still inside' : '—',
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                AnimatedSlide(
                  duration: const Duration(milliseconds: 160),
                  offset: Offset(hovered ? 0.25 : 0, 0),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingBanner(int pendingRequests) {
    final theme = Theme.of(context);
    final tone = StatusTone.forLevel(context, StatusLevel.caution);
    return Hoverable(
      onTap: () => setState(() => _selectedNavigationIndex = 1),
      builder: (context, hovered) => AppPanel(
        hovered: hovered,
        accent: tone.content,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_top_rounded, color: tone.content, size: 20),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Text(
                pendingRequests == 1
                    ? '1 child link request is waiting for approval'
                    : '$pendingRequests child link requests are waiting for approval',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }

  List<Widget> _homeContent(double width) {
    final theme = Theme.of(context);
    final pendingRequests = _linkRequests
        .where((request) => request['status'] == 'pending')
        .length;
    final onCampus = _todayByChild.values
        .where((status) => status['state'] == 'on_campus')
        .length;

    return [
      Reveal(
        order: 1,
        child: Row(
          children: [
            Expanded(
              child: _statTile(
                icon: Icons.family_restroom_outlined,
                label: 'Children',
                value: _children.length,
                color: theme.colorScheme.primary,
                onTap: () => setState(() => _selectedNavigationIndex = 1),
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: _statTile(
                icon: Icons.location_on_outlined,
                label: 'On campus now',
                value: _todayLoaded ? onCampus : null,
                color: StatusTone.forLevel(context, StatusLevel.good).content,
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: _statTile(
                icon: Icons.notifications_outlined,
                label: 'Unread',
                value: _unreadCount,
                color: StatusTone.forLevel(
                  context,
                  StatusLevel.caution,
                ).content,
                onTap: _openNotifications,
              ),
            ),
          ],
        ),
      ),
      if (pendingRequests > 0) ...[
        const SizedBox(height: AppSpace.md),
        Reveal(order: 2, child: _pendingBanner(pendingRequests)),
      ],
      const SizedBox(height: AppSpace.xl),
      Reveal(
        order: 2,
        child: SectionHeading(
          title: 'Today',
          subtitle: _children.isEmpty
              ? 'Link a child to see their attendance'
              : 'Tap a child to see their attendance history',
        ),
      ),
      const SizedBox(height: AppSpace.md),
      Reveal(
        order: 3,
        child: _children.isEmpty
            ? _emptyChildrenCard()
            : _grid(width, _children.map(_todayCard).toList()),
      ),
    ];
  }

  // ----------------------------------------------------------------- Children

  Widget _childCard(dynamic child) {
    final theme = Theme.of(context);
    final details = [
      if (child['student_number'] != null) '${child['student_number']}',
      if (_classLine(child).isNotEmpty) _classLine(child),
    ].join('  ·  ');

    return Hoverable(
      onTap: () => _openChild(child),
      builder: (context, hovered) => AppPanel(
        hovered: hovered,
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          children: [
            ProfileAvatar(name: _getFullName(child), radius: 22),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getFullName(child),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            AnimatedSlide(
              duration: const Duration(milliseconds: 160),
              offset: Offset(hovered ? 0.25 : 0, 0),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> request) {
    final theme = Theme.of(context);
    final status = request['status']?.toString();
    final String label;
    final StatusLevel level;
    switch (status) {
      case 'approved':
        label = 'Approved';
        level = StatusLevel.good;
        break;
      case 'rejected':
        label = 'Declined';
        level = StatusLevel.stop;
        break;
      default:
        label = 'Pending';
        level = StatusLevel.caution;
    }
    final requested = _formatDate(request['requested_at']);
    return AppPanel(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(
        children: [
          Icon(
            Icons.person_add_alt_1_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request['student_name']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  [
                    request['student_number']?.toString() ?? '',
                    if (requested.isNotEmpty) 'Requested $requested',
                  ].where((part) => part.isNotEmpty).join('  ·  '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          StatusBadge(
            label: label,
            tone: StatusTone.forLevel(context, level),
          ),
        ],
      ),
    );
  }

  Widget _groupLabel(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  List<Widget> _childrenContent(double width) {
    return [
      Reveal(
        order: 0,
        child: SectionHeading(
          title: 'Your children',
          subtitle:
              '${_children.length} linked student${_children.length == 1 ? '' : 's'}',
          trailing: _children.isEmpty
              ? null
              : FilledButton.icon(
                  onPressed: _addChild,
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                  label: const Text('Add child'),
                ),
        ),
      ),
      const SizedBox(height: AppSpace.lg),
      if (_children.isEmpty)
        Reveal(order: 1, child: _emptyChildrenCard())
      else
        Reveal(
          order: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _groupLabel('Linked students'),
              _grid(width, _children.map(_childCard).toList()),
            ],
          ),
        ),
      if (_linkRequests.isNotEmpty) ...[
        const SizedBox(height: AppSpace.xl),
        Reveal(
          order: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _groupLabel('Link requests'),
              _grid(
                width,
                _linkRequests.take(10).map(_requestCard).toList(),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: brandAppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadAll,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error.isNotEmpty
          ? EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load your children',
              message: 'Unable to connect to the server. Please try again.',
              action: FilledButton.icon(
                onPressed: _loadAll,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final padding = constraints.maxWidth < 400
                      ? AppSpace.lg
                      : AppSpace.xl;
                  final contentWidth =
                      (constraints.maxWidth - padding * 2).clamp(0.0, 960.0);
                  final home = _selectedNavigationIndex == 0;
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    // On Home the green band runs edge to edge at the top, so
                    // there is no padding above it.
                    padding: home
                        ? EdgeInsets.fromLTRB(0, 0, 0, padding)
                        : EdgeInsets.all(padding),
                    children: [
                      if (home) ...[
                        Reveal(
                          order: 0,
                          child: BrandBand(
                            greeting: _greeting,
                            subtitle:
                                'Here is how your children are doing today.',
                            name: _displayName,
                            photo: ProfileState.instance.photo,
                          ),
                        ),
                        const SizedBox(height: AppSpace.lg),
                      ],
                      Center(
                        child: Container(
                          width: home ? contentWidth + padding * 2 : contentWidth,
                          padding: home
                              ? EdgeInsets.symmetric(horizontal: padding)
                              : EdgeInsets.zero,
                          // A new key per tab, so switching tabs plays the
                          // entrance again instead of swapping in silently.
                          child: Column(
                            key: ValueKey(_selectedNavigationIndex),
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _selectedNavigationIndex == 0
                                ? _homeContent(contentWidth)
                                : _childrenContent(contentWidth),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedNavigationIndex,
        onDestinationSelected: (index) {
          if (index == 0 || index == 1) {
            setState(() => _selectedNavigationIndex = index);
          } else if (index == 2) {
            _openNotifications();
          } else {
            _openAccountSettings();
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.child_care_outlined),
            selectedIcon: Icon(Icons.child_care),
            label: 'Children',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _unreadCount > 0,
              label: Text(_unreadCount > 99 ? '99+' : '$_unreadCount'),
              child: const Icon(Icons.notifications_outlined),
            ),
            label: 'Notifications',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

/// Asks for a student number and sends a link request to the administrator.
/// The dialog stays open on an error so the number does not have to be retyped.
class _AddChildDialog extends StatefulWidget {
  final String token;

  const _AddChildDialog({required this.token});

  @override
  State<_AddChildDialog> createState() => _AddChildDialogState();
}

class _AddChildDialogState extends State<_AddChildDialog> {
  final _controller = TextEditingController();
  bool _isSending = false;
  String _error = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSending) return;
    final studentNumber = _controller.text.trim();
    if (studentNumber.isEmpty) {
      setState(() => _error = 'Enter your child\'s student number.');
      return;
    }

    setState(() {
      _isSending = true;
      _error = '';
    });
    try {
      final result = await ApiService.requestChildLink(
        token: widget.token,
        studentNumber: studentNumber,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        result['message']?.toString() ??
            'Request sent. The administrator will review it.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Add child'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter your child\'s student number. The administrator will review the request before the child is linked to your account.',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              enabled: !_isSending,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Student number',
                hintText: 'e.g. BSIT-2023-01-00062',
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_error, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSending ? null : _submit,
          child: _isSending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send request'),
        ),
      ],
    );
  }
}