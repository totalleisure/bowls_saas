import 'package:supabase_flutter/supabase_flutter.dart';

class AppEntryAccess {
  final bool isSuperuser;
  final bool hasActiveMembership;

  const AppEntryAccess({
    required this.isSuperuser,
    required this.hasActiveMembership,
  });

  bool get allowed => isSuperuser || hasActiveMembership;
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

    final memberProfileId = (await _client.rpc(
      'my_member_profile_id',
    )).toString();
    final memberships = await _client
        .from('club_memberships')
        .select('id')
        .eq('member_profile_id', memberProfileId)
        .eq('is_active', true)
        .limit(1);

    return AppEntryAccess(
      isSuperuser: false,
      hasActiveMembership: (memberships as List).isNotEmpty,
    );
  }
}
