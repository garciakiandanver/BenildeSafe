import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/app_preferences.dart';
import '../services/profile_state.dart';
import '../widgets/app_ui.dart';
import 'edit_profile_screen.dart';
import 'forgot_password_screen.dart';

class AccountSettingsScreen extends StatefulWidget {
  final String email;
  final String role;
  final VoidCallback onSignOut;

  /// Full name from the sign-in session. Optional, so screens that do not pass
  /// it still work (they show the email instead).
  final String fullName;

  /// Sign-in token. Needed for "Change password"; the option is hidden when
  /// it is empty.
  final String token;

  const AccountSettingsScreen({
    super.key,
    required this.email,
    required this.role,
    required this.onSignOut,
    this.fullName = '',
    this.token = '',
  });

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _isSavingAppearance = false;

  @override
  void initState() {
    super.initState();
    ProfileState.instance.addListener(_onProfileChanged);
    // Loads the latest student / employee details from the server.
    if (widget.token.isNotEmpty) {
      unawaited(ProfileState.instance.refresh(widget.token));
    }
  }

  @override
  void dispose() {
    ProfileState.instance.removeListener(_onProfileChanged);
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  void _editProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditProfileScreen(
          token: widget.token,
          role: widget.role,
          email: widget.email,
        ),
      ),
    );
  }

  Future<void> _setDarkMode(bool enabled) async {
    setState(() => _isSavingAppearance = true);
    try {
      await AppPreferences.instance.setDarkMode(enabled);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save appearance setting: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSavingAppearance = false);
    }
  }

  Future<void> _changePassword() async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ChangePasswordDialog(token: widget.token),
    );
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your password has been changed.')),
      );
    }
  }

  void _forgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ForgotPasswordScreen(initialEmail: widget.email),
      ),
    );
  }

  String _orDash(String value) => value.isEmpty ? '—' : value;

  // Student: student number, course, year level, section.
  // Teacher: employee number.
  List<Widget> _roleDetailRows(ThemeData theme) {
    final state = ProfileState.instance;
    final role = widget.role.toLowerCase();

    if (role == 'student') {
      final year = state.yearLevel;
      final yearText = int.tryParse(year) != null ? 'Year $year' : year;
      return [
        _detailRow(
          theme,
          Icons.numbers_rounded,
          'Student number',
          _orDash(state.studentNumber),
        ),
        _detailRow(theme, Icons.school_outlined, 'Course', _orDash(state.course)),
        _detailRow(
          theme,
          Icons.layers_outlined,
          'Year level',
          _orDash(yearText),
        ),
        _detailRow(
          theme,
          Icons.groups_outlined,
          'Section',
          _orDash(state.section),
        ),
      ];
    }
    if (role == 'teacher') {
      return [
        _detailRow(
          theme,
          Icons.numbers_rounded,
          'Employee number',
          _orDash(state.employeeNumber),
        ),
      ];
    }
    return const [];
  }

  Widget _detailRow(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
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
                const SizedBox(height: 2),
                Text(
                  value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roleLabel = widget.role.isEmpty
        ? 'Campus account'
        : '${widget.role[0].toUpperCase()}${widget.role.substring(1).toLowerCase()}';

    // Accounts without a personal record (such as the administrator) have no
    // name, so fall back to the role or the email.
    final liveName = ProfileState.instance.fullName.trim();
    final fullName = liveName.isNotEmpty ? liveName : widget.fullName.trim();
    final displayName = fullName.isNotEmpty
        ? fullName
        : (widget.role.toLowerCase() == 'admin'
              ? 'Administrator'
              : widget.email);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile & settings')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        children: [
                          Center(
                            child: ProfileAvatar(
                              name: displayName,
                              radius: 38,
                              photo: ProfileState.instance.photo,
                            ),
                          ),
                          if (widget.token.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _editProfile,
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('Edit Profile Picture'),
                            ),
                          ],
                          const SizedBox(height: 18),
                          const Divider(),
                          _detailRow(
                            theme,
                            Icons.person_outline_rounded,
                            'Name',
                            displayName,
                          ),
                          _detailRow(
                            theme,
                            Icons.badge_outlined,
                            'Role',
                            roleLabel,
                          ),
                          _detailRow(
                            theme,
                            Icons.mail_outline_rounded,
                            'Email',
                            widget.email,
                          ),
                          ..._roleDetailRows(theme),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle(theme, 'SECURITY'),
                  const SizedBox(height: 10),
                  Card(
                    child: Column(
                      children: [
                        if (widget.token.isNotEmpty) ...[
                          ListTile(
                            leading: Icon(
                              Icons.lock_outline_rounded,
                              color: theme.colorScheme.primary,
                            ),
                            title: const Text('Change password'),
                            subtitle: const Text(
                              'Use your current password to set a new one',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _changePassword,
                          ),
                          const Divider(height: 1),
                        ],
                        ListTile(
                          leading: Icon(
                            Icons.mark_email_read_outlined,
                            color: theme.colorScheme.primary,
                          ),
                          title: const Text('Forgot password?'),
                          subtitle: const Text(
                            'Get a reset code at your registered email',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: _forgotPassword,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionTitle(theme, 'PREFERENCES'),
                  const SizedBox(height: 10),
                  Card(
                    child: ListenableBuilder(
                      listenable: AppPreferences.instance,
                      builder: (context, _) => SwitchListTile(
                        value: AppPreferences.instance.isDarkMode,
                        onChanged: _isSavingAppearance ? null : _setDarkMode,
                        secondary: Icon(
                          AppPreferences.instance.isDarkMode
                              ? Icons.dark_mode_outlined
                              : Icons.light_mode_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        title: const Text('Dark mode'),
                        subtitle: Text(
                          _isSavingAppearance
                              ? 'Saving preference...'
                              : 'Use a darker appearance on this device',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: widget.onSignOut,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign out'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      foregroundColor: theme.colorScheme.error,
                      side: BorderSide(
                        color: theme.colorScheme.error.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for the current password and a new one, then changes it on the server.
class _ChangePasswordDialog extends StatefulWidget {
  final String token;

  const _ChangePasswordDialog({required this.token});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _hideCurrent = true;
  bool _hideNew = true;
  bool _isSaving = false;
  String _error = '';

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validate() {
    final newPassword = _newController.text;
    if (_currentController.text.isEmpty) {
      return 'Enter your current password.';
    }
    if (newPassword.length < 8 ||
        !RegExp(r'[A-Z]').hasMatch(newPassword) ||
        !RegExp(r'\d').hasMatch(newPassword)) {
      return 'The new password must be at least 8 characters and contain an uppercase letter and a number.';
    }
    if (newPassword != _confirmController.text) {
      return 'The new passwords do not match.';
    }
    if (newPassword == _currentController.text) {
      return 'Your new password must be different from your current password.';
    }
    return null;
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
        token: widget.token,
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _currentController,
              obscureText: _hideCurrent,
              enabled: !_isSaving,
              decoration: InputDecoration(
                labelText: 'Current password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _hideCurrent ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _hideCurrent = !_hideCurrent),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newController,
              obscureText: _hideNew,
              enabled: !_isSaving,
              decoration: InputDecoration(
                labelText: 'New password',
                helperText: 'At least 8 characters, with a capital letter and a number',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  icon: Icon(_hideNew ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _hideNew = !_hideNew),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmController,
              obscureText: _hideNew,
              enabled: !_isSaving,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Change password'),
        ),
      ],
    );
  }
}