import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'account_settings_screen.dart';
import 'admin_attendance_screen.dart';
import 'admin_bulk_accounts_screen.dart';
import 'admin_campuses_screen.dart';
import 'admin_class_schedules_screen.dart';
import 'admin_registration_requests_screen.dart';
import 'admin_student_report_screen.dart';
import 'admin_users_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import '../services/profile_state.dart';
import '../utils/manila_time.dart';
import '../widgets/app_ui.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String token;
  final String email;
  final String fullName;

  const AdminDashboardScreen({
    super.key,
    required this.token,
    required this.email,
    this.fullName = '',
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _isLoading = true;
  String _error = '';
  Map<String, dynamic> _summary = {};
  int? _pendingRequests; // null = unknown
  int? _pendingChildLinks; // null = unknown

  @override
  void initState() {
    super.initState();
    ProfileState.instance.addListener(_onProfileChanged);
    ProfileState.instance.refresh(widget.token);
    _loadSummary();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ProfileState.instance.removeListener(_onProfileChanged);
    super.dispose();
  }

  Future<void> _loadSummary() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = '';
      });
    }
    try {
      final result = await ApiService.getAdminSummary(token: widget.token);
      if (!mounted) return;
      setState(() {
        _summary = result;
        _isLoading = false;
      });
      _loadPendingRequests();
      _loadPendingChildLinks();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  // ── Navigation ───────────────────────────────────────────────────

  // Counts the registration requests that are still waiting for the admin.
  Future<void> _loadPendingRequests() async {
    try {
      final result = await ApiService.getRegistrationRequests(
        token: widget.token,
      );
      final list =
          result['requests'] ??
          result['registrationRequests'] ??
          result['registration_requests'];
      if (list is! List) {
        if (mounted) setState(() => _pendingRequests = null);
        return;
      }
      final pending = list.where((item) {
        final status = (item is Map ? item['status'] : null)
            ?.toString()
            .toLowerCase();
        return status == null || status == 'pending';
      }).length;
      if (!mounted) return;
      setState(() => _pendingRequests = pending);
    } catch (error) {
      debugPrint('Could not load pending registration requests: $error');
    }
  }

  // Counts the parent requests to link a child that are still pending.
  Future<void> _loadPendingChildLinks() async {
    try {
      final result = await ApiService.getChildLinkRequests(token: widget.token);
      final list = result['requests'];
      if (list is! List) return;
      final pending = list
          .where((item) => item is Map && item['status'] == 'pending')
          .length;
      if (!mounted) return;
      setState(() => _pendingChildLinks = pending);
    } catch (error) {
      // The child link table may not exist yet; just hide the count.
      debugPrint('Could not load pending child link requests: $error');
    }
  }

  Future<void> _openScreen(Widget screen) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
    if (mounted) await _loadSummary();
  }

  Future<void> _openRegistrationRequests() =>
      _openScreen(AdminRegistrationRequestsScreen(token: widget.token));

  Future<void> _openChildLinkRequests() => _openScreen(
    AdminRegistrationRequestsScreen(token: widget.token, initialTab: 1),
  );

  Future<void> _openUsers() =>
      _openScreen(AdminUsersScreen(token: widget.token));

  Future<void> _openBulkAccounts() =>
      _openScreen(AdminBulkAccountsScreen(token: widget.token));

  Future<void> _openAttendance() =>
      _openScreen(AdminAttendanceScreen(token: widget.token));

  Future<void> _openSchedules() =>
      _openScreen(AdminClassSchedulesScreen(token: widget.token));

  Future<void> _openCampuses() =>
      _openScreen(AdminCampusesScreen(token: widget.token));

  Future<void> _openReports() =>
      _openScreen(AdminStudentReportScreen(token: widget.token));

  Future<void> _openAccount() => _openScreen(
    AccountSettingsScreen(
      email: widget.email,
      role: 'Admin',
      fullName: widget.fullName,
      token: widget.token,
      onSignOut: _confirmSignOut,
    ),
  );

  Future<void> _openMoreMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Bulk accounts'),
              subtitle: const Text('Create student and parent accounts from Excel'),
              onTap: () => Navigator.pop(sheetContext, 'bulk'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Class schedules'),
              onTap: () => Navigator.pop(sheetContext, 'schedules'),
            ),
            ListTile(
              leading: const Icon(Icons.location_city_outlined),
              title: const Text('Campuses and boundaries'),
              onTap: () => Navigator.pop(sheetContext, 'campuses'),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1_outlined),
              title: const Text('Registration requests'),
              onTap: () => Navigator.pop(sheetContext, 'registrations'),
            ),
            ListTile(
              leading: const Icon(Icons.assessment_outlined),
              title: const Text('Attendance reports'),
              onTap: () => Navigator.pop(sheetContext, 'reports'),
            ),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Profile'),
              onTap: () => Navigator.pop(sheetContext, 'account'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'bulk':
        await _openBulkAccounts();
        break;
      case 'schedules':
        await _openSchedules();
        break;
      case 'campuses':
        await _openCampuses();
        break;
      case 'registrations':
        await _openRegistrationRequests();
        break;
      case 'reports':
        await _openReports();
        break;
      case 'account':
        await _openAccount();
        break;
    }
  }

  Future<void> _confirmSignOut() async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again to access BenildeSafe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _signOut();
    }
  }

  void _signOut() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  void _handleBottomNav(int index) {
    switch (index) {
      case 1:
        _openUsers();
        break;
      case 2:
        _openAttendance();
        break;
      case 3:
        _openMoreMenu();
        break;
    }
  }

  // ── Reusable widgets ─────────────────────────────────────────────

  Widget _statCard({
    required String label,
    required dynamic value,
    required IconData icon,
    required Color color,
    bool compact = false,
  }) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Row(
          children: [
            Container(
              width: compact ? 38 : 46,
              height: compact ? 38 : 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(compact ? 12 : 14),
              ),
              child: Icon(icon, size: compact ? 20 : 23, color: color),
            ),
            SizedBox(width: compact ? 10 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    value.toString(),
                    style: TextStyle(
                      fontSize: compact ? 22 : 24,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(double width) {
    final columns = width > 900 ? 4 : 2;
    final compact = width <= 600;
    final cards = <Widget>[
      _statCard(
        label: 'Students',
        value: _summary['totalStudents'] ?? 0,
        icon: Icons.school_outlined,
        color: AppColors.forestGreen,
        compact: compact,
      ),
      _statCard(
        label: 'Teachers',
        value: _summary['totalTeachers'] ?? 0,
        icon: Icons.person_outline,
        color: AppColors.accentGreen,
        compact: compact,
      ),
      _statCard(
        label: 'Parents',
        value: _summary['totalParents'] ?? 0,
        icon: Icons.family_restroom_outlined,
        color: AppColors.warmGold,
        compact: compact,
      ),
      _statCard(
        label: 'Attendance today',
        value: _summary['totalAttendanceToday'] ?? 0,
        icon: Icons.fact_check_outlined,
        color: Theme.of(context).colorScheme.primary,
        compact: compact,
      ),
    ];

    if (columns == 1) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            cards[i],
            if (i != cards.length - 1) const SizedBox(height: 12),
          ],
        ],
      );
    }

    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: compact ? 1.9 : 2.6,
      children: cards,
    );
  }

  Widget _attentionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required int? count,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
        child: Icon(icon, color: theme.colorScheme.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      trailing: (count ?? 0) > 0
          ? Badge(label: Text('$count'), child: const Icon(Icons.chevron_right))
          : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  // Things that are waiting for the admin. Navigation lives in the sidebar
  // (wide screens) and the bottom bar / More menu (phones).
  Widget _attentionCard() {
    final theme = Theme.of(context);
    final pending = _pendingRequests;
    final String subtitle;
    if (pending == null) {
      subtitle = 'Review new student, teacher and parent accounts';
    } else if (pending == 0) {
      subtitle = 'No pending requests. You are all caught up.';
    } else {
      subtitle =
          '$pending ${pending == 1 ? 'request is' : 'requests are'} waiting for approval';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Needs attention',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.notifications_active_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Things that are waiting for you.',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            _attentionTile(
              icon: Icons.person_add_alt_1_outlined,
              title: 'Registration requests',
              subtitle: subtitle,
              count: pending,
              onTap: _openRegistrationRequests,
            ),
            Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.5)),
            _attentionTile(
              icon: Icons.family_restroom_outlined,
              title: 'Child link requests',
              subtitle: _pendingChildLinks == null
                  ? 'Parents asking to link another child'
                  : (_pendingChildLinks == 0
                        ? 'No pending requests. You are all caught up.'
                        : '$_pendingChildLinks ${_pendingChildLinks == 1 ? 'request is' : 'requests are'} waiting for approval'),
              count: _pendingChildLinks,
              onTap: _openChildLinkRequests,
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(bool isWide) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProfileAvatar(
            name: widget.fullName.trim().isNotEmpty
                ? widget.fullName.trim()
                : 'Administrator',
            radius: 24,
            photo: ProfileState.instance.photo,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.fullName.trim().isNotEmpty
                      ? 'Welcome back, ${widget.fullName.trim()}'
                      : 'Welcome back, Administrator',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          if (isWide)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 15,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    MaterialLocalizations.of(
                      context,
                    ).formatMediumDate(ManilaTime.now()),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dashboardBody(bool isWide) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_off_outlined,
                size: 42,
                color: Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(_error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _loadSummary,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSummary,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final padding = width < 400 ? 14.0 : 24.0;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.all(padding),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _header(isWide),
                    _buildStatsGrid(width),
                    const SizedBox(height: 20),
                    _attentionCard(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 900;

    final appBar = AppBar(
      title: const Text('BenildeSafe'),
      actions: [
        NotificationButton(token: widget.token),
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Refresh dashboard',
          onPressed: _isLoading ? null : _loadSummary,
        ),
      ],
    );

    if (isWide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _Sidebar(
                onUsers: _openUsers,
                onBulkAccounts: _openBulkAccounts,
                onAttendance: _openAttendance,
                onSchedules: _openSchedules,
                onCampuses: _openCampuses,
                onRegistrations: _openRegistrationRequests,
                onReports: _openReports,
                onAccount: _openAccount,
                onSignOut: _confirmSignOut,
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    appBar,
                    Expanded(child: _dashboardBody(true)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: _dashboardBody(false),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: _handleBottomNav,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline_rounded),
            label: 'Users',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            label: 'Attendance',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

// ── Helper types ───────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final VoidCallback onUsers;
  final VoidCallback onBulkAccounts;
  final VoidCallback onAttendance;
  final VoidCallback onSchedules;
  final VoidCallback onCampuses;
  final VoidCallback onRegistrations;
  final VoidCallback onReports;
  final VoidCallback onAccount;
  final VoidCallback onSignOut;

  const _Sidebar({
    required this.onUsers,
    required this.onBulkAccounts,
    required this.onAttendance,
    required this.onSchedules,
    required this.onCampuses,
    required this.onRegistrations,
    required this.onReports,
    required this.onAccount,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      color: Theme.of(context).cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.forestGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: AppColors.forestGreen,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'BenildeSafe',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _navItem(
                  context,
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  selected: true,
                  onTap: null,
                ),
                _navItem(
                  context,
                  icon: Icons.people_outline_rounded,
                  activeIcon: Icons.people_rounded,
                  label: 'Users',
                  onTap: onUsers,
                ),
                _navItem(
                  context,
                  icon: Icons.upload_file_outlined,
                  activeIcon: Icons.upload_file_rounded,
                  label: 'Bulk accounts',
                  onTap: onBulkAccounts,
                ),
                _navItem(
                  context,
                  icon: Icons.fact_check_outlined,
                  activeIcon: Icons.fact_check_rounded,
                  label: 'Attendance records',
                  onTap: onAttendance,
                ),
                _navItem(
                  context,
                  icon: Icons.calendar_month_outlined,
                  activeIcon: Icons.calendar_month_rounded,
                  label: 'Class schedules',
                  onTap: onSchedules,
                ),
                _navItem(
                  context,
                  icon: Icons.location_city_outlined,
                  activeIcon: Icons.location_city_rounded,
                  label: 'Campuses',
                  onTap: onCampuses,
                ),
                _navItem(
                  context,
                  icon: Icons.person_add_alt_1_outlined,
                  activeIcon: Icons.person_add_alt_1_rounded,
                  label: 'Registration requests',
                  onTap: onRegistrations,
                ),
                _navItem(
                  context,
                  icon: Icons.assessment_outlined,
                  activeIcon: Icons.assessment_rounded,
                  label: 'Attendance reports',
                  onTap: onReports,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Divider(color: Theme.of(context).dividerColor),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _navItem(
                  context,
                  icon: Icons.account_circle_outlined,
                  activeIcon: Icons.account_circle,
                  label: 'Profile',
                  onTap: onAccount,
                ),
                _navItem(
                  context,
                  icon: Icons.logout_rounded,
                  activeIcon: Icons.logout_rounded,
                  label: 'Sign out',
                  onTap: onSignOut,
                  danger: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(
    BuildContext context, {
    required IconData icon,
    required IconData activeIcon,
    required String label,
    bool selected = false,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final color = danger
        ? scheme.error
        : (selected ? scheme.primary : scheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 11,
            ),
            child: Row(
              children: [
                Icon(selected ? activeIcon : icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}