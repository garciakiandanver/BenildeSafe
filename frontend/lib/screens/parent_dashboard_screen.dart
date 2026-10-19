import 'dart:async';
import 'package:flutter/material.dart';
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
    ProfileState.instance.addListener(_onProfileChanged);
    ProfileState.instance.refresh(widget.token);
    _loadAll();
    // Check for new notifications every 30 seconds while this screen is open.
    _notificationTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadUnreadCount(),
    );
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
    if (latest['time_out'] == null) {
      return {
        'state': 'on_campus',
        'time': _parseLocal(latest['time_in']),
        'campus': campus,
      };
    }
    return {
      'state': latest['status'] == 'timeout' ? 'timed_out' : 'checked_out',
      'time': _parseLocal(latest['time_out']),
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

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

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

  Widget _greetingRow(String subtitle) {
    final theme = Theme.of(context);
    return Row(
      children: [
        ProfileAvatar(
          name: _displayName,
          radius: 25,
          photo: ProfileState.instance.photo,
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _firstName.isNotEmpty
                    ? 'Welcome, $_firstName'
                    : 'Welcome',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
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

  Widget _emptyChildrenCard() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.family_restroom_outlined,
                size: 30,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No children linked yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              'Open the Children tab and tap "Add child". Enter your child\'s student number and the administrator will review your request.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------- Home

  Widget _summaryCard(
    IconData icon,
    String value,
    String label, {
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(height: 10),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _todayCard(dynamic child) {
    final theme = Theme.of(context);
    final id = child['id'].toString();
    final status = _todayByChild[id];
    final state = status?['state']?.toString();
    final time = _formatTime(status?['time'] as DateTime?);
    final campus = status?['campus']?.toString();

    final String label;
    final String detail;
    final Color color;
    switch (state) {
      case 'on_campus':
        label = 'On campus';
        detail =
            'In since $time${campus != null && campus.isNotEmpty ? '  ·  $campus' : ''}';
        color = Colors.green.shade700;
        break;
      case 'checked_out':
        label = 'Checked out';
        detail = 'Checked out at $time';
        color = Colors.blueGrey.shade600;
        break;
      case 'timed_out':
        label = 'Timed out';
        detail = 'Automatically timed out at $time';
        color = Colors.orange.shade800;
        break;
      case 'none':
        label = 'No check-in';
        detail = 'No check-in yet today';
        color = Colors.grey.shade600;
        break;
      default:
        label = _todayLoaded ? 'Unavailable' : '...';
        detail = _todayLoaded
            ? 'Could not load today\'s status'
            : 'Checking today\'s status...';
        color = Colors.grey.shade600;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 17,
            vertical: 8,
          ),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              (child['first_name']?.toString() ?? '').isNotEmpty
                  ? child['first_name'].toString()[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          title: Text(
            _getFullName(child),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(detail),
          ),
          trailing: _chip(label, color),
          onTap: () => _openChild(child),
        ),
      ),
    );
  }

  List<Widget> _homeContent() {
    final theme = Theme.of(context);
    final pendingRequests = _linkRequests
        .where((request) => request['status'] == 'pending')
        .length;
    final onCampus = _todayByChild.values
        .where((status) => status['state'] == 'on_campus')
        .length;

    return [
      _greetingRow('Here is how your children are doing today.'),
      const SizedBox(height: 18),
      Row(
        children: [
          Expanded(
            child: _summaryCard(
              Icons.family_restroom_outlined,
              '${_children.length}',
              'Children',
              onTap: () => setState(() => _selectedNavigationIndex = 1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _summaryCard(
              Icons.school_outlined,
              _todayLoaded ? '$onCampus' : '-',
              'On campus now',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _summaryCard(
              Icons.notifications_outlined,
              '$_unreadCount',
              'Unread notifications',
              onTap: _openNotifications,
            ),
          ),
        ],
      ),
      if (pendingRequests > 0) ...[
        const SizedBox(height: 12),
        Card(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: Icon(
              Icons.hourglass_top_rounded,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              pendingRequests == 1
                  ? '1 child link request is waiting for approval'
                  : '$pendingRequests child link requests are waiting for approval',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => _selectedNavigationIndex = 1),
          ),
        ),
      ],
      const SizedBox(height: 22),
      SectionHeading(
        title: 'Today',
        subtitle: _children.isEmpty
            ? 'Link a child to see their attendance'
            : 'Tap a child to see their attendance history',
      ),
      if (_children.isEmpty)
        _emptyChildrenCard()
      else
        ..._children.map(_todayCard),
    ];
  }

  // ----------------------------------------------------------------- Children

  Widget _childCard(dynamic child) {
    final theme = Theme.of(context);
    final courseDetails = [
      child['course']?.toString(),
      if (child['year_level'] != null) 'Year ${child['year_level']}',
      if ((child['section']?.toString() ?? '').trim().isNotEmpty)
        'Section ${child['section']}',
    ].whereType<String>().where((value) => value.trim().isNotEmpty);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 17,
            vertical: 10,
          ),
          leading: CircleAvatar(
            radius: 25,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              (child['first_name']?.toString() ?? '').isNotEmpty
                  ? child['first_name'].toString()[0].toUpperCase()
                  : '?',
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          title: Text(
            _getFullName(child),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              [
                if (child['student_number'] != null)
                  'ID ${child['student_number']}',
                ...courseDetails,
              ].join('  ·  '),
            ),
          ),
          trailing: Icon(
            Icons.arrow_forward_ios_rounded,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          onTap: () => _openChild(child),
        ),
      ),
    );
  }

  Widget _requestCard(Map<String, dynamic> request) {
    final status = request['status']?.toString();
    final String label;
    final Color color;
    switch (status) {
      case 'approved':
        label = 'Approved';
        color = Colors.green.shade700;
        break;
      case 'rejected':
        label = 'Declined';
        color = Colors.red.shade700;
        break;
      default:
        label = 'Pending';
        color = Colors.orange.shade800;
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person_add_alt_1_outlined),
        title: Text(
          request['student_name']?.toString() ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${request['student_number'] ?? ''}  ·  Requested ${_formatDate(request['requested_at'])}',
        ),
        trailing: _chip(label, color),
      ),
    );
  }

  List<Widget> _childrenContent() {
    final theme = Theme.of(context);
    return [
      Row(
        children: [
          Expanded(
            child: SectionHeading(
              title: 'Your children',
              subtitle:
                  '${_children.length} linked student${_children.length == 1 ? '' : 's'}',
            ),
          ),
          FilledButton.icon(
            onPressed: _addChild,
            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
            label: const Text('Add child'),
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (_children.isEmpty)
        _emptyChildrenCard()
      else ...[
        Text(
          'LINKED STUDENTS',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        ..._children.map(_childCard),
      ],
      if (_linkRequests.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(
          'LINK REQUESTS',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 10),
        ..._linkRequests.take(10).map(_requestCard),
      ],
    ];
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BenildeSafe'),
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
                builder: (context, constraints) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.all(constraints.maxWidth < 400 ? 16 : 24),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: _selectedNavigationIndex == 0
                              ? _homeContent()
                              : _childrenContent(),
                        ),
                      ),
                    ),
                  ],
                ),
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