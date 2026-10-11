import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'login_screen.dart';

import '../services/api_service.dart';
import '../services/location_service.dart';
import 'attendance_history_screen.dart';
import 'notifications_screen.dart';
import 'teacher_class_schedule_screen.dart';
import '../widgets/app_ui.dart';
import 'account_settings_screen.dart';

class AttendanceScreen extends StatefulWidget {
  final String token;
  final String email;
  final String fullName;
  final bool isTeacher;

  const AttendanceScreen({
    super.key,
    required this.token,
    required this.email,
    this.fullName = '',
    this.isTeacher = false,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  StreamSubscription<Position>? _locationSubscription;
  Timer? _heartbeatTimer;
  bool _isSendingUpdate = false;
  bool _isConfirming = false;
  int _selectedNavigationIndex = 0;

  bool _isCheckedIn = false;
  bool _isInitializing = true;
  bool _isLoading = false;
  bool _isDetectingCampus = false;
  bool _canCheckIn = false;

  String _status = 'Not checked in.';
  String _campus = '';
  String _detectedCampus = '';
  String _campusDetectionMessage = '';
  String _outsideSince = '';
  String get _displayName =>
      widget.fullName.trim().isNotEmpty ? widget.fullName.trim() : widget.email;

  String get _locationLabel {
    final status = _status.toLowerCase();
    final detectionMessage = _campusDetectionMessage.toLowerCase();
    if (_isLoading ||
        _isDetectingCampus ||
        status.contains('getting your location')) {
      return 'Checking Location...';
    }
    if (status.contains('permission') ||
        _campusDetectionMessage.toLowerCase().contains('permission')) {
      return 'Location Permission Required';
    }
    if (_outsideSince.isNotEmpty ||
        (!_isCheckedIn &&
            (status.contains('outside campus') ||
                detectionMessage.contains('outside all configured campus')))) {
      return 'Outside Campus';
    }
    if (_isCheckedIn || _detectedCampus.isNotEmpty) return 'Inside Campus';
    return 'Location not checked';
  }

  @override
  void initState() {
    super.initState();
    _loadActiveAttendance();
  }

  Future<void> _loadActiveAttendance() async {
    try {
      final result = await ApiService.getActiveAttendance(token: widget.token);

      if (!mounted) return;

      if (result['active'] == true) {
        setState(() {
          _isCheckedIn = true;
          _canCheckIn = false;

          _campus = result['campus']?['name'] ?? 'Unknown campus';
          _status = 'Active attendance session.';
          _outsideSince = result['outside_since']?.toString() ?? '';
        });

        _startLocationMonitoring();
      } else {
        setState(() {
          _isCheckedIn = false;
          _canCheckIn = true;
          _campus = '';
          _outsideSince = '';
          _status = 'Time in when you are inside a campus boundary.';
        });
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _status = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _refreshAttendance() async {
    if (!mounted) return;
    setState(() => _isInitializing = true);
    await _loadActiveAttendance();
  }

  Future<void> _detectCampus() async {
    if (_isLoading || _isDetectingCampus) return;
    setState(() {
      _isDetectingCampus = true;
      _campusDetectionMessage = '';
    });
    try {
      final position = await LocationService.getCurrentLocation();
      if (position == null) {
        throw Exception('Location permission is required.');
      }

      final result = await ApiService.detectCampus(
        token: widget.token,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;
      final detected = result['campus']?['name']?.toString() ?? '';
      setState(() {
        _detectedCampus = detected;
        _campusDetectionMessage =
            result['message']?.toString() ??
            'Campus detected: ${detected.isEmpty ? 'Unknown campus' : detected}.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _detectedCampus = '';
        _campusDetectionMessage = error.toString().replaceFirst(
          'Exception: ',
          '',
        );
      });
    } finally {
      if (mounted) setState(() => _isDetectingCampus = false);
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  // Asks the user to confirm Time In / Time Out so a stray touch or a double
  // tap cannot record attendance by accident.
  Future<bool> _confirmAttendanceAction({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    if (_isConfirming) return false; // a box is already opening
    _isConfirming = true;
    var answered = false; // ignore a second tap while the box is closing
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                if (answered) return;
                answered = true;
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (answered) return;
                answered = true;
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
      return confirmed ?? false;
    } finally {
      _isConfirming = false;
    }
  }

  Future<void> _checkIn() async {
    final confirmed = await _confirmAttendanceAction(
      title: 'Confirm Time In',
      message:
          'Do you want to time in now? Your location will be used to confirm that you are inside the campus.',
      confirmLabel: 'Time In',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _isLoading = true;
      _status = 'Getting your location...';
    });

    try {
      final position = await LocationService.getCurrentLocation();

      if (position == null) {
        throw Exception('Location permission is required.');
      }

      final result = await ApiService.checkIn(
        token: widget.token,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (!mounted) return;
      setState(() {
        _isCheckedIn = true;
        _canCheckIn = false;
        _campus = result['campus']?['name'] ?? 'Unknown campus';
        _detectedCampus = _campus;
        _outsideSince = '';
        _status = [
          result['message'] ?? 'Check-in successful.',
          if (result['notificationWarning'] != null)
            result['notificationWarning'],
        ].join(' ');
      });

      _startLocationMonitoring();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startLocationMonitoring() {
    _locationSubscription?.cancel();
    _heartbeatTimer?.cancel();

    _locationSubscription = LocationService.locationStream().listen(
      _sendLocationUpdate,
    );

    // The location stream only reports after the phone moves 10 metres, so a
    // student standing still outside the campus would never be warned or timed
    // out on time. Also report the current position every minute.
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!_isCheckedIn || _isSendingUpdate) return;
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 20),
          ),
        );
        await _sendLocationUpdate(position);
      } catch (error) {
        debugPrint('Location report skipped: $error');
      }
    });
  }

  Future<void> _sendLocationUpdate(Position position) async {
    if (!_isCheckedIn || _isSendingUpdate) return;
    _isSendingUpdate = true;

    try {
      final result = await ApiService.updateLocation(
        token: widget.token,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (!mounted) return;

      setState(() {
        _status = result['message'] ?? result['status'] ?? 'Location updated.';
        if (result['notificationWarning'] != null) {
          _status = '$_status ${result['notificationWarning']}';
        }

        _outsideSince = result['outside_since']?.toString() ?? '';

        if (result['status'] == 'Timed Out') {
          _isCheckedIn = false;
          _canCheckIn = true;
          _outsideSince = '';
          _locationSubscription?.cancel();
          _heartbeatTimer?.cancel();
        }
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _status = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      _isSendingUpdate = false;
    }
  }

  Future<void> _checkOut() async {
    final confirmed = await _confirmAttendanceAction(
      title: 'Confirm Time Out',
      message:
          'Do you want to time out now? You can time in again later while you are inside a campus boundary.',
      confirmLabel: 'Time Out',
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _isLoading = true;
      _status = 'Getting your location...';
    });

    try {
      final position = await LocationService.getCurrentLocation();

      if (position == null) {
        throw Exception('Location permission is required.');
      }

      final result = await ApiService.checkOut(
        token: widget.token,
        latitude: position.latitude,
        longitude: position.longitude,
      );

      await _locationSubscription?.cancel();
      _heartbeatTimer?.cancel();

      if (!mounted) return;
      setState(() {
        _isCheckedIn = false;
        _canCheckIn = true;
        _outsideSince = '';
        _status = [
          result['message'] ?? 'Check-out successful.',
          'You can time in again while inside a campus boundary.',
          if (result['notificationWarning'] != null)
            result['notificationWarning'],
        ].join(' ');
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _signOut() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  void _selectNavigation(int index) {
    if (index == 0 || index == 1) {
      setState(() => _selectedNavigationIndex = index);
      return;
    }

    // Students: 2 = History, 3 = Profile.
    // Teachers: 2 = Schedule, 3 = History, 4 = Profile.
    final profileIndex = widget.isTeacher ? 4 : 3;
    final Widget destination;
    if (index == profileIndex) {
      destination = AccountSettingsScreen(
        email: widget.email,
        role: widget.isTeacher ? 'Teacher' : 'Student',
        fullName: widget.fullName,
        token: widget.token,
        onSignOut: _signOut,
      );
    } else if (widget.isTeacher && index == 2) {
      destination = TeacherClassScheduleScreen(token: widget.token);
    } else {
      destination = AttendanceHistoryScreen(token: widget.token);
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => destination),
    ).then((_) {
      if (mounted) setState(() => _selectedNavigationIndex = 0);
    });
  }

  Widget _buildAttendancePage(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = MaterialLocalizations.of(
      context,
    ).formatMediumDate(DateTime.now());
    final canTakeAction = _isCheckedIn || _canCheckIn;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(constraints.maxWidth < 400 ? 16 : 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: EdgeInsets.all(constraints.maxWidth < 400 ? 22 : 30),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF005A23), Color(0xFF003D19)],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: const Icon(
                              Icons.fact_check_outlined,
                              color: Color(0xFFE6C64A),
                              size: 25,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Attendance for today',
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  date,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _isCheckedIn
                            ? 'You’re checked in'
                            : 'Ready when you are',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isCheckedIn
                            ? 'Your attendance session is active.'
                            : 'Time in while inside a campus boundary.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CURRENT STATUS',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _attendanceDetailRow(
                          context,
                          Icons.location_on_outlined,
                          'Campus location',
                          _isCheckedIn
                              ? _campus
                              : _detectedCampus.isNotEmpty
                              ? _detectedCampus
                              : _locationLabel,
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              StatusBadge(label: _locationLabel),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: _isLoading || _isDetectingCampus
                                    ? null
                                    : _detectCampus,
                                icon: _isDetectingCampus
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.my_location_outlined,
                                        size: 16,
                                      ),
                                label: Text(
                                  _isDetectingCampus
                                      ? 'Detecting'
                                      : 'Detect campus',
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_campusDetectionMessage.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            _campusDetectionMessage,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _attendanceDetailRow(
                          context,
                          Icons.info_outline_rounded,
                          'Attendance update',
                          _status,
                          null,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Record attendance',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          canTakeAction
                              ? 'Time in and out are recorded only inside a configured campus boundary.'
                              : 'There is no check-in or check-out action available right now.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            onPressed: _isLoading || !canTakeAction
                                ? null
                                : _isCheckedIn
                                ? _checkOut
                                : _checkIn,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    _isCheckedIn
                                        ? Icons.logout_rounded
                                        : Icons.login_rounded,
                                  ),
                            label: Text(
                              _isLoading
                                  ? 'Checking location...'
                                  : _isCheckedIn
                                  ? 'Time Out'
                                  : _canCheckIn
                                  ? 'Time In'
                                  : 'No attendance action available',
                            ),
                          ),
                        ),
                      ],
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

  Widget _attendanceDetailRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Widget? trailing,
  ) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary, size: 21),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 3),
              Text(value, style: theme.textTheme.bodyMedium),
              if (trailing != null && trailing is! StatusBadge) ...[
                const SizedBox(height: 4),
                trailing,
              ],
            ],
          ),
        ),
        if (trailing is StatusBadge) trailing,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _selectedNavigationIndex == 1
                ? 'Attendance'
                : widget.isTeacher
                ? 'Teacher dashboard'
                : 'BenildeSafe',
          ),
          actions: [
            NotificationButton(token: widget.token),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh attendance',
              onPressed: _isInitializing ? null : _refreshAttendance,
            ),
          ],
        ),

        body: _isInitializing
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _refreshAttendance,
                child: _selectedNavigationIndex == 1
                    ? _buildAttendancePage(context)
                    : LayoutBuilder(
                        builder: (context, constraints) => SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.all(
                            constraints.maxWidth < 400 ? 16 : 24,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      ProfileAvatar(
                                        name: _displayName,
                                        radius: 24,
                                      ),
                                      const SizedBox(width: 13),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.fullName.trim().isNotEmpty
                                                  ? 'Welcome back, ${widget.fullName.trim()}'
                                                  : 'Welcome back',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              MaterialLocalizations.of(
                                                context,
                                              ).formatMediumDate(
                                                DateTime.now(),
                                              ),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(17),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: Icon(
                                              Icons.location_on_outlined,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 13),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Campus location',
                                                  style: TextStyle(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  _campus.isEmpty
                                                      ? _locationLabel
                                                      : _campus,
                                                  style: TextStyle(
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.onSurface,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          StatusBadge(label: _locationLabel),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _TodayInfoCard(
                                          icon: Icons.access_time_rounded,
                                          label: 'Current time',
                                          value: TimeOfDay.now().format(
                                            context,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _TodayInfoCard(
                                          icon: Icons.fact_check_outlined,
                                          label: 'Attendance',
                                          value: _isCheckedIn
                                              ? 'Present'
                                              : _canCheckIn
                                              ? 'Ready to time in'
                                              : 'Not checked in',
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  Card(
                                    child: Padding(
                                      padding: EdgeInsets.all(
                                        constraints.maxWidth < 400 ? 18 : 26,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                width: 44,
                                                height: 44,
                                                decoration: BoxDecoration(
                                                  color: _isCheckedIn
                                                      ? const Color(0xFFE6F5EF)
                                                      : Theme.of(context)
                                                            .colorScheme
                                                            .primaryContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                ),
                                                child: Icon(
                                                  _isCheckedIn
                                                      ? Icons
                                                            .check_circle_outline
                                                      : Icons
                                                            .calendar_month_outlined,
                                                  color: _isCheckedIn
                                                      ? const Color(0xFF268664)
                                                      : Theme.of(
                                                          context,
                                                        ).colorScheme.primary,
                                                ),
                                              ),
                                              const SizedBox(width: 13),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      _isCheckedIn
                                                          ? 'You’re checked in'
                                                          : 'Your attendance',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .titleMedium
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      _isCheckedIn
                                                          ? 'Your attendance session is active.'
                                                          : 'Time in and out at an approved campus boundary.',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              if (_isCheckedIn)
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 6,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFE6F5EF,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                  ),
                                                  child: const Text(
                                                    'ACTIVE',
                                                    style: TextStyle(
                                                      color: Color(0xFF268664),
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      letterSpacing: 0.5,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 23),
                                          Text(
                                            _status,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                  height: 1.5,
                                                ),
                                          ),
                                          if (_campus.isNotEmpty) ...[
                                            const SizedBox(height: 10),
                                            _infoRow(
                                              context,
                                              Icons.location_on_outlined,
                                              _campus,
                                            ),
                                          ],
                                          if (_outsideSince.isNotEmpty) ...[
                                            const SizedBox(height: 12),
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFFF5E8),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.location_off_outlined,
                                                    size: 18,
                                                    color: Color(0xFFB67827),
                                                  ),
                                                  const SizedBox(width: 9),
                                                  Expanded(
                                                    child: Text(
                                                      'Outside campus since $_outsideSince',
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF80591E,
                                                        ),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          if (_isCheckedIn || _canCheckIn) ...[
                                            const SizedBox(height: 24),
                                            SizedBox(
                                              width: double.infinity,
                                              height: 52,
                                              child: ElevatedButton.icon(
                                                onPressed: _isLoading
                                                    ? null
                                                    : _isCheckedIn
                                                    ? _checkOut
                                                    : _checkIn,
                                                icon: _isLoading
                                                    ? const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                      )
                                                    : Icon(
                                                        _isCheckedIn
                                                            ? Icons
                                                                  .logout_rounded
                                                            : Icons
                                                                  .login_rounded,
                                                      ),
                                                label: Text(
                                                  _isLoading
                                                      ? 'Getting your location…'
                                                      : _isCheckedIn
                                                      ? 'Time Out'
                                                      : 'Time In',
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              'Your location is used to confirm you are at the campus.',
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
        bottomNavigationBar: NavigationBar(
          destinations: widget.isTeacher
              ? const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.fact_check_outlined),
                    label: 'Attendance',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.calendar_month_outlined),
                    label: 'Schedule',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history_rounded),
                    label: 'History',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    label: 'Profile',
                  ),
                ]
              : const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.fact_check_outlined),
                    label: 'Attendance',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.history_rounded),
                    label: 'History',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    label: 'Profile',
                  ),
                ],
          selectedIndex: _selectedNavigationIndex,
          onDestinationSelected: _selectNavigation,
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

class _TodayInfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _TodayInfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Icon(icon, color: scheme.primary, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}