import 'package:supabase_flutter/supabase_flutter.dart';

class TeamPermissions {
  static final SupabaseClient _client = Supabase.instance.client;

  /// Returns true if the current user can edit the team pool for [teamId] in [clubId].
  /// Logic:
  /// - club role is admin or selector (active membership), OR
  /// - user is captain/vice/manager for the team
  static Future<bool> canEditTeamPool({
    required String clubId,
    required String teamId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    // 1) Get my member_profile_id
    final mp = await _client
        .from('member_profiles')
        .select('id')
        .eq('user_id', userId)
        .maybeSingle();

    final myProfileId = mp?['id']?.toString();
    if (myProfileId == null) return false;

    // 2) Am I admin or selector for this club?
    final cm = await _client
        .from('club_memberships')
        .select('role, is_active')
        .eq('club_id', clubId)
        .eq('member_profile_id', myProfileId)
        .maybeSingle();

    final isActive = cm?['is_active'] == true;
    final role = cm?['role']?.toString(); // enum comes back as string
    final isAdminOrSelector = isActive && (role == 'admin' || role == 'selector');

    if (isAdminOrSelector) return true;

    // 3) Am I captain/vice/manager for THIS team?
    final team = await _client
        .from('teams')
        .select('captain_member_profile_id, vice_captain_member_profile_id, manager_member_profile_id')
        .eq('id', teamId)
        .maybeSingle();

    if (team == null) return false;

    final captainId = team['captain_member_profile_id']?.toString();
    final viceId = team['vice_captain_member_profile_id']?.toString();
    final managerId = team['manager_member_profile_id']?.toString();

    return myProfileId == captainId || myProfileId == viceId || myProfileId == managerId;
  }
}