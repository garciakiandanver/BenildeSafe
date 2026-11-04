import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'login_screen.dart';
import '../services/profile_state.dart';
import '../services/session_service.dart';
import '../widgets/daily_schedule_card.dart';

import '../services/api_service.dart';
import '../services/location_service.dart';
import 'attendance_history_screen.dart';
import 'notifications_screen.dart';
import 'teacher_dashboard_screen.dart';
import '../widgets/app_ui.dart';
import 'account_settings_screen.dart';
import '../utils/manila_time.dart';

class AttendanceScreen extends StatefulWidget {
  final String token;
  final String email;
  final String fullName;
  final String firstName;
  final bool isTeacher;

  const AttendanceScreen({
    super.key,
    required this.token,
    required this.email,
    this.fullName = '',
    this.firstName = '',
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

  String _status = 'Not checked in.';
  String _campus = '';
  String _detectedCampus = '';
  String _campusDetectionMessage = '';
  String _outsideSince = '';
  bool _confirmingOutside = false;

  // True once a location check has answered, so "not inside any campus" can
  // be told apart from "not checked yet".
  bool _hasReading = false;

  // Something the student must know after pressing a button: why a time in
  // failed, or that the parent could not be notified. Cleared on the next
  // press or location check.
  String _notice = '';

  // The campus is looked for once when the screen opens. A pull to refresh
  // does not repeat it on its own; the button on the campus card does.
  bool _hasAutoDetected = false;
  String get _displayName =>
      widget.fullName.trim().isNotEmpty ? widget.fullName.trim() : widget.email;

  String get _firstName {
    final live = ProfileState.instance.firstName;
    return live.isNotEmpty
        ? live
        : SessionService.resolveFirstName(widget.firstName, widget.fullName);
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

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
    if (_hasReading) return 'Outside Campus';
    return 'Location not checked';
  }

  /// The one sentence under the badge.
  ///
  /// This used to be up to three: the last location check, the last thing the
  /// server said, and a note about the boundary. They were written at
  /// different moments, so they could disagree ("Outside Campus" above "You
  /// can time out here"), and a sentence from before a time out stayed on
  /// screen after it. Now one sentence is chosen from where things stand.
  String get _cardMessage {
    if (_isLoading) {
      return 'Getting your location. Hold still for a few seconds.';
    }
    if (_isDetectingCampus) return 'Checking where you are...';
    if (_isCheckedIn) {
      if (_outsideSince.isNotEmpty) {
        final left = ManilaTime.parse(_outsideSince);
        final deadline = left == null
            ? ''
            : ' before ${ManilaTime.clock(left.add(const Duration(minutes: 30)))}';
        return 'You left the campus. Go back inside$deadline, or you will be '
            'timed out automatically.';
      }
      return 'You are timed in. Press Time out when you leave the campus.';
    }
    if (_detectedCampus.isNotEmpty) {
      return 'You are inside $_detectedCampus. You can time in now.';
    }
    if (_campusDetectionMessage.isNotEmpty) return _campusDetectionMessage;
    return 'Press "Check my location" to see whether you are inside a campus.';
  }

  @override
  void initState() {
    super.initState();
    ProfileState.instance.addListener(_onProfileChanged);
    _releaseKeyboard();
    // Teachers do not record their own attendance, so none of the location
    // work below runs for them. They get the teacher dashboard instead.
    if (!widget.isTeacher) _loadActiveAttendance();
  }

  // Only let go of the focus when a text field really has it. Unfocusing on
  // every tap makes the browser open the keyboard again on some phones.
  void _dismissKeyboardIfOpen() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || focus is FocusScopeNode) return;
    focus.unfocus();
  }

