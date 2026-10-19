import 'package:shared_preferences/shared_preferences.dart';

/// A saved login session. Lives until the user taps Logout.
class Session {
  final String token;
  final String email;
  final String role; // student | teacher | admin | parent
  final String fullName;
  final String firstName;

  const Session({
    required this.token,
    required this.email,
    required this.role,
    required this.fullName,
    required this.firstName,
  });
}

class SessionService {
  SessionService._();

  static const _tokenKey = 'benildeSafeSessionToken';
  static const _emailKey = 'benildeSafeSessionEmail';
  static const _roleKey = 'benildeSafeSessionRole';
  static const _fullNameKey = 'benildeSafeSessionFullName';
  static const _firstNameKey = 'benildeSafeSessionFirstName';

  /// Uses the backend's first_name when available; otherwise the first word
  /// of the full name.
  static String resolveFirstName(String? firstName, String fullName) {
    final explicit = (firstName ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  static Future<void> save(Session session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, session.token);
    await prefs.setString(_emailKey, session.email);
    await prefs.setString(_roleKey, session.role);
    await prefs.setString(_fullNameKey, session.fullName);
    await prefs.setString(_firstNameKey, session.firstName);
  }

  /// Updates only the saved name after the profile is edited, so the
  /// dashboard shows the new name after a restart without logging in again.
  static Future<void> updateNames({
    required String fullName,
    required String firstName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_fullNameKey, fullName);
    await prefs.setString(_firstNameKey, firstName);
  }

  static Future<Session?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final role = prefs.getString(_roleKey);
    if (token == null || token.isEmpty || role == null || role.isEmpty) {
      return null;
    }
    final fullName = prefs.getString(_fullNameKey) ?? '';
    return Session(
      token: token,
      email: prefs.getString(_emailKey) ?? '',
      role: role,
      fullName: fullName,
      firstName: resolveFirstName(prefs.getString(_firstNameKey), fullName),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_fullNameKey);
    await prefs.remove(_firstNameKey);
  }
}