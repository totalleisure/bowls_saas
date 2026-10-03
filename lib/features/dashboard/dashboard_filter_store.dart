import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/dashboard_fixture_filter.dart';

class DashboardFilterStore {
  const DashboardFilterStore(this.client);
  final SupabaseClient client;

  Future<void> save(
    String userId,
    String clubId,
    DashboardFixtureFilter filter,
  ) async {
    if (filter.isDefault) {
      await client
          .from('user_club_dashboard_filters')
          .delete()
          .eq('user_id', userId)
          .eq('club_id', clubId);
    } else {
      await client.from('user_club_dashboard_filters').upsert({
        'user_id': userId,
        'club_id': clubId,
        'filter_json': filter.toJson(),
      }, onConflict: 'user_id,club_id');
    }
  }
}
