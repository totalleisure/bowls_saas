import 'package:supabase_flutter/supabase_flutter.dart';

const memberSelection =
    'member_profile_id, role, is_active, is_coach, coaching_award, '
    'member_profiles('
    'email_address, first_name, last_name, display_name, phone, home_phone, office_phone, '
    'address_line1, address_line2, town_city, county, postcode, '
    'title, outdoor_club, gender, gender_self_described, sex_at_birth, preferred_position, '
    'show_mobile_in_directory, show_home_phone_in_directory, show_office_phone_in_directory, '
    'show_email_in_directory, show_address_in_directory'
    ')';

/// Load the complete directory despite the API's per-response row limit.
/// The screen still presents one list, with no user-facing pagination.
Future<List<Map<String, dynamic>>> loadClubMembers(
  SupabaseClient client,
  String clubId, {
  String? onlyMemberProfileId,
}) async {
  const batchSize = 1000;
  final rows = <Map<String, dynamic>>[];
  final seen = <String>{};
  int? expectedCount;
  while (true) {
    var query = client
        .from('club_memberships')
        .select(memberSelection)
        .eq('club_id', clubId);
    if (onlyMemberProfileId != null) {
      query = query.eq('member_profile_id', onlyMemberProfileId);
    }
    final response = await query
        .order('role', ascending: true)
        .order('member_profile_id', ascending: true)
        .range(rows.length, rows.length + batchSize - 1)
        .count(CountOption.exact);
    expectedCount ??= response.count;
    if (response.count != expectedCount) {
      throw StateError('Membership changed while loading. Please refresh.');
    }
    for (final row in response.data) {
      if (!seen.add(row['member_profile_id'] as String)) {
        throw StateError('Membership changed while loading. Please refresh.');
      }
      rows.add(Map<String, dynamic>.from(row));
    }
    if (rows.length == expectedCount) return rows;
    if (response.data.isEmpty || rows.length > expectedCount) {
      throw StateError(
        'The complete membership list could not be loaded. Please retry.',
      );
    }
  }
}
