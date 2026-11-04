import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'account_settings_screen.dart';
import 'admin_attendance_screen.dart';
import 'admin_bulk_accounts_screen.dart';
import 'admin_campuses_screen.dart';
import 'admin_class_schedules_screen.dart';
import 'admin_child_link_requests_screen.dart';
import 'admin_student_report_screen.dart';
import 'admin_users_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import '../services/profile_state.dart';
import '../widgets/app_ui.dart';
import '../widgets/attendance_trend_chart.dart';

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
  int? _pendingChildLinks; // null = unknown

  // Two more things worth knowing about, both read from small tables.
  //
  // A campus with no boundary drawn cannot accept a single time in, and a term
  // with no class schedules leaves every student without a daily schedule and
  // nobody ever marked late. Neither shows up anywhere else on this screen,
  // and both are silent: the system keeps running and simply does nothing.
  int? _campusesWithoutBoundary;
  int? _schedulesThisTerm;

  // A running clock in the header. It is the one moving thing on the screen,
  // and it is what tells an administrator at a glance that the page is live
  // and not a stale tab left open since this morning.

  @override
  void initState() {
    super.initState();
    _releaseKeyboard();
    ProfileState.instance.addListener(_onProfileChanged);
    ProfileState.instance.refresh(widget.token);
    _loadSummary();
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
      _loadPendingChildLinks();
      _loadSetupSignals();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  // ── Navigation ───────────────────────────────────────────────────

  // Counts the parent requests to link a child that are still pending.
  /// Two cheap checks that nothing else on this screen would reveal.
  ///
  /// Both fail quietly in a half-set-up school, which is exactly why they are
  /// worth showing: a campus with no boundary refuses every time in, and a
  /// term with no schedules means no daily schedule and no late, with no
  /// error anywhere to say so.
  Future<void> _loadSetupSignals() async {
    try {
      final campuses = await ApiService.getAdminCampuses(token: widget.token);
      final list = campuses['campuses'];
      if (list is List && mounted) {
        setState(() {
          _campusesWithoutBoundary = list
              .where(
                (item) =>
                    item is Map && item['boundary_coordinates'] == null,
              )
              .length;
        });
      }
    } catch (error) {
      debugPrint('Could not read the campuses: $error');
    }

    try {
      final terms = await ApiService.getAcademicTerms(token: widget.token);
      final list = terms['terms'];
      if (list is List && mounted) {
        final current = list.firstWhere(
          (item) => item is Map && item['is_current'] == true,
          orElse: () => null,
        );
        setState(() {
          _schedulesThisTerm = current == null
              ? 0
              : (current['schedule_count'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (error) {
      debugPrint('Could not read the academic terms: $error');
    }
  }

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

  Future<void> _openChildLinkRequests() =>
      _openScreen(AdminChildLinkRequestsScreen(token: widget.token));

  /// [tab]: 0 students, 1 teachers, 2 parents.
  Future<void> _openUsers({int tab = 0}) => _openScreen(
    AdminUsersScreen(token: widget.token, initialTab: tab),
  );

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
      // The profile screen asks "Sign out?" itself; asking here too would
      // put the same question on screen twice.
      onSignOut: _signOut,
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
              title: const Text('Import accounts'),
              subtitle: const Text('Students and parents from the masterlist'),
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
              leading: const Icon(Icons.family_restroom_outlined),
              title: const Text('Child link requests'),
              onTap: () => Navigator.pop(sheetContext, 'childlinks'),
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
      case 'childlinks':
        await _openChildLinkRequests();
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

  int _count(String key) {
    final value = _summary[key];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// A panel: a white surface with a hairline border instead of a shadow.
  ///
  /// Shadows on every card make a page look like a pile of receipts. A thin
  /// border separates without adding weight, and lets a panel hold other
  /// panels without the stacking becoming muddy.
  Widget _panel({
    required Widget child,
    EdgeInsetsGeometry? padding,
    bool hovered = false,
  }) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: padding ?? const EdgeInsets.all(AppSpace.xl),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border.all(
          color: hovered
              ? theme.colorScheme.primary.withValues(alpha: 0.45)
              : theme.dividerColor,
        ),
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: hovered
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }

  /// One figure, with its name above it and a line of context below.
  ///
  /// The footer is where the number stops being trivia and starts being
  /// useful: 2,450 students means little on its own, 2,308 of them timed in
  /// today means something. Every figure here is counted by the server; none
  /// of it is estimated.
  Widget _statCard({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
    Widget? footer,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return _Hoverable(
      onTap: onTap,
      builder: (context, hovered) => _panel(
        padding: const EdgeInsets.all(AppSpace.lg),
        hovered: hovered,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.block),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          _CountUp(
            value: value,
            format: _grouped,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -1,
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: AppSpace.md),
            Divider(height: 1, color: theme.dividerColor),
            const SizedBox(height: AppSpace.md),
            DefaultTextStyle.merge(
              style: theme.textTheme.bodySmall!.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              child: footer,
            ),
          ],
          ],
        ),
      ),
    );
  }

  /// 2450 reads as a code; 2,450 reads as a number.
  String _grouped(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer(value < 0 ? '-' : '');
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  Widget _buildStatsGrid(double width) {
    final students = _count('totalStudents');
    final present = _count('totalAttendanceToday');
    final pending = _pendingChildLinks;
    final share = students == 0 ? 0.0 : (present / students).clamp(0.0, 1.0);
    final theme = Theme.of(context);

    final cards = <Widget>[
      _statCard(
        label: 'Students',
        value: students,
        icon: Icons.school_outlined,
        color: AppColors.forestGreen,
        footer: Text('${_grouped(present)} timed in today'),
        onTap: () => _openUsers(),
      ),
      _statCard(
        label: 'Teachers',
        value: _count('totalTeachers'),
        icon: Icons.person_outline,
        color: AppColors.accentGreen,
        footer: const Text('View classes only'),
        onTap: () => _openUsers(tab: 1),
      ),
      _statCard(
        label: 'Parents',
        value: _count('totalParents'),
        icon: Icons.family_restroom_outlined,
        color: AppColors.warmGold,
        footer: Text(
          pending == null
              ? 'Linked to their children'
              : pending == 0
              ? 'No link requests waiting'
              : '$pending link ${pending == 1 ? 'request' : 'requests'} waiting',
        ),
        // Straight to the parents, whatever is waiting. The link requests
        // have their own row in the panel below.
        onTap: () => _openUsers(tab: 2),
      ),
      _statCard(
        label: 'On campus today',
        value: present,
        icon: Icons.fact_check_outlined,
        color: theme.colorScheme.primary,
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              students == 0
                  ? 'No students enrolled yet'
                  : '${(share * 100).toStringAsFixed(1)}% of ${_grouped(students)} students',
            ),
            const SizedBox(height: AppSpace.sm),
            // The bar fills from empty to the day's figure, so the share is
            // something you watch arrive rather than read off a label.
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: share.toDouble()),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (context, shown, _) => LinearProgressIndicator(
                  value: shown,
                  minHeight: 6,
                  backgroundColor: theme.dividerColor,
                ),
              ),
            ),
          ],
        ),
        onTap: _openAttendance,
      ),
    ];

    // Two to a row even on a phone. One per row made four tall cards that
    // filled three screens with white and pushed everything else out of sight.
    final columns = width > 1000
        ? 4
        : width >= 300
        ? 2
        : 1;

    if (columns == 1) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            cards[i],
            if (i != cards.length - 1) const SizedBox(height: AppSpace.md),
          ],
        ],
      );
    }

    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += columns) {
      final row = cards.skip(i).take(columns).toList();
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = 0; j < columns; j++) ...[
                Expanded(
                  child: j < row.length ? row[j] : const SizedBox.shrink(),
                ),
                if (j != columns - 1) const SizedBox(width: AppSpace.md),
              ],
            ],
          ),
        ),
      );
      if (i + columns < cards.length) {
        rows.add(const SizedBox(height: AppSpace.md));
      }
    }
    return Column(children: rows);
  }

  /// A row inside one of the two panels below the figures.
  Widget _hubRow({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String action,
    required VoidCallback onTap,
    int? count,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: _Hoverable(
        onTap: onTap,
        builder: (context, hovered) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: hovered
              ? color.withValues(alpha: 0.10)
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
          borderRadius: BorderRadius.circular(AppRadius.block),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if ((count ?? 0) > 0) ...[
                        const SizedBox(width: AppSpace.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            TextButton(onPressed: onTap, child: Text(action)),
          ],
        ),
        ),
      ),
    );
  }

  Widget _hubPanel({
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          ...children,
        ],
      ),
    );
  }

  /// What is waiting, and the few things an administrator starts most often.
  ///
  /// Only one thing can actually be waiting today — a parent asking to link a
  /// child — so the panel beside it holds the work that is started from here
  /// rather than inventing alerts the server does not report.
  Widget _attentionCard(double width) {
    final theme = Theme.of(context);
    final pending = _pendingChildLinks;
    final tone = StatusTone.of(
      context,
      (pending ?? 0) > 0 ? 'Late' : 'Present',
    );

    final stop = StatusTone.of(context, 'Outside Campus');
    final caution = StatusTone.of(context, 'Late');

    // Only what is actually wrong is listed. An empty panel of headings that
    // all say "none" tells an administrator nothing and takes up the room
    // that a real warning would need.
    final items = <Widget>[
      if (pending == null || pending > 0)
        _hubRow(
          icon: Icons.family_restroom_outlined,
          color: caution.content,
          title: 'Child link requests',
          subtitle: pending == null
              ? 'Parents asking to link another child'
              : '${pending == 1 ? 'A parent is' : '$pending parents are'} waiting',
          action: 'Review',
          count: pending,
          onTap: _openChildLinkRequests,
        ),
      if ((_campusesWithoutBoundary ?? 0) > 0)
        _hubRow(
          icon: Icons.wrong_location_outlined,
          color: stop.content,
          title: _campusesWithoutBoundary == 1
              ? 'A campus has no boundary'
              : '$_campusesWithoutBoundary campuses have no boundary',
          subtitle: 'No one can time in there until it is drawn',
          action: 'Draw it',
          count: _campusesWithoutBoundary,
          onTap: _openCampuses,
        ),
      if (_schedulesThisTerm == 0)
        _hubRow(
          icon: Icons.event_busy_outlined,
          color: stop.content,
          title: 'No class schedules this term',
          subtitle: 'Without them there is no daily schedule and no late',
          action: 'Add them',
          onTap: _openSchedules,
        ),
    ];

    final attention = _hubPanel(
      icon: items.isEmpty
          ? Icons.check_circle_outline
          : Icons.notifications_active_outlined,
      accent: items.isEmpty ? StatusTone.of(context, 'Present').content : tone.content,
      title: 'Needs attention',
      subtitle: items.isEmpty
          ? 'Nothing is waiting and nothing is missing.'
          : 'What is waiting, and what is not set up yet.',
      children: items.isEmpty
          ? [
              Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: StatusTone.of(context, 'Present').content,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      'Requests are cleared, every campus has a boundary, and '
                      'this term has class schedules.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ]
          : items,
    );

    final shortcuts = _hubPanel(
      icon: Icons.bolt_outlined,
      accent: theme.colorScheme.primary,
      title: 'Start here',
      subtitle: 'The work that begins on this screen.',
      children: [
        _hubRow(
          icon: Icons.upload_file_outlined,
          color: AppColors.forestGreen,
          title: 'Import accounts',
          subtitle: 'Students and parents from the masterlist',
          action: 'Open',
          onTap: _openBulkAccounts,
        ),
        _hubRow(
          icon: Icons.calendar_month_outlined,
          color: AppColors.accentGreen,
          title: 'Class schedules',
          subtitle: 'The hours that decide the daily schedule and late',
          action: 'Open',
          onTap: _openSchedules,
        ),
        _hubRow(
          icon: Icons.location_city_outlined,
          color: AppColors.warmGold,
          title: 'Campus boundaries',
          subtitle: 'The polygon a time in is checked against',
          action: 'Open',
          onTap: _openCampuses,
        ),
      ],
    );

    final chart = AttendanceTrendChart(
      token: widget.token,
      totalStudents: _count('totalStudents'),
    );

    // Phone: what needs doing, then the week, then the shortcuts.
    if (width <= 1000) {
      return Column(
        children: [
          attention,
          const SizedBox(height: AppSpace.md),
          chart,
          const SizedBox(height: AppSpace.md),
          shortcuts,
        ],
      );
    }
    // Laptop: the two lists stacked on the left, the chart on the right.
    // Side by side, the shorter list used to leave a tall empty space under
    // it; stacked, they fill the column the chart stands beside.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              attention,
              const SizedBox(height: AppSpace.md),
              shortcuts,
            ],
          ),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(child: chart),
      ],
    );
  }

  /// The school's shield and the app's name, set as a mark rather than as
  /// plain title text.
  Widget _brand(Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(2),
            child: Image.asset(
              'assets/benilde_shield.png',
              width: 26,
              height: 26,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Text(
          'BenildeSafe',
          style: TextStyle(
            color: color,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }

  /// The green band at the top of the dashboard: the greeting, and the date
  /// and time, on the school's colour. On a phone it runs edge to edge under
  /// the app bar; on a wide screen it is a rounded panel that also carries
  /// the notification bell and refresh, which there is no app bar to hold.
  Widget _brandBand({bool wide = false}) {
    final name = widget.fullName.trim().isNotEmpty
        ? widget.fullName.trim()
        : 'Administrator';
    const onBrand = Colors.white;
    return Container(
      width: double.infinity,
      padding: wide
          ? const EdgeInsets.symmetric(
              horizontal: AppSpace.xl,
              vertical: AppSpace.lg,
            )
          : const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.sm,
              AppSpace.lg,
              AppSpace.xl,
            ),
      decoration: BoxDecoration(
        color: AppColors.forestGreen,
        borderRadius: wide
            ? BorderRadius.circular(AppRadius.card)
            : const BorderRadius.vertical(
                bottom: Radius.circular(AppRadius.card + 8),
              ),
      ),
      child: wide ? _bandRowWide(name) : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProfileAvatar(
                name: name,
                radius: 24,
                photo: ProfileState.instance.photo,
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome,',
                      style: TextStyle(
                        color: onBrand.withValues(alpha: 0.8),
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: onBrand,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          const BrandClock(inRow: true),
        ],
      ),
    );
  }

  /// The wide band's content: one row, greeting on the left, the clock and
  /// the two actions on the right.
  Widget _bandRowWide(String name) {
    const onBrand = Colors.white;
    // White icons for the bell and refresh on the green. A Material 3 icon
    // button takes its colour from the button theme, not the icon theme.
    return IconButtonTheme(
      data: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: onBrand),
      ),
      child: Row(
        children: [
          ProfileAvatar(
            name: name,
            radius: 24,
            photo: ProfileState.instance.photo,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, $name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: onBrand,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  'Campus safety and attendance',
                  style: TextStyle(
                    color: onBrand.withValues(alpha: 0.8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.md),
          const BrandClock(),
          const SizedBox(width: AppSpace.sm),
          NotificationButton(token: widget.token),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh dashboard',
            onPressed: _isLoading ? null : _loadSummary,
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
          final padding = width < 400 ? AppSpace.md : AppSpace.xl;

          final content = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isWide) ...[
                    _Reveal(order: 0, child: _brandBand(wide: true)),
                    const SizedBox(height: AppSpace.lg),
                  ],
                  _Reveal(
                    order: 1,
                    child: _buildStatsGrid(width - padding * 2),
                  ),
                  const SizedBox(height: AppSpace.md),
                  _Reveal(
                    order: 2,
                    child: _attentionCard(width - padding * 2),
                  ),
                ],
              ),
            ),
          );

          if (isWide) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              // Less room above than around: there is no app bar on a wide
              // screen, so the greeting should start near the top rather
              // than float in a band of nothing.
              padding: EdgeInsets.fromLTRB(
                padding,
                AppSpace.md,
                padding,
                padding,
              ),
              child: content,
            );
          }

          // On a phone the green band runs edge to edge under the app bar,
          // and the figures start just below it.
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                _Reveal(order: 0, child: _brandBand()),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    AppSpace.lg,
                    padding,
                    padding,
                  ),
                  child: content,
                ),
              ],
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
      backgroundColor: AppColors.forestGreen,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      iconTheme: const IconThemeData(color: Colors.white),
      actionsIconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: AppSpace.lg,
      title: _brand(Colors.white),
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
            // Stretched to the full height. Centred (the default), the
            // dashboard shrank to its own height whenever it was shorter
            // than the window and floated in the middle, which left a band
            // of empty space above the greeting.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Sidebar(
                pendingChildLinks: _pendingChildLinks,
                onUsers: _openUsers,
                onBulkAccounts: _openBulkAccounts,
                onAttendance: _openAttendance,
                onSchedules: _openSchedules,
                onCampuses: _openCampuses,
                onChildLinks: _openChildLinkRequests,
                onReports: _openReports,
                onAccount: _openAccount,
                onSignOut: _confirmSignOut,
              ),
              const VerticalDivider(width: 1),
              // No app bar on a wide screen. It only repeated the name that
              // the sidebar already carries, and left it floating above the
              // greeting with two icons stranded at the far edge. The two
              // actions moved into the header beside the clock.
              Expanded(child: _dashboardBody(true)),
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
            label: 'Daily',
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


