import 'package:supabase_flutter/supabase_flutter.dart';
import 'club_access.dart';
import 'club_onboarding_state.dart';

/// Setup checks only read existing records; this service never sends messages.
class ClubOnboardingRepository {
  ClubOnboardingRepository(this.client);
  final SupabaseClient client;

  Future<ClubSetupSnapshot> load(String clubId) async {
    final access = await loadClubAccess(clubId: clubId, client: client);
    if (!(access.isSuperuser ||
        (access.hasActiveMembership && access.isClubAdmin))) {
      throw StateError('Club administrator access is required.');
    }
    final club = await client
        .from('clubs')
        .select('name')
        .eq('id', clubId)
        .single();
    final venues = await client
        .from('venues')
        .select('id,club_start_time,club_end_time')
        .eq('club_id', clubId)
        .eq('is_home_venue', true);
    final greens = await client
        .from('green_areas')
        .select('id,venue_id,rink_count,venues!inner(club_id,is_home_venue)')
        .eq('venues.club_id', clubId)
        .eq('venues.is_home_venue', true);
    final types = await client
        .from('competition_types')
        .select('id')
        .eq('club_id', clubId)
        .eq('is_active', true);
    final members = await client
        .from('club_memberships')
        .select('id')
        .eq('club_id', clubId)
        .eq('is_active', true);
    final teams = await client
        .from('teams')
        .select('id')
        .eq('club_id', clubId)
        .eq('is_active', true);
    int? minute(dynamic raw) {
      final parts = '$raw'.split(':');
      if (parts.length < 2) return null;
      final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
      if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
        return null;
      }
      return h * 60 + m;
    }

    final homeIds = venues.map((v) => v['id']).toSet();
    return ClubSetupSnapshot(
      clubName: club['name'].toString(),
      homeVenues: venues.length,
      greens: greens
          .where(
            (g) =>
                homeIds.contains(g['venue_id']) &&
                (int.tryParse('${g['rink_count']}') ?? 0) > 0,
          )
          .length,
      hoursReady:
          venues.isNotEmpty &&
          venues.every((v) {
            final start = minute(v['club_start_time']),
                end = minute(v['club_end_time']);
            return start != null && end != null && start < end;
          }),
      fixtureTypes: types.length,
      members: members.length,
      teams: teams.length,
    );
  }
}
