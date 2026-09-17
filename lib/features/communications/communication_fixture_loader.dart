import 'package:supabase_flutter/supabase_flutter.dart';

/// Fixtures are the source of the list: open sessions need no selection row.
Future<List<Map<String, dynamic>>> loadCommunicationFixtures(
  SupabaseClient client,
  String clubId,
) async {
  const pageSize = 200;
  final rows = <Map<String, dynamic>>[];
  for (var offset = 0; ; offset += pageSize) {
    final fixtures = await client
        .from('fixtures')
        .select('''
      id, start_at, created_at, is_home, section, team_id, team_name, club_id,
      clubs(name),
      team:teams!fixtures_team_id_fkey(name),
      competition_type:competition_types!fixtures_competition_type_id_fkey(
        name, selection_mode, is_internal, uses_rinks,
        colour_scheme:fixture_colour_schemes!competition_types_colour_scheme_id_fkey(
          background_hex, foreground_hex
        )
      ),
      venue:venues!fixtures_venue_id_fkey(name),
      opponent_venue:venues!fixtures_opponent_venue_id_fkey(name),
      selections:team_selections(id, status, created_at)
    ''')
        .eq('club_id', clubId)
        .order('created_at', ascending: false)
        .order('id')
        .range(offset, offset + pageSize - 1);
    for (final fixture in fixtures) {
      final rawSelections = fixture['selections'];
      final selectionRows = rawSelections is Map
          ? [rawSelections]
          : rawSelections is List
          ? rawSelections
          : const [];
      final selections =
          selectionRows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
            ..sort((a, b) {
              final aa = DateTime.tryParse(a['created_at']?.toString() ?? '');
              final bb = DateTime.tryParse(b['created_at']?.toString() ?? '');
              return (bb ?? DateTime(1900)).compareTo(aa ?? DateTime(1900));
            });
      final selection = selections.isEmpty ? null : selections.first;
      rows.add({
        'id': selection?['id'],
        'status': selection?['status'] ?? 'draft',
        'created_at': selection?['created_at'] ?? fixture['created_at'],
        'fixtures': fixture,
      });
    }
    if (fixtures.length < pageSize) break;
  }
  // Preserve the selector's recent-publication ordering.
  rows.sort(
    (a, b) => (b['created_at']?.toString() ?? '').compareTo(
      a['created_at']?.toString() ?? '',
    ),
  );
  return rows;
}
