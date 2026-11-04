import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';
import 'login_screen.dart';

/// Shown right after login when the account still has a temporary password
/// (for example, accounts created from the bulk Excel upload).
///
/// The session is saved only after the password has been changed. Closing the
/// app on this screen therefore sends the user back to login, and they cannot
/// reach the dashboard until they set a new password.
class ChangePasswordScreen extends StatefulWidget {
  /// The login session to save once the password is changed.
  final Session session;

  /// The temporary password the user just logged in with.
  final String currentPassword;

  /// The dashboard to open after the password is changed.
  final Widget next;

  const ChangePasswordScreen({
    super.key,
    required this.session,
    required this.currentPassword,
    required this.next,
  });

  @override
  State<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _hidePassword = true;
  bool _isSaving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    // Redraws the strength meter on every keystroke.
    _newController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _newController.removeListener(_onPasswordChanged);
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// The rule the account must pass. The meter below is guidance only; it never
  /// blocks a password that already meets this.
  bool _meetsRequirement(String value) =>
      value.length >= 8 &&
      RegExp(r'[A-Z]').hasMatch(value) &&
      RegExp(r'\d').hasMatch(value);

  String? _validate() {
    final newPassword = _newController.text;
    if (!_meetsRequirement(newPassword)) {
      return 'The new password must be at least 8 characters and contain an uppercase letter and a number.';
    }
    if (newPassword != _confirmController.text) {
      return 'The new passwords do not match.';
    }
    if (newPassword == widget.currentPassword) {
      return 'Your new password must be different from your temporary password.';
    }
    return null;
  }

  /// 0 = nothing typed, 1 = Weak, 2 = Fair, 3 = Good, 4 = Strong.
  ///
  /// Length counts first, then the mix of characters. A password shorter than
  /// the required eight characters never climbs above Weak, so the meter and
  /// the rule never contradict each other.
  int _strength(String value) {
    if (value.isEmpty) return 0;
    if (value.length < 8) return 1;

    var points = 1;
    if (value.length >= 12) points++;
    if (RegExp(r'[A-Z]').hasMatch(value) &&
        RegExp(r'[a-z]').hasMatch(value)) {
      points++;
    }
    if (RegExp(r'\d').hasMatch(value)) points++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) points++;

    // Strong is reserved for a genuinely long password, so a short one full of
    // symbols cannot reach the top of the meter.
    final ceiling = value.length >= 12 ? 4 : 3;
    return points > ceiling ? ceiling : points;
  }

  static const _strengthColors = [
    Color(0xFFC62828), // Weak
    Color(0xFFEF6C00), // Fair
    Color(0xFF689F38), // Good
    Color(0xFF2E7D32), // Strong
  ];

  static const _strengthLabels = ['Weak', 'Fair', 'Good', 'Strong'];
  static const _okGreen = Color(0xFF2E7D32);

  Widget _strengthMeter(ThemeData theme) {
    final value = _newController.text;
    final score = _strength(value);
    final empty = theme.colorScheme.outlineVariant;
    final filled = score == 0 ? empty : _strengthColors[score - 1];
    final meets = _meetsRequirement(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (index) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: index == 3 ? 0 : 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 6,
                  decoration: BoxDecoration(
                    color: index < score ? filled : empty,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              meets
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 16,
              color: meets ? _okGreen : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                'At least 8 characters, with a capital letter and a number',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: meets ? _okGreen : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (score > 0) ...[
              const SizedBox(width: 10),
              Text(
                _strengthLabels[score - 1],
                style: theme.textTheme.bodySmall?.copyWith(
                  color: filled,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    final problem = _validate();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _isSaving = true;
      _error = '';
    });
    try {
      await ApiService.changePassword(
        token: widget.session.token,
        currentPassword: widget.currentPassword,
        newPassword: _newController.text,
      );
      await SessionService.save(widget.session);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => widget.next),
        (route) => false,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isSaving = false;
      });
    }
  }

  void _signOut() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstName = widget.session.firstName.trim();

    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Set a new password'),
          automaticallyImplyLeading: false,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Icon(
                          Icons.lock_reset_rounded,
                          size: 36,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      firstName.isEmpty
                          ? 'Welcome to BenildeSafe'
                          : 'Welcome, $firstName',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You signed in with a temporary password. Create your own password to continue.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _newController,
                      obscureText: _hidePassword,
                      enabled: !_isSaving,
                      decoration: InputDecoration(
                        labelText: 'New password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _strengthMeter(theme),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _confirmController,
                      obscureText: _hidePassword,
                      enabled: !_isSaving,
                      decoration: const InputDecoration(
                        labelText: 'Confirm new password',
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        _error,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _isSaving ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save and continue'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _isSaving ? null : _signOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
