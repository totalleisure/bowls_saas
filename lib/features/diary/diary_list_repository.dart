import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/date_format.dart';

const diaryMaintenanceType = <String, dynamic>{
  'id': '__maintenance__',
  'name': 'Green maintenance',
  'uses_rinks': true,
  'is_internal': false,
  'tags': <String>[],
  'colour_scheme': {'background_hex': '#ECEFF1', 'foreground_hex': '#263238'},
};
const diaryFixtureSelection = '''
  id, club_id, notes, start_at, end_at, cancelled_at, is_home, section,
  team_id, team_name, opponent_name, venue_id, opponent_venue_id,
  captain_member_profile_id, vice_captain_member_profile_id,
  green_area_id, rinks_required, competition_type_id,
  competition_type:competition_types!fixtures_competition_type_id_fkey(
    id,name,is_internal,selection_mode,uses_rinks,tags,
    colour_scheme:fixture_colour_schemes(background_hex,foreground_hex)),
  team:teams(id,name), venue:venues!fixtures_venue_id_fkey(id,name),
  opponent_venue:venues!fixtures_opponent_venue_id_fkey(id,name),
  green_areas(id,name), fixture_rinks(id,format,home_rink_label)
''';

/// Every page uses the authenticated client and retains RLS. Never infer the
/// end of a result from a short page: the server may impose a smaller row cap.
Future<List<Map<String, dynamic>>> loadDiaryPages(
  Future<PostgrestResponse<List<Map<String, dynamic>>>> Function(int offset)
  fetch,
) async {
  final rows = <Map<String, dynamic>>[];
  final seen = <String>{};
  int? total;
  while (true) {
    final result = await fetch(rows.length);
    total ??= result.count;
    if (result.count != total) {
      throw StateError('Diary changed while loading. Please refresh.');
    }
    for (final row in result.data) {
      final id = row['id']?.toString();
      if (id == null || !seen.add(id)) {
        throw StateError('Diary changed while loading. Please refresh.');
      }
      rows.add(Map<String, dynamic>.from(row));
    }
    if (rows.length == total) return rows;
    if (result.data.isEmpty || rows.length > total) {
      throw StateError('The complete diary could not be loaded. Please retry.');
    }
  }
}

class DiaryListRepository {
  final SupabaseClient client;
  final String clubId;
  DiaryListRepository(this.client, this.clubId);
  Future<List<Map<String, dynamic>>> loadTypes() async => [
    ...await loadDiaryPages(
      (offset) => client
          .from('competition_types')
          .select(
            'id,name,section,is_internal,tags,selection_mode,uses_rinks,colour_scheme:fixture_colour_schemes(name,background_hex,foreground_hex)',
          )
          .eq('club_id', clubId)
          .order('name', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + 499)
          .count(CountOption.exact),
    ),
    diaryMaintenanceType,
  ];
  Future<List<Map<String, dynamic>>> loadTeams() => loadDiaryPages(
    (offset) => client
        .from('teams')
        .select('id,name')
        .eq('club_id', clubId)
        .order('name', ascending: true)
        .order('id', ascending: true)
        .range(offset, offset + 499)
        .count(CountOption.exact),
  );
  Future<List<Map<String, dynamic>>> load(DateTime from, DateTime until) async {
    final lower = clubTimeToUtc(from).toIso8601String();
    final upper = clubTimeToUtc(until).toIso8601String();
    final results = await Future.wait([
      loadDiaryPages(
        (offset) => client
            .from('fixtures')
            .select(diaryFixtureSelection)
            .eq('club_id', clubId)
            .gte('start_at', lower)
            .lt('start_at', upper)
            .order('start_at', ascending: true)
            .order('id', ascending: true)
            .range(offset, offset + 499)
            .count(CountOption.exact),
      ),
      loadDiaryPages(
        (offset) => client
            .from('green_rink_maintenance')
            .select(
              'id,green_area_id,rink_number,start_at,end_at,reason,notes,status,green_areas!inner(id,name,venue:venues!inner(id,name,club_id))',
            )
            .eq('green_areas.venue.club_id', clubId)
            .eq('status', 'active')
            .lt('start_at', upper)
            .gt('end_at', lower)
            .order('start_at', ascending: true)
            .order('id', ascending: true)
            .range(offset, offset + 499)
            .count(CountOption.exact),
      ),
    ]);
    return [
      ...results[0],
      for (final row in results[1])
        {
          ...row,
          '_maintenance': true,
          'competition_type_id': '__maintenance__',
          'competition_type': diaryMaintenanceType,
          'is_home': true,
          'section': 'open',
          'venue': (row['green_areas'] as Map?)?['venue'],
        },
    ];
  }
}