/// Counts from zero up to [value] the first time a figure arrives.
///
/// The count is not decoration: it is what makes a page of numbers feel like
/// it has just been read from the server rather than printed last week. It
/// runs once per value, so a refresh that changes nothing stays still.
class _CountUp extends StatelessWidget {
  final int value;
  final TextStyle? style;
  final String Function(int) format;

  const _CountUp({
    required this.value,
    required this.format,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Text(format(value), style: style);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, shown, _) =>
          Text(format(shown.round()), style: style),
    );
  }
}

/// Fades a panel in and lifts it a little into place, [order] steps after the
/// one before it.
///
/// One sequence when the dashboard opens, and nothing after. Entrances on
/// every scroll are the thing that makes a page feel like it is performing
/// rather than working.
class _Reveal extends StatelessWidget {
  final int order;
  final Widget child;

  const _Reveal({required this.order, required this.child});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + order * 70),
      curve: Curves.easeOutCubic,
      builder: (context, t, inner) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: inner),
      ),
      child: child,
    );
  }
}

/// Wraps anything that answers to the pointer: the border warms, the surface
/// lifts a little, and the cursor becomes a hand.
class _Hoverable extends StatefulWidget {
  final Widget Function(BuildContext context, bool hovered) builder;
  final VoidCallback? onTap;

