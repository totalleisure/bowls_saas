import 'package:supabase_flutter/supabase_flutter.dart';

class ClubReport {
  ClubReport(this.data, this.members);
  final Map<String, dynamic> data;
  final List<Map<String, dynamic>> members;
  Map<String, dynamic> get summary =>
      Map<String, dynamic>.from(data['summary'] as Map);
  List<Map<String, dynamic>> get bookings =>
      List<Map<String, dynamic>>.from(data['bookings'] as List);
  List<Map<String, dynamic>> get screens =>
      List<Map<String, dynamic>>.from(data['screens'] as List);

  List<Map<String, dynamic>> get guestMembers => members
      .where((m) => m['member_type']?.toString().toLowerCase() == 'guest')
      .toList();

  bool get hasRecordedUsage => members.any(
    (m) =>
        (m['screen_views'] as num? ?? 0) > 0 ||
        (m['app_visits'] as num? ?? 0) > 0 ||
        (m['recorded_logins'] as num? ?? 0) > 0,
  );

  /// A snapshot order, not a score. Do not substitute fixture participation for
  /// App usage: captains can book/select/respond on another member's behalf.
  List<Map<String, dynamic>> get topUsers {
    final rows = members
        .where(
          (m) =>
              m['last_sign_in'] != null ||
              (m['screen_views'] as num? ?? 0) > 0 ||
              (m['app_visits'] as num? ?? 0) > 0 ||
              (m['recorded_logins'] as num? ?? 0) > 0,
        )
        .toList();
    rows.sort((a, b) {
      for (final key in ['screen_views', 'app_visits', 'recorded_logins']) {
        final comparison = (b[key] as num? ?? 0).compareTo(a[key] as num? ?? 0);
        if (comparison != 0) return comparison;
      }
      final latest = (b['last_sign_in']?.toString() ?? '').compareTo(
        a['last_sign_in']?.toString() ?? '',
      );
      if (latest != 0) return latest;
      final surname = a['surname'].toString().toLowerCase().compareTo(
        b['surname'].toString().toLowerCase(),
      );
      return surname != 0
          ? surname
          : a['forename'].toString().toLowerCase().compareTo(
              b['forename'].toString().toLowerCase(),
            );
    });
    return rows;
  }

  static Future<ClubReport> load(
    SupabaseClient client,
    String clubId,
    DateTime from,
    DateTime to,
  ) async {
    final members = <Map<String, dynamic>>[];
    final seen = <String>{};
    Map<String, dynamic>? first;
    while (true) {
      final page = Map<String, dynamic>.from(
        await client.rpc(
              'get_club_admin_report',
              params: {
                'p_club_id': clubId,
                'p_from': from.toIso8601String().split('T').first,
                'p_to': to.toIso8601String().split('T').first,
                'p_offset': members.length,
                'p_limit': 500,
              },
            )
            as Map,
      );
      first ??= page;
      first['club_id'] = clubId;
      if (page['total_members'] != first['total_members']) {
        throw StateError(
          'Membership changed during the export. Please refresh.',
        );
      }
      final rows = List<Map<String, dynamic>>.from(page['members'] as List);
      for (final row in rows) {
        if (!seen.add(row['member_profile_id'] as String)) {
          throw StateError(
            'Membership changed during the export. Please refresh.',
          );
        }
        members.add(row);
      }
      if (members.length == first['total_members']) {
        return ClubReport(first, members);
      }
      if (rows.isEmpty || members.length > (first['total_members'] as num)) {
        throw StateError(
          'The complete report could not be loaded. Please retry.',
        );
      }
    }
  }
}

const reportMemberColumns = <String, String>{
  'surname': 'Surname',
  'forename': 'Forename',
  'email': 'Email',
  'mobile': 'Mobile telephone',
  'home_phone': 'Home telephone',
  'office_phone': 'Office telephone',
  'member_type': 'Member type (App role)',
  'active': 'Active membership',
  'coach': 'Coach',
  'captain_managed': 'Captain managed',
  'login_enabled': 'Login enabled',
  'member_since': 'Member record since',
  'last_sign_in': 'Last sign-in',
  'recorded_logins': 'Recorded logins',
  'app_visits': 'App visits',
  'screen_views': 'Screen views',
  'last_app_activity': 'Last App activity',
  'bookings_created': 'Bookings created',
  'selected_fixtures': 'Assigned fixtures',
  'fixture_responses': 'Fixture responses',
  'explicit_start_view': 'Explicit starting view',
  'start_view_recorded_at': 'Starting view recorded (UTC)',
  'start_view_status': 'Starting view report status',
};
