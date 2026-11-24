import '../../secrets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppEntryAccess {
  final bool isSuperuser;
  final bool hasActiveMembership;
  final bool hasClubInvitation;
  final bool hasClubRegistration;

  const AppEntryAccess({
    required this.isSuperuser,
    required this.hasActiveMembership,
    this.hasClubInvitation = false,
    this.hasClubRegistration = false,
  });

  bool get allowed =>
      isSuperuser ||
      hasActiveMembership ||
      hasClubInvitation ||
      hasClubRegistration;
}

class AppEntryAccessService {
  final SupabaseClient _client;

  AppEntryAccessService([SupabaseClient? client])
    : _client = client ?? Supabase.instance.client;

  Future<AppEntryAccess> load() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const AppEntryAccess(
        isSuperuser: false,
        hasActiveMembership: false,
      );
    }

    final superuser = await _client
        .from('app_superusers')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();

    if (superuser != null) {
      return const AppEntryAccess(
        isSuperuser: true,
        hasActiveMembership: false,
      );
    }

    final hasRegistration =
        const {
          'egxdkaotepgfjmszxlyn.supabase.co',
          'xfjelvvfoguzukgvxchh.supabase.co',
        }.contains(Uri.parse(Secrets.supabaseUrl).host) &&
        await _client.rpc('my_staging_club_registration') != null;
    final memberProfileId = await _client.rpc('my_member_profile_id');
    if (memberProfileId == null) {
      return AppEntryAccess(
        isSuperuser: false,
        hasActiveMembership: false,
        hasClubRegistration: hasRegistration,
      );
    }
    final memberships = await _client
        .from('club_memberships')
        .select('id')
        .eq('member_profile_id', memberProfileId)
        .eq('is_active', true)
        .limit(1);

    final hasActive = (memberships as List).isNotEmpty;
    var hasInvitation = false;
    if (!hasActive &&
        const {
          'egxdkaotepgfjmszxlyn.supabase.co',
          'xfjelvvfoguzukgvxchh.supabase.co',
        }.contains(Uri.parse(Secrets.supabaseUrl).host)) {
      final invitations = await _client.rpc('my_staging_club_invitations');
      hasInvitation = (invitations as List).isNotEmpty;
    }
    return AppEntryAccess(
      isSuperuser: false,
      hasActiveMembership: hasActive,
      hasClubInvitation: hasInvitation,
      hasClubRegistration: hasRegistration,
    );
  }
}
