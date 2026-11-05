import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

/// An id made once for this installation of the app (or this browser) and
/// kept on the device. A student account is linked to this id on the first
/// sign-in, so it can be used on one phone only. Reinstalling the app or
/// clearing its data makes a new id, and the school then has to reset the
/// linked phone. Logging out does not remove it.
class DeviceService {
  DeviceService._();

  static const _key = 'benildeSafeDeviceId';

  static Future<String> getId() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && saved.length >= 16) return saved;
    final random = Random.secure();
    final id = List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    await prefs.setString(_key, id);
    return id;
  }
}
