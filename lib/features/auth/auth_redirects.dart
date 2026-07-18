import 'package:flutter/foundation.dart';

class AuthRedirects {
  AuthRedirects._();

  static const String nativeCallback =
      'totalleisuresolutions.bowls://login-callback/';

  static String get callback {
    if (kIsWeb) {
      return Uri.base.resolve('/').toString();
    }

    return nativeCallback;
  }
}
