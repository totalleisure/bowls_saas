import 'package:supabase_flutter/supabase_flutter.dart';
import '../../secrets.dart';

class SupabaseInit {
  static Future<void> init() async {
    await Supabase.initialize(
      url: Secrets.supabaseUrl,
      anonKey: Secrets.supabaseAnonKey,
    );
  }
}
