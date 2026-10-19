import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'session_service.dart';

/// The signed-in user's name and photo, shared by every screen so the
/// dashboard updates right after the profile is edited.
class ProfileState extends ChangeNotifier {
  ProfileState._();

  static final ProfileState instance = ProfileState._();

  String firstName = '';
  String fullName = '';
  String? photo; // data URL, e.g. "data:image/jpeg;base64,...."

  // Read-only details loaded from the server (empty until loaded).
  String studentNumber = '';
  String course = '';
  String yearLevel = '';
  String section = '';
  String employeeNumber = '';

  void setUser({
    required String fullName,
    required String firstName,
    String? photo,
  }) {
    this.fullName = fullName;
    this.firstName = firstName;
    this.photo = (photo == null || photo.isEmpty) ? null : photo;
    notifyListeners();
  }

  void setPhoto(String? value) {
    photo = (value == null || value.isEmpty) ? null : value;
    notifyListeners();
  }

  /// Called on the login screen. Does not notify: the old screens are gone.
  void clear() {
    firstName = '';
    fullName = '';
    photo = null;
    studentNumber = '';
    course = '';
    yearLevel = '';
    section = '';
    employeeNumber = '';
  }

  /// Loads the latest name and photo from the server. Fails silently
  /// (offline, expired token) and keeps what is already shown.
  Future<void> refresh(String token) async {
    try {
      final result = await ApiService.getProfile(token: token);
      final user = result['user'];
      if (user is! Map) return;
      final newFull = (user['full_name'] as String?)?.trim() ?? '';
      final newFirst = SessionService.resolveFirstName(
        user['first_name'] as String?,
        newFull,
      );
      final newPhoto = user['profile_photo'] as String?;
      String text(String key) => (user[key]?.toString() ?? '').trim();
      studentNumber = text('student_number');
      course = text('course');
      yearLevel = text('year_level');
      section = text('section');
      employeeNumber = text('employee_number');
      setUser(
        fullName: newFull.isNotEmpty ? newFull : fullName,
        firstName: newFirst.isNotEmpty ? newFirst : firstName,
        photo: newPhoto,
      );
      if (newFull.isNotEmpty) {
        await SessionService.updateNames(
          fullName: newFull,
          firstName: newFirst,
        );
      }
    } catch (_) {}
  }
}