import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/profile_state.dart';
import '../widgets/app_ui.dart';

class EditProfileScreen extends StatefulWidget {
  final String token;
  final String role;
  final String email;

  const EditProfileScreen({
    super.key,
    required this.token,
    required this.role,
    required this.email,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const _maxPhotoBytes = 380 * 1024;

  final _firstController = TextEditingController();
  final _middleController = TextEditingController();
  final _lastController = TextEditingController();

  bool _isLoading = true;
  bool _isPhotoBusy = false;
  String _error = '';

  // Admin accounts have no personal record, so there are no name fields to show.
  bool get _hasName => widget.role.toLowerCase() != 'admin';

  @override
  void initState() {
    super.initState();
    ProfileState.instance.addListener(_onProfileChanged);
    _load();
  }

  @override
  void dispose() {
    ProfileState.instance.removeListener(_onProfileChanged);
    _firstController.dispose();
    _middleController.dispose();
    _lastController.dispose();
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final result = await ApiService.getProfile(token: widget.token);
      final user = result['user'];
      if (user is Map) {
        _firstController.text = (user['first_name'] as String?) ?? '';
        _middleController.text = (user['middle_name'] as String?) ?? '';
        _lastController.text = (user['last_name'] as String?) ?? '';
        String text(String key) => (user[key]?.toString() ?? '').trim();
        final state = ProfileState.instance;
        state.studentNumber = text('student_number');
        state.course = text('course');
        state.yearLevel = text('year_level');
        state.section = text('section');
        state.employeeNumber = text('employee_number');
        state.setPhoto(user['profile_photo'] as String?);
      }
    } catch (error) {
      _error = error.toString().replaceFirst('Exception: ', '');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _detectMime(Uint8List bytes) {
    if (bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50) {
      return 'image/png';
    }
    if (bytes.length > 12 &&
        bytes[0] == 0x52 && // R
        bytes[1] == 0x49 && // I
        bytes[8] == 0x57 && // W
        bytes[9] == 0x45) {
      // E
      return 'image/webp';
    }
    return 'image/jpeg';
  }

  Future<void> _pickPhoto() async {
    if (_isPhotoBusy) return;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 400,
        maxHeight: 400,
        imageQuality: 80,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (bytes.length > _maxPhotoBytes) {
        setState(() => _error = 'That photo is too large. Please choose a smaller one.');
        return;
      }

      setState(() {
        _isPhotoBusy = true;
        _error = '';
      });
      final dataUrl = 'data:${_detectMime(bytes)};base64,${base64Encode(bytes)}';
      await ApiService.uploadProfilePhoto(token: widget.token, photo: dataUrl);
      ProfileState.instance.setPhoto(dataUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isPhotoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    if (_isPhotoBusy) return;
    setState(() {
      _isPhotoBusy = true;
      _error = '';
    });
    try {
      await ApiService.deleteProfilePhoto(token: widget.token);
      ProfileState.instance.setPhoto(null);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isPhotoBusy = false);
    }
  }

  Widget _lockedField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: TextFormField(
        key: ValueKey('$label|$value'),
        initialValue: value.isEmpty ? '—' : value,
        enabled: false,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  // Student: student number, course, year level, section.
  // Teacher: employee number. All read-only.
  List<Widget> _roleFields() {
    final state = ProfileState.instance;
    final role = widget.role.toLowerCase();
    if (role == 'student') {
      final year = state.yearLevel;
      return [
        _lockedField('Student number', state.studentNumber),
        _lockedField('Course', state.course),
        _lockedField(
          'Year level',
          int.tryParse(year) != null ? 'Year $year' : year,
        ),
        _lockedField('Section', state.section),
      ];
    }
    if (role == 'teacher') {
      return [_lockedField('Employee number', state.employeeNumber)];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ProfileState.instance;
    final displayName = state.fullName.isNotEmpty ? state.fullName : widget.email;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Stack(
                            children: [
                              ProfileAvatar(
                                name: displayName,
                                radius: 56,
                                photo: state.photo,
                              ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Material(
                                  color: theme.colorScheme.primary,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: _isPhotoBusy ? null : _pickPhoto,
                                    child: Padding(
                                      padding: const EdgeInsets.all(9),
                                      child: _isPhotoBusy
                                          ? SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: theme.colorScheme.onPrimary,
                                              ),
                                            )
                                          : Icon(
                                              Icons.photo_camera_outlined,
                                              size: 18,
                                              color: theme.colorScheme.onPrimary,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            TextButton(
                              onPressed: _isPhotoBusy ? null : _pickPhoto,
                              child: Text(
                                state.photo == null ? 'Add photo' : 'Change photo',
                              ),
                            ),
                            if (state.photo != null)
                              TextButton(
                                onPressed: _isPhotoBusy ? null : _removePhoto,
                                child: Text(
                                  'Remove',
                                  style: TextStyle(color: theme.colorScheme.error),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_hasName) ...[
                          TextField(
                            controller: _firstController,
                            enabled: false,
                            decoration: const InputDecoration(
                              labelText: 'First name',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _middleController,
                            enabled: false,
                            decoration: const InputDecoration(
                              labelText: 'Middle name',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _lastController,
                            enabled: false,
                            decoration: const InputDecoration(
                              labelText: 'Last name',
                            ),
                          ),
                          const SizedBox(height: 14),
                        ],
                        TextField(
                          controller: TextEditingController(text: widget.email),
                          enabled: false,
                          decoration: const InputDecoration(labelText: 'Email'),
                        ),
                        ..._roleFields(),
                        if (_error.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ],
                        const SizedBox(height: 22),
                        OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            shape: const StadiumBorder(),
                            side: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                          child: const Text('Done'),
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