  const _Hoverable({required this.builder, this.onTap});

  @override
  State<_Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<_Hoverable> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final content = widget.builder(context, _hovered);
    return MouseRegion(
      cursor: widget.onTap == null
          ? MouseCursor.defer
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.onTap == null
          ? content
          : GestureDetector(onTap: widget.onTap, child: content),
    );
  }
}


class _Sidebar extends StatelessWidget {
  /// Shown as a badge beside Child link requests. Null while it is unknown.
  final int? pendingChildLinks;

  final VoidCallback onUsers;
  final VoidCallback onBulkAccounts;
  final VoidCallback onAttendance;
  final VoidCallback onSchedules;
  final VoidCallback onCampuses;
  final VoidCallback onChildLinks;
  final VoidCallback onReports;
  final VoidCallback onAccount;
  final VoidCallback onSignOut;

  const _Sidebar({
    required this.pendingChildLinks,
    required this.onUsers,
    required this.onBulkAccounts,
    required this.onAttendance,
    required this.onSchedules,
    required this.onCampuses,
    required this.onChildLinks,
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
          // The school's mark on its green, level with the green band at the
          // top of the dashboard, so the two read as one header across the
          // whole width instead of a plain label beside a coloured panel.
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg,
              vertical: AppSpace.lg,
            ),
            decoration: BoxDecoration(
              color: AppColors.forestGreen,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(3),
                    child: Image.asset(
                      'assets/benilde_shield.png',
                      width: 34,
                      height: 34,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'BenildeSafe',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      Text(
                        'Administrator',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                // The headings are not decoration. They say what kind of work
                // each item belongs to, so an administrator looking for the
                // campus polygon does not have to read nine labels to find it.
                _sectionLabel(context, 'Overview'),
                _navItem(
                  context,
                  icon: Icons.dashboard_outlined,
                  activeIcon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  selected: true,
                  onTap: null,
                ),
                _sectionLabel(context, 'Accounts'),
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
                  label: 'Import accounts',
                  onTap: onBulkAccounts,
                ),
                _navItem(
                  context,
                  icon: Icons.family_restroom_outlined,
                  activeIcon: Icons.family_restroom_rounded,
                  label: 'Child link requests',
                  badge: pendingChildLinks,
                  onTap: onChildLinks,
                ),
                _sectionLabel(context, 'Campus'),
                _navItem(
                  context,
                  icon: Icons.fact_check_outlined,
                  activeIcon: Icons.fact_check_rounded,
                  label: 'Daily records',
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
                _sectionLabel(context, 'Reports'),
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

  /// The small heading above a group of links.
  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
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
    int? badge,
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
          hoverColor: (danger ? scheme.error : scheme.primary).withValues(
            alpha: 0.08,
          ),
          mouseCursor: onTap == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
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
                // How many are waiting, where the work is. Nothing is shown
                // when the count is zero or not known yet.
                if ((badge ?? 0) > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.error.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      '$badge',
                      style: TextStyle(
                        color: scheme.error,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
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