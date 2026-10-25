import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/date_format.dart';
import 'diary_list_repository.dart' show loadDiaryPages;

class MonthDiaryRepository {
  const MonthDiaryRepository(this.client, this.clubId);
  final SupabaseClient client;
  final String clubId;

  Future<List<Map<String, dynamic>>> load(DateTime month) {
    final from = clubTimeToUtc(DateTime(month.year, month.month));
    final until = clubTimeToUtc(DateTime(month.year, month.month + 1));
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
}
