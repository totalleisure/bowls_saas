import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class SavedLogin {
  final String identifier;
  final String password;
  const SavedLogin(this.identifier, this.password);
}

class SavedLoginService {
  static const _channel = MethodChannel('bowls/saved_login');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<SavedLogin?> select() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('get');
    if (result == null) return null;
    final identifier = result['identifier'];
    final password = result['password'];
    if (identifier is! String ||
        password is! String ||
        identifier.isEmpty ||
        password.isEmpty) {
      throw PlatformException(code: 'unavailable');
    }
    return SavedLogin(identifier, password);
  }

  static Future<void> saveVerified(String identifier, String password) async {
    if (!supported) {
      TextInput.finishAutofillContext(shouldSave: true);
      return;
    }
    // Avoid duplicate save offers from the autofill and Credential Manager APIs.
    TextInput.finishAutofillContext(shouldSave: false);
    try {
      await _channel.invokeMethod<bool>('save', {
        'identifier': identifier,
        'password': password,
      });
    } on PlatformException {
      // Password-manager failures do not undo authentication.
    } on MissingPluginException {
      // Older test binaries retain the existing autofill saving route.
      TextInput.finishAutofillContext(shouldSave: true);
    }
  }
}
