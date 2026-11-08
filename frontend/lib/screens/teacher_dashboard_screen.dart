import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/profile_state.dart';
import '../services/session_service.dart';
import '../utils/dtr.dart';
import '../utils/manila_time.dart';
import '../widgets/app_ui.dart';
import '../widgets/dtr_table.dart';
import 'account_settings_screen.dart';
import 'notifications_screen.dart';

/// Home screen of a teacher.
///
/// Teachers do not record their own attendance. They choose a course and a year
/// level and read the daily time record (DTR) of its students, one month at a
/// time. The report is read only.
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

  int _selectedNavigationIndex = 0;
  bool _isLoadingFilters = true;
  bool _isLoadingStudents = false;
  String _error = '';
  String _studentsError = '';

  // [{course_code, course_name, year_levels: [..]}]
  List<Map<String, dynamic>> _courses = [];

  /// The teacher's department; empty until the administrator sets it.
  String _department = '';
  bool _hasDepartment = true;
  String? _course;
  String? _yearLevel;
  late DateTime _month = _firstOfThisMonth();
  List<Map<String, dynamic>> _students = [];

  static DateTime _firstOfThisMonth() {
    final now = ManilaTime.now();
    return DateTime(now.year, now.month);
  }

  String get _displayName =>
      widget.fullName.trim().isNotEmpty ? widget.fullName.trim() : widget.email;

  String get _firstName =>
      SessionService.resolveFirstName(widget.firstName, widget.fullName);

  String get _monthKey =>
      '${_month.year.toString().padLeft(4, '0')}-'
      '${_month.month.toString().padLeft(2, '0')}';

  List<String> get _yearLevels {
    final match = _courses.where((item) => item['course_code'] == _course);
    if (match.isEmpty) return const [];
    return [
      for (final level in (match.first['year_levels'] as List<dynamic>? ?? []))
        level.toString(),
    ];
  }

  @override
  void initState() {
    super.initState();
    _releaseKeyboard();
    ProfileState.instance.addListener(_onProfileChanged);
    ProfileState.instance.refresh(widget.token);
    _loadFilters();
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

  Future<void> _loadFilters() async {
    setState(() {
      _isLoadingFilters = true;
      _error = '';
    });
    try {
      final result = await ApiService.getTeacherFilters(token: widget.token);
      if (!mounted) return;
      final courses = [
        for (final item in (result['courses'] as List<dynamic>? ?? []))
          Map<String, dynamic>.from(item as Map),
      ];
      setState(() {
        _courses = courses;
        _hasDepartment = result['department'] != null;
        _department = (result['department']?['name'] ?? '').toString();
        _isLoadingFilters = false;
        final stillThere = courses.any((c) => c['course_code'] == _course);
        if (!stillThere) {
          _course = courses.isEmpty
              ? null
              : courses.first['course_code']?.toString();
          _yearLevel = null;
        }
        if (_course != null && !_yearLevels.contains(_yearLevel)) {
          _yearLevel = _yearLevels.isEmpty ? null : _yearLevels.first;
        }
      });
      if (_course != null && _yearLevel != null) await _loadStudents();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isLoadingFilters = false;
      });
    }
  }

  Future<void> _loadStudents() async {
    final course = _course;
    final yearLevel = _yearLevel;
    if (course == null || yearLevel == null) return;
    setState(() {
      _isLoadingStudents = true;
      _studentsError = '';
    });
    try {
      final result = await ApiService.getTeacherStudentsDtr(
        token: widget.token,
        course: course,
        yearLevel: yearLevel,
        month: _monthKey,
      );
      if (!mounted) return;
      setState(() {
        _students = [
          for (final item in (result['students'] as List<dynamic>? ?? []))
            Map<String, dynamic>.from(item as Map),
        ];
        _isLoadingStudents = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _studentsError = error.toString().replaceFirst('Exception: ', '');
        _isLoadingStudents = false;
      });
    }
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _loadStudents();
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
    _openProfile();
  }

  /// "Hello, Ana", the same greeting as the student and parent homes.
  String get _greeting {
    final name = _firstName.trim().isNotEmpty ? _firstName : _displayName;
    return 'Hello, $name';
  }

  Widget _filters(ThemeData theme) {
    return AppPanel(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading(
            title: 'Student attendance',
            subtitle:
                'Choose a course and a year level to read the daily time '
                'record of its students.',
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('course-$_course'),
                  initialValue: _course,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Course'),
                  items: [
                    for (final course in _courses)
                      DropdownMenuItem<String>(
                        value: course['course_code']?.toString(),
                        child: Text(
                          course['course_code']?.toString() ?? '',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _course = value;
                      _yearLevel = _yearLevels.isEmpty
                          ? null
                          : _yearLevels.first;
                    });
                    _loadStudents();
                  },
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey('year-$_course-$_yearLevel'),
                  initialValue: _yearLevel,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Year level'),
                  items: [
                    for (final level in _yearLevels)
                      DropdownMenuItem<String>(
                        value: level,
                        child: Text('Year $level'),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _yearLevel = value);
                    _loadStudents();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous month',
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: _isLoadingStudents ? null : () => _changeMonth(-1),
              ),
              Text(
                '${_months[_month.month - 1]} ${_month.year}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: _isLoadingStudents ? null : () => _changeMonth(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _studentPanel(ThemeData theme, Map<String, dynamic> student) {
    final recorded = [
      for (final item in (student['days'] as List<dynamic>? ?? []))
        DtrDay.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
    // Every date of the month up to today, newest first, like a paper DTR.
    final days = fillCalendar(
      recorded,
      from: _month,
      to: DateTime(_month.year, _month.month + 1, 0),
    ).reversed.toList();
    final onCampus = (student['days_on_campus'] as num?)?.toInt() ?? 0;
    final minutes = (student['total_minutes'] as num?)?.toInt() ?? 0;
    final number = student['student_number']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppPanel(
        padding: EdgeInsets.zero,
        child: Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.xs,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpace.md,
              0,
              AppSpace.md,
              AppSpace.md,
            ),
            title: Text(
              student['name']?.toString() ?? 'Student',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              [
                if (number.isNotEmpty) number,
                '$onCampus ${onCampus == 1 ? 'day' : 'days'}',
                formatDuration(minutes),
              ].join('  ·  '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            children: [
              if (recorded.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                  child: Text(
                    'No attendance this month.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                DtrTable(days: days),
            ],
          ),
        ),
      ),
    );
  }

  Widget _studentsSection(ThemeData theme) {
    if (_isLoadingFilters) {
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
            const Expanded(child: Text('Could not load the course list.')),
            TextButton(onPressed: _loadFilters, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (!_hasDepartment) {
      return const AppPanel(
        padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
        child: EmptyState(
          icon: Icons.apartment_outlined,
          title: 'No department yet',
          message:
              'Your account has no department yet. Ask the administrator to '
              'set your department.',
        ),
      );
    }
    if (_courses.isEmpty) {
      return const AppPanel(
        padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
        child: EmptyState(
          icon: Icons.groups_outlined,
          title: 'No students yet',
          message:
              'The students will show up here once the administrator imports '
              'the masterlist.',
        ),
      );
    }
    if (_isLoadingStudents) {
      return const AppPanel(
        padding: EdgeInsets.all(28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_studentsError.isNotEmpty) {
      return AppPanel(
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpace.md),
            Expanded(child: Text(_studentsError)),
            TextButton(onPressed: _loadStudents, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_students.isEmpty) {
      return const AppPanel(
        padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
        child: EmptyState(
          icon: Icons.groups_outlined,
          title: 'No students found',
          message: 'There are no students in this course and year level.',
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final student in _students) _studentPanel(theme, student),
      ],
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
            onPressed: _isLoadingFilters ? null : _loadFilters,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadFilters,
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
                    subtitle: _department.isEmpty
                        ? 'The daily time record of your students'
                        : 'The daily time record of the $_department',
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
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Reveal(order: 1, child: _filters(theme)),
                          const SizedBox(height: AppSpace.md),
                          Reveal(order: 2, child: _studentsSection(theme)),
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
            icon: Icon(Icons.person_outline_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
