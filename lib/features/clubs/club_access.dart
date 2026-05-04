import 'package:supabase_flutter/supabase_flutter.dart';

class ClubAccess {
  final String currentMemberId;
  final bool isSuperuser;
  final bool isClubAdmin;
  final bool isSelector;

  const ClubAccess({
    required this.currentMemberId,
    required this.isSuperuser,
    required this.isClubAdmin,
    required this.isSelector,
  });

  bool get canAdminManageFixtures =>
      isSuperuser || isClubAdmin || isSelector;

  bool get canCreateFixtures => canAdminManageFixtures;
}

Future<ClubAccess> loadClubAccess({
  required String clubId,
  SupabaseClient? client,
}) async {
  final supabase = client ?? Supabase.instance.client;
  final user = supabase.auth.currentUser;

  if (user == null) {
    throw Exception('No logged-in user');
  }

  final myProfileId =
      (await supabase.rpc('my_member_profile_id')).toString();

  final superuserRow = await supabase
      .from('app_superusers')
      .select('user_id')
      .eq('user_id', user.id)
      .maybeSingle();

  final membership = await supabase
      .from('club_memberships')
      .select('id, club_id, member_profile_id, role')
      .eq('member_profile_id', myProfileId)
      .eq('club_id', clubId)
      .maybeSingle();

  final role = (membership?['role'] ?? '').toString().trim().toLowerCase();

  return ClubAccess(
    currentMemberId: myProfileId,
    isSuperuser: superuserRow != null,
    isClubAdmin: role == 'admin',
    isSelector: role == 'selector',
  );
}