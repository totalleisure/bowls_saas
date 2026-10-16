import 'package:supabase_flutter/supabase_flutter.dart';

class AccountUsernameService {
  static const enabled = bool.fromEnvironment('ACCOUNT_USERNAME_ENABLED');
  final SupabaseClient client;
  AccountUsernameService(this.client);

  static String normalize(String value) => value.trim().toLowerCase();
  static bool valid(String value) =>
      RegExp(r'^[a-z0-9][a-z0-9_.-]{2,29}$').hasMatch(value) &&
      !const {
        'admin',
        'administrator',
        'support',
        'system',
        'root',
        'moderator',
      }.contains(value);

  Future<String?> load() async =>
      await client.rpc('my_account_username') as String?;
  Future<String?> save(String value) async {
    final name = normalize(value);
    if (name.isNotEmpty && !valid(name)) {
      throw const FormatException(
        'Use 3–30 letters, numbers, dots, hyphens or underscores, starting with a letter or number.',
      );
    }
    return await client.rpc(
          'set_account_username',
          params: {'requested_username': name},
        )
        as String?;
  }

  Future<void> signIn(String identifier, String password) async {
    if (identifier.contains('@')) {
      await client.auth.signInWithPassword(
        email: identifier.trim(),
        password: password,
      );
      return;
    }
    if (!enabled || !valid(normalize(identifier))) {
      throw const AuthException('Invalid login credentials');
    }
    try {
      final response = await client.functions.invoke(
        'username-login',
        body: {'username': normalize(identifier), 'password': password},
      );
      final data = response.data;
      if (response.status != 200 ||
          data is! Map ||
          data['refresh_token'] is! String) {
        throw const AuthException('Invalid login credentials');
      }
      await client.auth.setSession(data['refresh_token'] as String);
    } on FunctionException catch (error) {
      if (error.status == 401) {
        throw const AuthException('Invalid login credentials');
      }
      throw const AuthException(
        'Sign in is temporarily unavailable. Please try again later.',
      );
    }
  }
}
