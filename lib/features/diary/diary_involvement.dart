import '../../core/utils/fixture_reminders.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/date_format.dart';
import 'diary_list_repository.dart';

class DiaryInvolvement {
  final String? memberId;
  final Map<String, List<String>> selectionBadges;
  const DiaryInvolvement({this.memberId, this.selectionBadges = const {}});
  factory DiaryInvolvement.fromRows(
    String memberId,
    List<Map<String, dynamic>> rows,
  ) {
    final badges = <String, List<String>>{};
    for (final row in rows) {
      final selection = row['team_selections'] as Map?;
      final fixture = selection?['fixture'] as Map?;
      if (row['is_selected'] != true ||
          selection?['status'] != 'published' ||
          fixture == null ||
          fixture['cancelled_at'] != null) {
        continue;
      }
      final label = row['acceptance'] == 'pending'
          ? 'Awaiting your acceptance'
          : row['acceptance'] == 'accepted'
          ? (row['role'] == 'reserve' ? "You're a reserve" : "You're playing")
          : null;
      if (label != null) {
        final labels = badges.putIfAbsent(fixture['id'].toString(), () => []);
        if (!labels.contains(label)) labels.add(label);
      }
    }
    return DiaryInvolvement(memberId: memberId, selectionBadges: badges);
  }
  List<String> badgesFor(Map<String, dynamic> entry) {
    if (entry['_maintenance'] == true || entry['cancelled_at'] != null) {
      return const [];
    }
    return [
      ...?selectionBadges[entry['id']?.toString()],
      if (memberId != null &&
          (entry['captain_member_profile_id'] == memberId ||
              entry['vice_captain_member_profile_id'] == memberId))
        (entry['competition_type'] as Map?)?['uses_rinks'] == false
            ? "You're organising"
            : "You're managing",
    ];
  }
}

const _personalSelection =
    'id,is_selected,acceptance,role,team_selections!inner(status,fixture:fixtures!inner(id,start_at,cancelled_at))';

class DiaryInvolvementRepository {
  final SupabaseClient client;
  final String clubId;
  final Future<String?> Function()? memberIdLoader;
  DiaryInvolvementRepository(this.client, this.clubId, {this.memberIdLoader});
  String? _cachedUser;
  String? _cachedMember;
  Future<String?> _memberId() async {
    if (memberIdLoader != null) return memberIdLoader!();
    final user = client.auth.currentUser?.id;
    if (user == null) return null;
    if (_cachedUser == user && _cachedMember != null) return _cachedMember;
    final value = await client.rpc('my_member_profile_id');
    _cachedMember = value?.toString();
    _cachedUser = user;
    return _cachedMember;
  }

  Future<DiaryInvolvement> load(DateTime from, DateTime until) async {
    final member = await _memberId();
    if (member == null) return const DiaryInvolvement();
    final rows = await loadDiaryPages(
      (offset) => client
          .from('team_selection_members')
          .select(_personalSelection)
          .eq('member_profile_id', member)
          .eq('is_selected', true)
          .eq('team_selections.status', 'published')
          .eq('team_selections.fixture.club_id', clubId)
          .gte(
            'team_selections.fixture.start_at',
            clubTimeToUtc(from).toIso8601String(),
          )
          .lt(
            'team_selections.fixture.start_at',
            clubTimeToUtc(until).toIso8601String(),
          )
          .order('id', ascending: true)
          .range(offset, offset + 499)
          .count(CountOption.exact),
    );
    return DiaryInvolvement.fromRows(member, rows);
  }

  Future<Map<String, dynamic>?> nextAccepted(DateTime nowUtc) async {
    final member = await _memberId();
    if (member == null) return null;
    // Retrieve only this member's compact future commitments. Sorting after
    // complete pagination avoids relying on embedded ordering to sort parents.
    final rows = await loadDiaryPages(
      (offset) => client
          .from('team_selection_members')
          .select(_personalSelection)
          .eq('member_profile_id', member)
          .eq('is_selected', true)
          .eq('acceptance', 'accepted')
          .eq('team_selections.status', 'published')
          .eq('team_selections.fixture.club_id', clubId)
          .isFilter('team_selections.fixture.cancelled_at', null)
          .gte(
            'team_selections.fixture.start_at',
            nowUtc.toUtc().toIso8601String(),
          )
          .order('id', ascending: true)
          .range(offset, offset + 499)
          .count(CountOption.exact),
    );
    final fixtures =
        [
          for (final row in rows)
            Map<String, dynamic>.from(
              (row['team_selections'] as Map)['fixture'] as Map,
            ),
        ]..sort((a, b) {
          final order = DateTime.parse(
            a['start_at'] as String,
          ).compareTo(DateTime.parse(b['start_at'] as String));
          return order == 0
              ? a['id'].toString().compareTo(b['id'].toString())
              : order;
        });
    if (fixtures.isEmpty) return null;
    return await client
        .from('fixtures')
        .select(
          diaryFixtureSelection.replaceFirst(
            'venue:venues!fixtures_venue_id_fkey(id,name)',
            'venue:venues!fixtures_venue_id_fkey(id,name,address_line1,address_line2,town_city,postcode,latitude,longitude,directions_url,google_maps_url)',
          ),
        )
        .eq('club_id', clubId)
        .eq('id', fixtures.first['id'])
        .isFilter('cancelled_at', null)
        .maybeSingle();
  }

  /// Personal reminders are independent of diary browsing dates and filters.
  Future<List<Map<String, dynamic>>> reminders(DateTime nowUtc) async {
    final member = await _memberId();
    if (member == null) return [];
    final rows = await loadDiaryPages(
      (offset) => client
          .from('team_selection_members')
          .select(_personalSelection)
          .eq('member_profile_id', member)
          .eq('is_selected', true)
          .inFilter('acceptance', ['accepted', 'pending'])
          .eq('team_selections.status', 'published')
          .eq('team_selections.fixture.club_id', clubId)
          .isFilter('team_selections.fixture.cancelled_at', null)
          .gte(
            'team_selections.fixture.start_at',
            nowUtc.toUtc().toIso8601String(),
          )
          .order('id', ascending: true)
          .range(offset, offset + 499)
          .count(CountOption.exact),
    );
    final candidates = fixtureReminders([
      for (final row in rows)
        {
          ...Map<String, dynamic>.from(
            (row['team_selections'] as Map)['fixture'] as Map,
          ),
          '_reminderAcceptance': row['acceptance'],
        },
    ], now: nowUtc);
    if (candidates.isEmpty) return [];
    final details = await loadDiaryPages(
      (offset) => client
          .from('fixtures')
          .select(
            diaryFixtureSelection.replaceFirst(
              'venue:venues!fixtures_venue_id_fkey(id,name)',
              'venue:venues!fixtures_venue_id_fkey(id,name,address_line1,address_line2,town_city,postcode,latitude,longitude,directions_url,google_maps_url)',
            ),
          )
          .eq('club_id', clubId)
          .inFilter('id', candidates.map((f) => f['id']).toList())
          .isFilter('cancelled_at', null)
          .order('id', ascending: true)
          .range(offset, offset + 499)
          .count(CountOption.exact),
    );
    final byId = {for (final row in details) row['id']: row};
    return fixtureReminders([
      for (final candidate in candidates)
        if (byId[candidate['id']] != null)
          {
            ...byId[candidate['id']]!,
            '_reminderAcceptance': candidate['_reminderAcceptance'],
          },
    ], now: nowUtc);
  }
}
