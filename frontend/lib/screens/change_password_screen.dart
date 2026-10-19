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
  void dispose() {
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _validate() {
    final newPassword = _newController.text;
    if (newPassword.length < 8 ||
        !RegExp(r'[A-Z]').hasMatch(newPassword) ||
        !RegExp(r'\d').hasMatch(newPassword)) {
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
                        helperText:
                            'At least 8 characters, with a capital letter and a number',
                        helperMaxLines: 2,
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
                    const SizedBox(height: 14),
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