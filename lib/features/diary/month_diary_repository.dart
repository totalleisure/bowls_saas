import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/date_format.dart';
import 'diary_list_repository.dart' show loadDiaryPages;

class MonthDiaryRepository {
  const MonthDiaryRepository(this.client, this.clubId);
  final SupabaseClient client;
  final String clubId;

  Future<List<Map<String, dynamic>>> load(DateTime month) => _loadRange(
    DateTime(month.year, month.month),
    DateTime(month.year, month.month + 1),
  );

  Future<List<Map<String, dynamic>>> loadDay(DateTime day) => _loadRange(
    DateTime(day.year, day.month, day.day),
    DateTime(day.year, day.month, day.day + 1),
  );

  Future<List<Map<String, dynamic>>> _loadRange(DateTime start, DateTime end) {
    final from = clubTimeToUtc(start);
    final until = clubTimeToUtc(end);
    // Count every page: a server row cap must not silently hide busy days.
    return loadDiaryPages(
      (offset) => client
          .from('fixtures')
          .select('''
        id, club_id, start_at, end_at, cancelled_at, is_home, opponent_name, team_name,
        green_area_id, rinks_required,
          venue:venues!fixtures_venue_id_fkey(id,name),
        competition_types (
          id, name, is_internal, selection_mode,
          colour_scheme:fixture_colour_schemes (background_hex, foreground_hex)
        ),
        fixture_rinks (
          id, home_rink_label,
          fixture_rink_assignments (member_profile_id)
        )
      ''')
          .eq('club_id', clubId)
          .gte('start_at', from.toIso8601String())
          .lt('start_at', until.toIso8601String())
          .order('start_at', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + 499)
          .count(CountOption.exact),
    );
  }

  Future<Set<DateTime>> affectedDays(
    Set<DateTime> days,
    Iterable<String> fixtureIds,
  ) async {
    final result = {...days};
    var ids = fixtureIds.toSet();
    for (var pass = 0; pass < 2 && ids.isNotEmpty; pass++) {
      final rows = await client
          .from('fixtures')
          .select('id,start_at,rescheduled_to_fixture_id')
          .eq('club_id', clubId)
          .inFilter('id', ids.toList());
      ids = {};
      for (final row in rows) {
        final at = parseClubTime(row['start_at'].toString());
        result.add(DateTime(at.year, at.month, at.day));
        final next = row['rescheduled_to_fixture_id']?.toString();
        if (next != null && next.isNotEmpty) ids.add(next);
      }
    }
    return result;
  }
}
