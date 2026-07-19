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
  Future<void> updateFixtureStartAt({
    required String fixtureId,
    required DateTime startAtUtc,
  }) async {
    await _client
        .from('fixtures')
        .update({'start_at': startAtUtc.toIso8601String()})
        .eq('id', fixtureId);
  }

  Future<void> updateFixtureNotes({
    required String fixtureId,
    required String? notes,
  }) async {
    await _client
        .from('fixtures')
        .update({'notes': notes})
        .eq('id', fixtureId);
  }

  Future<void> deleteFixture(String fixtureId) async {
    await _client.rpc(
      'delete_fixture',
      params: {'p_fixture_id': fixtureId},
    );
  }

}
