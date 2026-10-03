import 'package:supabase_flutter/supabase_flutter.dart';

class FixtureTeamStructureService {
  const FixtureTeamStructureService(this.client);

  final SupabaseClient client;

  static const formats = <String, String>{
    'rinks': 'Rinks (4)',
    'triples': 'Triples (3)',
    'pairs': 'Pairs (2)',
    'singles': 'Singles (1)',
  };

  Future<List<String>> availablePhysicalRinks(String fixtureId) async {
    final fixture = await client
        .from('fixtures')
        .select('is_home, green_area_id, start_at, end_at')
        .eq('id', fixtureId)
        .single();
    if (fixture['is_home'] != true || fixture['green_area_id'] == null) {
      return const [];
    }
    final rows = await client.rpc(
      'get_green_rink_availability',
      params: {
        'p_green_area_id': fixture['green_area_id'],
        'p_start_at': fixture['start_at'],
        'p_end_at': fixture['end_at'],
        'p_exclude_fixture_id': fixtureId,
      },
    );
    return List<Map<String, dynamic>>.from(rows)
        .where((row) => row['is_booked'] != true)
        .map((row) => row['rink_label']?.toString() ?? '')
        .where((label) => label.isNotEmpty)
        .toList();
  }

  Future<void> change({
    required String fixtureId,
    required String action,
    String? fixtureRinkId,
    String? format,
    String? homeRinkLabel,
  }) async {
    await client.rpc(
      'manage_fixture_team_structure',
      params: {
        'p_fixture_id': fixtureId,
        'p_action': action,
        'p_fixture_rink_id': fixtureRinkId,
        'p_format': format,
        'p_home_rink_label': homeRinkLabel,
      },
    );
  }
}
