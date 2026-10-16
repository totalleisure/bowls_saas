import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Only the destination and stage are persisted, never codes or passwords.
class PasswordRecoveryProgress {
  static String? verifyingEmail;
  static const key = 'password_recovery_progress_v1';
  static Future<void> save(String email, {bool verified = false}) async {
    verifyingEmail = verified ? email : null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode({
        'email': email,
        'verified': verified,
        'requested_at': DateTime.now().millisecondsSinceEpoch,
      }),
    );
  }

  static Future<Map<String, dynamic>?> read() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final age =
          DateTime.now().millisecondsSinceEpoch -
          (value['requested_at'] as int);
      if (age < 0 ||
          age > const Duration(hours: 1).inMilliseconds ||
          value['email'] is! String) {
        await clear();
        return null;
      }
      return value;
    } catch (_) {
      await clear();
      return null;
    }
  }

  static Future<void> clear() async {
    verifyingEmail = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }
}