  // Coming from the login or change password screen, the browser can keep the
  // old text field focused, so the keyboard pops up on every tap. Let go of it.
  void _releaseKeyboard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      TextInput.finishAutofillContext(shouldSave: false);
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    });
  }

  Future<void> _loadActiveAttendance() async {
    try {
      final result = await ApiService.getActiveAttendance(token: widget.token);

      if (!mounted) return;

      if (result['active'] == true) {
        setState(() {
          _isCheckedIn = true;

          _campus = result['campus']?['name'] ?? 'Unknown campus';
          _status = 'Active attendance session.';
          _outsideSince = result['outside_since']?.toString() ?? '';
        });

        _startLocationMonitoring();
      } else {
        setState(() {
          _isCheckedIn = false;
          _campus = '';
          _outsideSince = '';
          _status = 'Time in when you are inside a campus boundary.';
        });

        // Look for the campus straight away, so the student sees whether they
        // are inside before pressing anything. Without this the status on the
        // home screen stays unknown until the first time in.
        if (!_hasAutoDetected) {
          _hasAutoDetected = true;
          unawaited(_detectCampus());
        }
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _status = error.toString().replaceFirst('Exception: ', '');
        _notice = _status;
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

  // A reading with an error of this many meters or less is precise enough.
  static const double _goodAccuracyMeters = 20;

  // The first GPS reading is often rough (a saved or Wi-Fi based position that
  // can be tens or hundreds of meters off). Wait a few seconds for the phone to
  // settle on a precise one and use the most accurate reading seen. If nothing
  // better arrives, the first reading is used.
  Future<Position?> _getBestPosition() async {
    final first = await LocationService.getCurrentLocation();
    if (first == null || first.accuracy <= _goodAccuracyMeters) return first;

    var best = first;
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    try {
      final readings =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 0,
            ),
          ).timeout(
            const Duration(seconds: 12),
            onTimeout: (sink) => sink.close(),
          );
      await for (final reading in readings) {
        if (reading.accuracy < best.accuracy) best = reading;
        if (best.accuracy <= _goodAccuracyMeters ||
            DateTime.now().isAfter(deadline)) {
          break;
        }
      }
    } catch (error) {
      debugPrint('Precise location skipped: $error');
    }
    return best;
  }

  Future<void> _detectCampus() async {
    if (_isLoading || _isDetectingCampus) return;
    setState(() {
      _isDetectingCampus = true;
      _campusDetectionMessage = '';
      _notice = '';
    });
    try {
      final position = await _getBestPosition();
      if (position == null) {
        throw Exception('Location permission is required.');
      }

      final result = await ApiService.detectCampus(
        token: widget.token,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        isMocked: position.isMocked,
      );
      if (!mounted) return;
      final detected = result['campus']?['name']?.toString() ?? '';
      setState(() {
        _detectedCampus = detected;
        _hasReading = true;
        // A fresh reading replaces what an earlier time in attempt said, so
        // an old "outside campus" cannot outlive the student walking inside.
        if (!_isCheckedIn) _status = '';
        _campusDetectionMessage =
            result['message']?.toString() ??
            'Campus detected: ${detected.isEmpty ? 'Unknown campus' : detected}.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _detectedCampus = '';
        _hasReading = false;
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
    ProfileState.instance.removeListener(_onProfileChanged);
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
      _notice = '';
      _status =
          'Getting your location... hold still for a few seconds for a precise GPS fix.';
    });

    try {
      final position = await _getBestPosition();

      if (position == null) {
        throw Exception('Location permission is required.');
      }

      final result = await ApiService.checkIn(
        token: widget.token,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        isMocked: position.isMocked,
      );

      if (!mounted) return;
      setState(() {
        _isCheckedIn = true;
        _campus = result['campus']?['name'] ?? 'Unknown campus';
        _detectedCampus = _campus;
        _campusDetectionMessage = '';
        _outsideSince = '';
        _status = result['message'] ?? 'Check-in successful.';
        _notice = result['notificationWarning']?.toString() ?? '';
      });

      _startLocationMonitoring();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.toString().replaceFirst('Exception: ', '');
        _notice = _status;
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

  Future<void> _sendLocationUpdate(
    Position position, {
    bool confirmed = false,
  }) async {
    if (!_isCheckedIn || _isSendingUpdate) return;
    _isSendingUpdate = true;
    var needsConfirmation = false;

    try {
      final result = await ApiService.updateLocation(
        token: widget.token,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        isMocked: position.isMocked,
        confirmed: confirmed,
      );

      if (!mounted) return;

      // The first reading outside the campus is not trusted on its own (GPS can
      // jump). The server asks for a second reading before it records it.
      if (result['confirm_required'] == true) {
        needsConfirmation = true;
        return;
      }

      setState(() {
        _status = result['message'] ?? result['status'] ?? 'Location updated.';
        if (result['notificationWarning'] != null) {
          _status = '$_status ${result['notificationWarning']}';
        }

        _outsideSince = result['outside_since']?.toString() ?? '';

        if (result['status'] == 'Timed Out') {
          _isCheckedIn = false;
          _outsideSince = '';
          _campusDetectionMessage = '';
          _detectedCampus = '';
          _notice = 'You were timed out automatically because you stayed '
              'outside the campus.';
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
      if (needsConfirmation && mounted) unawaited(_confirmOutside());
    }
  }

  // Takes a fresh, precise reading a few seconds later and reports it as the
  // confirmation. Only a reading that is still outside starts the 30-minute
  // timer and alerts the parent.
  Future<void> _confirmOutside() async {
    if (_confirmingOutside) return;
    _confirmingOutside = true;
    try {
      await Future.delayed(const Duration(seconds: 15));
      if (!mounted || !_isCheckedIn) return;
      final position = await _getBestPosition();
      if (position == null || !mounted || !_isCheckedIn) return;
      await _sendLocationUpdate(position, confirmed: true);
    } catch (error) {
      debugPrint('Second location check skipped: $error');
    } finally {
      _confirmingOutside = false;
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
      _notice = '';
      _status =
          'Getting your location... hold still for a few seconds for a precise GPS fix.';
    });

    try {
      final position = await _getBestPosition();

      if (position == null) {
        throw Exception('Location permission is required.');
      }

      final result = await ApiService.checkOut(
        token: widget.token,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        isMocked: position.isMocked,
      );

      await _locationSubscription?.cancel();
      _heartbeatTimer?.cancel();

      if (!mounted) return;
      setState(() {
        _isCheckedIn = false;
        _outsideSince = '';
        // What was said while timed in no longer applies.
        _campusDetectionMessage = '';
        _detectedCampus = '';
        _hasReading = false;
        _status = result['message'] ?? 'Check-out successful.';
        _notice = result['notificationWarning']?.toString() ?? '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = error.toString().replaceFirst('Exception: ', '');
        _notice = _status;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    // A fresh reading, so the card says where the student is now rather than
    // where they were when they timed in.
    if (mounted && !_isCheckedIn) unawaited(_detectCampus());
  }

  Future<void> _signOut() async {
    await SessionService.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  void _selectNavigation(int index) {
    if (index == 0) {
      setState(() => _selectedNavigationIndex = 0);
      return;
    }

    // 1 = Attendance (the record of past days), 2 = Profile. Time in and time
    // out live on the home screen, so there is no separate tab for them.
    // (Teachers never get here: they are sent to the teacher dashboard in
    // build().)
    final destination = index == 2
        ? AccountSettingsScreen(
            email: widget.email,
            role: 'Student',
            fullName: widget.fullName,
            token: widget.token,
            onSignOut: _signOut,
          )
        : AttendanceHistoryScreen(token: widget.token, name: _displayName);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => destination),
    ).then((_) {
      if (mounted) setState(() => _selectedNavigationIndex = 0);
    });
  }

  // ── home ─────────────────────────────────────────────────────────────

  /// The one card that answers the only question this screen exists for: are
  /// you at the campus, and what can you do about it.
  ///
  /// This used to be three cards. The status sat at the top, a clock the phone
  /// already shows sat in the middle, and the button that actually records
  /// attendance sat at the bottom, below the week's schedule. A student had to
  /// scroll past everything to reach the one thing they came to press.
  Widget _campusCard(bool narrow) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = StatusTone.of(context, _locationLabel);

    return Card(
      child: Padding(
        padding: EdgeInsets.all(narrow ? AppSpace.lg : AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Tinted by the status, and it moves between colours rather
                // than snapping, so a change of state is something you see.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tone.container,
                    borderRadius: BorderRadius.circular(AppRadius.block),
                  ),
                  child: Icon(
                    _isCheckedIn
                        ? Icons.how_to_reg_rounded
                        : Icons.location_on_outlined,
                    color: tone.content,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isCheckedIn ? 'Timed in at' : 'Your location',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        // Timed in: the campus of the session. Otherwise:
                        // the campus the last check found, if any.
                        _isCheckedIn && _campus.isNotEmpty
                            ? _campus
                            : !_isCheckedIn && _detectedCampus.isNotEmpty
                            ? _detectedCampus
                            : _locationLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!narrow) ...[
                  const SizedBox(width: AppSpace.sm),
                  StatusBadge(label: _locationLabel),
                ],
              ],
            ),
            // On a narrow phone the badge would squeeze the campus name, so it
            // moves under the row instead of fighting it for width.
            if (narrow) ...[
              const SizedBox(height: AppSpace.md),
              Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge(label: _locationLabel),
              ),
            ],

            // One sentence: where things stand and what to do next.
            const SizedBox(height: AppSpace.md),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _cardMessage,
                key: ValueKey(_cardMessage),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                  height: 1.45,
                ),
              ),
            ),
            if (_notice.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Text(
                _notice,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: StatusTone.forLevel(
                    context,
                    StatusLevel.caution,
                  ).content,
                  height: 1.4,
                ),
              ),
            ],

            if (_outsideSince.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Builder(
                builder: (context) {
                  final outside = StatusTone.of(context, 'Outside Campus');
                  return Container(
                    padding: const EdgeInsets.all(AppSpace.md),
                    decoration: BoxDecoration(
                      color: outside.container,
                      borderRadius: BorderRadius.circular(AppRadius.block),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_off_outlined,
                          size: 18,
                          color: outside.content,
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Expanded(
                          child: Text(
                            'Outside campus since '
                            '${ManilaTime.time(_outsideSince, fallback: _outsideSince)}',
                            style: TextStyle(
                              color: outside.content,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],

            // Two buttons, side by side, always in the same place. Only the
            // one that applies can be pressed: Time in until the student has
            // timed in, then Time out. One button that changed its label in
            // the same spot and the same green left students unsure which
            // they were about to press.
            const SizedBox(height: AppSpace.xl),
            Row(
              children: [
                Expanded(
                  child: _attendanceButton(
                    label: 'Time in',
                    icon: Icons.login_rounded,
                    color: scheme.primary,
                    busy: _isLoading && !_isCheckedIn,
                    onPressed: !_isInitializing && !_isLoading && !_isCheckedIn
                        ? _checkIn
                        : null,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: _attendanceButton(
                    label: 'Time out',
                    icon: Icons.logout_rounded,
                    color: StatusTone.forLevel(context, StatusLevel.stop).content,
                    busy: _isLoading && _isCheckedIn,
                    onPressed: !_isInitializing && !_isLoading && _isCheckedIn
                        ? _checkOut
                        : null,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpace.sm),
            // The campus is looked for once when the screen opens; this is how
            // the student asks for another reading after walking somewhere
            // else.
            Center(
              child: TextButton.icon(
                onPressed: _isLoading || _isDetectingCampus
                    ? null
                    : _detectCampus,
                icon: _isDetectingCampus
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location_outlined, size: 18),
                label: Text(
                  _isDetectingCampus ? 'Checking location' : 'Check my location',
                ),
              ),
            ),
            Center(
                child: Text(
                  'Your location is used to confirm you are at the campus.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// One of the two attendance buttons. Disabled, it fades to grey, so the
  /// one that can be pressed is the only one in colour.
  Widget _attendanceButton({
    required String label,
    required IconData icon,
    required Color color,
    required bool busy,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
        ),
        onPressed: onPressed,
        icon: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon),
        label: Text(
          busy ? 'Locating…' : label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  /// Who you are, where you are, and today's classes. Three blocks, in the
  /// order a student needs them.
  Widget _buildHome(BoxConstraints constraints) {
    final narrow = constraints.maxWidth < 400;
    final pad = narrow ? AppSpace.lg : AppSpace.xl;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        children: [
          // The school's green band, the same as every other role's home.
          Reveal(
            order: 0,
            child: BrandBand(
              greeting: _firstName.isNotEmpty ? 'Hello, $_firstName' : 'Hello',
              subtitle: 'Time in when you arrive, time out when you leave.',
              name: _displayName,
              photo: ProfileState.instance.photo,
              maxWidth: 760,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, AppSpace.lg, pad, pad),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Reveal(order: 1, child: _campusCard(narrow)),
                    const SizedBox(height: AppSpace.md),
                    Reveal(
                      order: 2,
                      child: DailyScheduleCard(token: widget.token),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    if (widget.isTeacher) {
      return TeacherDashboardScreen(
        token: widget.token,
        email: widget.email,
        fullName: widget.fullName,
        firstName: widget.firstName,
        onSignOut: _signOut,
      );
    }

    return Listener(
      onPointerDown: (_) => _dismissKeyboardIfOpen(),
      child: Scaffold(
        appBar: brandAppBar(
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
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildHome(constraints),
                ),
              ),
        bottomNavigationBar: NavigationBar(
          destinations: const [
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
}
