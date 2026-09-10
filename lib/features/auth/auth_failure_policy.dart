import 'package:supabase_flutter/supabase_flutter.dart';

class AuthFailurePresentation {
  final String title;
  final String message;
  final String actionLabel;

  const AuthFailurePresentation({
    required this.title,
    required this.message,
    required this.actionLabel,
  });
}

class AuthFailurePolicy {
  static AuthFailurePresentation? invalidCredentials(Object error) {
    if (error is! AuthException) return null;

    final message = error.message.toLowerCase();
    final invalid =
        message.contains('invalid login credentials') ||
        message.contains('invalid credentials');
    if (!invalid) return null;

    return const AuthFailurePresentation(
      title: 'Sign in unsuccessful',
      message:
          'The email address or password was not recognised. Please check both entries and try again.',
      actionLabel: 'Check details',
    );
  }
}
