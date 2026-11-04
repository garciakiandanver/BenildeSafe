import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/profile_state.dart';
import '../services/session_service.dart';
import '../widgets/app_ui.dart';
import '../widgets/daily_schedule_card.dart';
import 'account_settings_screen.dart';
import 'notifications_screen.dart';
import 'teacher_class_schedule_screen.dart';

/// Home screen of a teacher.
///
/// Teachers do not record their own attendance. They see the classes they
/// teach and the attendance of the students in those classes.
class TeacherDashboardScreen extends StatefulWidget {
  final String token;
  final String email;
  final String fullName;
  final String firstName;
  final Future<void> Function() onSignOut;

  const TeacherDashboardScreen({
    super.key,
    required this.token,
    required this.email,
    required this.onSignOut,
    this.fullName = '',
    this.firstName = '',
  });

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  int _selectedNavigationIndex = 0;
  bool _isLoading = true;
  String _error = '';
  List<Map<String, dynamic>> _classes = [];

  String get _displayName =>
      widget.fullName.trim().isNotEmpty ? widget.fullName.trim() : widget.email;

  String get _firstName =>
      SessionService.resolveFirstName(widget.firstName, widget.fullName);

  @override
  void initState() {
    super.initState();
    _releaseKeyboard();
    ProfileState.instance.addListener(_onProfileChanged);
    ProfileState.instance.refresh(widget.token);
    _loadClasses();
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

  @override
  void dispose() {
    ProfileState.instance.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadClasses() async {
    setState(() {
      _isLoading = true;
      _error = '';
    });
    try {
      final result = await ApiService.getMyClassSchedule(token: widget.token);
      if (!mounted) return;
      setState(() {
        _classes = _groupClasses(result['schedules'] as List<dynamic>? ?? []);
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

  // The server returns one row per weekly meeting. Count a subject taught to
  // one course / year / section as a single class, the same way the class
  // schedule screen does.
  List<Map<String, dynamic>> _groupClasses(List<dynamic> schedules) {
    final groups = <String, Map<String, dynamic>>{};
    for (final item in schedules) {
      final meeting = Map<String, dynamic>.from(item as Map);
      final key = [
        meeting['course'],
        meeting['year_level'],
        meeting['section'],
        meeting['subject'],
      ].map((value) => (value?.toString() ?? '').trim().toUpperCase()).join('|');
      groups.putIfAbsent(key, () => meeting);
    }
    return groups.values.toList();
  }

  // How many different subjects the teacher handles, and how many groups.
  int get _subjectCount =>
      _classes.map((item) => item['subject']?.toString() ?? '').toSet().length;

  void _openClasses() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => TeacherClassScheduleScreen(token: widget.token),
      ),
    ).then((_) {
      if (mounted) setState(() => _selectedNavigationIndex = 0);
    });
  }

  void _openProfile() {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (context) => AccountSettingsScreen(
          email: widget.email,
          role: 'Teacher',
          fullName: widget.fullName,
          token: widget.token,
          onSignOut: widget.onSignOut,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() => _selectedNavigationIndex = 0);
    });
  }

  void _selectNavigation(int index) {
    if (index == 0) {
      setState(() => _selectedNavigationIndex = 0);
      return;
    }
    setState(() => _selectedNavigationIndex = index);
    if (index == 1) {
      _openClasses();
    } else {
      _openProfile();
    }
  }

  /// "Hello, Ana", the same greeting as the student and parent homes.
  String get _greeting {
    final name = _firstName.trim().isNotEmpty ? _firstName : _displayName;
    return 'Hello, $name';
  }

  Widget _statTile(
    ThemeData theme, {
    required IconData icon,
    required int? value,
    required String label,
    VoidCallback? onTap,
  }) {
    return Expanded(
      child: Hoverable(
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
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.block),
                ),
                child: Icon(icon, size: 18, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: AppSpace.sm),
              value == null
                  ? Text(
                      '—',
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
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One class: the subject, and the course and year it is taught to.
  Widget _classRow(ThemeData theme, Map<String, dynamic> item) {
    final year = item['year_level']?.toString().trim() ?? '';
    final group = [
      item['course']?.toString().trim() ?? '',
      if (year.isNotEmpty) 'Year $year',
    ].where((value) => value.isNotEmpty).join('  ·  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Hoverable(
        onTap: _openClasses,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: hovered
                ? theme.colorScheme.primary.withValues(alpha: 0.06)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.4,
                  ),
            borderRadius: BorderRadius.circular(AppRadius.block),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.block),
                ),
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['subject']?.toString() ?? 'Class',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (group.isNotEmpty)
                      Text(
                        group,
                        maxLines: 1,
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
      ),
    );
  }

  Widget _classesCard(ThemeData theme) {
    if (_isLoading) {
      return const AppPanel(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error.isNotEmpty) {
      return AppPanel(
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpace.md),
            const Expanded(child: Text('Could not load your classes.')),
            TextButton(onPressed: _loadClasses, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_classes.isEmpty) {
      return const AppPanel(
        padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
        child: EmptyState(
          icon: Icons.menu_book_outlined,
          title: 'No classes assigned',
          message:
              'The classes you teach this term will show up here once the '
              'administrator assigns them.',
        ),
      );
    }

    return AppPanel(
      padding: const EdgeInsets.all(AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            title: 'Your classes',
            subtitle:
                'Open a class to see which students are on campus and their '
                'attendance for the day, week or month.',
            trailing: TextButton(
              onPressed: _openClasses,
              child: const Text('Open all'),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          ..._classes.take(4).map((item) => _classRow(theme, item)),
          if (_classes.length > 4)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                'and ${_classes.length - 4} more',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: brandAppBar(
        actions: [
          NotificationButton(token: widget.token),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadClasses,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadClasses,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final padding = constraints.maxWidth < 400
                ? AppSpace.lg
                : AppSpace.xl;
            final width = (constraints.maxWidth - padding * 2).clamp(
              0.0,
              960.0,
            );
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                Reveal(
                  order: 0,
                  child: BrandBand(
                    greeting: _greeting,
                    subtitle: 'Your classes and students today',
                    name: _displayName,
                    photo: ProfileState.instance.photo,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    padding,
                    AppSpace.lg,
                    padding,
                    padding,
                  ),
                  child: Center(
                  child: SizedBox(
                    width: width,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Reveal(
                          order: 1,
                          child: Row(
                            children: [
                              _statTile(
                                theme,
                                icon: Icons.menu_book_outlined,
                                value: _isLoading ? null : _subjectCount,
                                label: _subjectCount == 1
                                    ? 'Subject'
                                    : 'Subjects',
                                onTap: _openClasses,
                              ),
                              const SizedBox(width: AppSpace.sm),
                              _statTile(
                                theme,
                                icon: Icons.groups_outlined,
                                value: _isLoading ? null : _classes.length,
                                label: _classes.length == 1
                                    ? 'Class'
                                    : 'Classes',
                                onTap: _openClasses,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        Reveal(
                          order: 2,
                          child: DailyScheduleCard(
                            token: widget.token,
                            isTeacher: true,
                          ),
                        ),
                        const SizedBox(height: AppSpace.md),
                        Reveal(order: 3, child: _classesCard(theme)),
                      ],
                    ),
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
        onDestinationSelected: _selectNavigation,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            label: 'Classes',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
