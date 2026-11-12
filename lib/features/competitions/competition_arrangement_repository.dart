import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/date_format.dart';
import 'competition_repository.dart';

class CompetitionArrangementRepository {
  final SupabaseClient client;
  CompetitionArrangementRepository(this.client);

  Future<List<CompetitionRow>> players(
    CompetitionRow match,
  ) async => await client
      .from('competition_entry_members')
      .select(
        'entry_id,individual_handicap,member_profile:member_profiles(id,first_name,last_name)',
      )
      .eq('competition_id', match['competition_id'])
      .inFilter('entry_id', [
        match['side_a_entry_id'],
        match['side_b_entry_id'],
      ]);

  Future<List<CompetitionRow>> greens(String clubId) async => await client
      .from('green_areas')
      .select(
        'id,name,venue_id,orientation_mode,allowed_orientations,venue:venues!inner(name,club_id,is_home_venue)',
      )
      .eq('venue.club_id', clubId)
      .eq('venue.is_home_venue', true)
      .order('name');

  Future<List<CompetitionRow>> availability(
    String greenId,
    DateTime start,
    DateTime end,
  ) async => List<CompetitionRow>.from(
    await client.rpc(
      'get_green_rink_availability',
      params: {
        'p_green_area_id': greenId,
        'p_start_at': clubTimeToUtc(start).toIso8601String(),
        'p_end_at': clubTimeToUtc(end).toIso8601String(),
      },
    ),
  );

  Future<String> book(String matchId, CompetitionBookingChoice choice) async =>
      (await client.rpc(
        'arrange_competition_match',
        params: {
          'p_match_id': matchId,
          'p_green_area_id': choice.green['id'],
          'p_start_at': clubTimeToUtc(choice.start).toIso8601String(),
          'p_end_at': clubTimeToUtc(choice.end).toIso8601String(),
          'p_rink_labels': choice.rinkLabels,
          'p_orientation': choice.orientation,
        },
      )).toString();
}

class CompetitionBookingChoice {
  final CompetitionRow green;
  final DateTime start, end;
  final List<String> rinkLabels;
  final String? orientation;
  const CompetitionBookingChoice({
    required this.green,
    required this.start,
    required this.end,
    required this.rinkLabels,
    this.orientation,
  });
}
