import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/services/team_sheet_pdf.dart';

class TeamSheetService {
  final SupabaseClient client;
  TeamSheetService(this.client);

  int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  Future<TeamSheetData> loadTeamSheetData({
    required String fixtureId,
    required String teamSelectionId,
    required String clubName,
    required String opponentName,
    required DateTime startAt,
    required bool isHome,
    required String section,
    required int primaryColor,
    required int secondaryColor,
    Uint8List? logoBytes,
    String dress = 'Greys/Whites or Blacks',
    String? notes,
    String? captainName,
    String? viceName,
  }) async {
    // 1) Rinks for this fixture
    final rinks = await client
        .from('fixture_rinks')
        .select(
          'id, fixture_rink_no, format, players_per_rink, home_rink_label',
        )
        .eq('fixture_id', fixtureId);

    final rinkList = List<Map<String, dynamic>>.from(rinks);

    // Use your same sorting rule (label first, else rink_no)
    rinkList.sort((a, b) {
      final al = (a['home_rink_label'] as String?)?.trim();
      final bl = (b['home_rink_label'] as String?)?.trim();

      if (al != null && al.isNotEmpty && bl != null && bl.isNotEmpty) {
        return al.compareTo(bl);
      }
      final ao = _asInt(a['fixture_rink_no']);
      final bo = _asInt(b['fixture_rink_no']);
      return ao.compareTo(bo);
    });

    // 2) Pool (players + reserves) from team selection
    final poolRows = await client
        .from('team_selection_members')
        .select(
          'member_profile_id, role, acceptance, member_profiles!team_selection_members_member_profile_id_fkey(display_name, phone)',
        )
        .eq('team_selection_id', teamSelectionId)
        .inFilter('role', ['player', 'reserve']);

    final pool = List<Map<String, dynamic>>.from(poolRows);

    // Lookup role by member_profile_id
    final roleByMember = <String, String>{};
    final nameByMember = <String, String>{};

    for (final r in pool) {
      final mpId = r['member_profile_id']?.toString() ?? '';
      final role = r['role']?.toString().toLowerCase() ?? '';
      final name = r['member_profiles']?['display_name']?.toString() ?? '';
      if (mpId.isNotEmpty) {
        roleByMember[mpId] = role;
        if (name.isNotEmpty) nameByMember[mpId] = name;
      }
    }

    // Reserves list
    final reserves = <String>[];
    for (final r in pool) {
      final role = r['role']?.toString().toLowerCase() ?? '';
      if (role == 'reserve') {
        final name = r['member_profiles']?['display_name']?.toString() ?? '';
        if (name.isNotEmpty) reserves.add(name);
      }
    }

    // 3) Assignments
    final asnRows = await client
        .from('fixture_rink_assignments')
        .select(
          'fixture_rink_id, position, member_profile_id, member_profiles(display_name)',
        )
        .eq('fixture_id', fixtureId);

    // Group assignments: rinkId -> list sorted by position
    final asnByRink = <String, List<Map<String, dynamic>>>{};
    for (final a in List<Map<String, dynamic>>.from(asnRows)) {
      final rinkId = a['fixture_rink_id']?.toString() ?? '';
      if (rinkId.isEmpty) continue;
      (asnByRink[rinkId] ??= []).add(a);
    }
    for (final e in asnByRink.entries) {
      e.value.sort(
        (x, y) => _asInt(x['position']).compareTo(_asInt(y['position'])),
      );
    }

    // Build TeamSheetRink list
    final rinksOut = <TeamSheetRink>[];
    int playersPerRink = 4;

    for (final rr in rinkList) {
      final rinkId = rr['id']?.toString() ?? '';
      final rinkNo = _asInt(rr['fixture_rink_no']);
      final ppr = _asInt(rr['players_per_rink']);
      if (ppr > 0) playersPerRink = ppr;

      final assigned = asnByRink[rinkId] ?? const [];

      final players = <String>[];
      for (final a in assigned) {
        final mpId = a['member_profile_id']?.toString() ?? '';
        final role = roleByMember[mpId] ?? 'player';

        // keep reserves out of the rink boxes
        if (role == 'reserve') continue;

        final name =
            a['member_profiles']?['display_name']?.toString() ??
            nameByMember[mpId] ??
            '';
        if (name.isNotEmpty) players.add(name);
      }

      rinksOut.add(
        TeamSheetRink(
          rinkNumber: rinkNo,
          // We can add physical label support later if you want it printed per rink box:
          // physicalLabel: rr['home_rink_label']?.toString(),
          players: players,
        ),
      );
    }

    return TeamSheetData(
      clubName: clubName,
      opponentName: opponentName,
      startAt: startAt,
      isHome: isHome,
      venueName: '',
      section: section,
      rinksRequired: rinksOut.length,
      playersPerRink: playersPerRink,
      dress: dress,
      notes: notes,
      captainName: captainName,
      viceName: viceName,
      rinks: rinksOut,
      reserves: reserves,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
      logoBytes: logoBytes,
    );
  }
}
