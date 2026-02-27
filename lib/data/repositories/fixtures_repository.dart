import 'package:supabase_flutter/supabase_flutter.dart';

class FixturesRepository {
  final SupabaseClient _client;

  FixturesRepository(this._client);

  Future<List<Map<String, dynamic>>> getFixturesForClub(String clubId) async {
    final response = await _client
        .from('fixtures')
        .select()
        .eq('club_id', clubId)
        .order('when_utc');

    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>?> getFixtureById(String fixtureId) async {
    final response = await _client
        .from('fixtures')
        .select()
        .eq('id', fixtureId)
        .maybeSingle();

    return response;
  }
}
