import 'package:supabase_flutter/supabase_flutter.dart';

import 'team_sheet_pdf.dart';

class TeamSheetBuildResult {
  TeamSheetBuildResult({required this.data, required this.header});

  final TeamSheetData data;
  final Map<String, dynamic> header;
}

class TeamSheetBuilderService {
  TeamSheetBuilderService(this._client);

  final SupabaseClient _client;

  Future<TeamSheetBuildResult> buildForFixture(String fixtureId) async {
    final header = await _loadFixtureHeader(fixtureId);
    final rinks = await _loadFixtureRinks(fixtureId);
    final assignmentsByRink = await _loadAssignmentsByRink(fixtureId);

    Map<String, dynamic>? asMap(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }

    String venueNameOnly(Map<String, dynamic>? venueRow) {
      if (venueRow == null) return '';
      return venueRow['name']?.toString().trim() ?? '';
    }

    int? parseColor(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;

      final s = v.toString().trim();
      if (s.isEmpty) return null;

      if (s.startsWith('#')) {
        final hex = s.substring(1);
        if (hex.length == 6) return int.tryParse('FF$hex', radix: 16);
        if (hex.length == 8) return int.tryParse(hex, radix: 16);
      }

      if (s.startsWith('0x') || s.startsWith('0X')) {
        return int.tryParse(s.substring(2), radix: 16);
      }

      return int.tryParse(s);
    }

    String displayNameFromProfile(Map<String, dynamic>? p) {
      if (p == null) return '';
      final display = p['display_name']?.toString().trim() ?? '';
      if (display.isNotEmpty) return display;

      final first = p['first_name']?.toString().trim() ?? '';
      final last = p['last_name']?.toString().trim() ?? '';
      return '$first $last'.trim();
    }

    String emailFromProfile(Map<String, dynamic>? p) {
      return p?['email_address']?.toString().trim() ?? '';
    }

    String phoneFromProfile(Map<String, dynamic>? p) {
      return p?['phone']?.toString().trim() ?? '';
    }

    final clubName = header['clubs']?['name']?.toString().trim() ?? 'Club';
    final isHome = header['is_home'] == true;

    final venueRow = asMap(header['venue']);
    final opponentVenueRow = asMap(header['opponent_venue']);

    final opponentName = isHome
        ? venueNameOnly(opponentVenueRow)
        : venueNameOnly(venueRow);

    final startAt =
        DateTime.tryParse(header['start_at']?.toString() ?? '') ??
        DateTime.now();

    final section = header['section']?.toString() ?? '';

    final captain = asMap(header['captain']);
    final vice = asMap(header['vice_captain']);

    final competitionType = asMap(header['competition_type']);
    final colourScheme = asMap(competitionType?['colour_scheme']);

    final fixtureTypeName = (() {
      final s = competitionType?['name']?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    })();

    final isInternal = competitionType?['is_internal'] as bool?;
    final selectionMode = competitionType?['selection_mode']?.toString().trim();

    final fixtureTypeBgColor = parseColor(colourScheme?['background_hex']);
    final fixtureTypeFgColor = parseColor(colourScheme?['foreground_hex']);

    bool isPreselectInternalFixture() {
      final mode = (selectionMode ?? '').toLowerCase().trim();
      return mode == 'preselect' && isInternal == true;
    }

    final sheetRinks = <TeamSheetRink>[];
    var playersPerRink = 4;

    for (final rr in rinks) {
      final rinkId = rr['id']?.toString() ?? '';
      final rinkNo = (rr['fixture_rink_no'] as int?) ?? 0;
      final label = rr['home_rink_label']?.toString();
      final ppr = (rr['players_per_rink'] as int?) ?? 4;
      playersPerRink = ppr;

      final byPos = assignmentsByRink[rinkId] ?? <int, Map<String, dynamic>>{};

      final players = <String>[];
      final opponents = <String>[];
      String? marker;

      if (isPreselectInternalFixture()) {
        for (var lineNo = 1; lineNo <= ppr; lineNo++) {
          final playerAsn = byPos[lineNo];
          final opponentAsn = byPos[100 + lineNo];

          players.add(
            playerAsn?['member_profiles']?['display_name']?.toString() ?? '',
          );

          opponents.add(
            opponentAsn?['member_profiles']?['display_name']?.toString() ?? '',
          );
        }

        final markerAsn = byPos[201];
        final markerName =
            markerAsn?['member_profiles']?['display_name']?.toString() ?? '';
        marker = markerName.trim().isEmpty ? null : markerName.trim();
      } else {
        final positions = byPos.keys.toList()..sort();

        for (final pos in positions) {
          if (pos >= 100) continue;
          final a = byPos[pos]!;
          final name = a['member_profiles']?['display_name']?.toString() ?? '';
          if (name.isNotEmpty) players.add(name);
        }
      }

      sheetRinks.add(
        TeamSheetRink(
          rinkNumber: rinkNo,
          homeRinkLabel: label,
          players: players,
          opponents: opponents,
          marker: marker,
        ),
      );
    }

    final data = TeamSheetData(
      clubName: clubName,
      opponentName: opponentName.trim(),
      startAt: startAt,
      isHome: isHome,
      section: section,
      rinksRequired: sheetRinks.length,
      playersPerRink: playersPerRink,
      dress: 'Greys/Whites or Blacks',
      mealInfo: null,
      notes: null,
      captainName: displayNameFromProfile(captain),
      captainEmail: emailFromProfile(captain),
      captainPhone: phoneFromProfile(captain),
      viceName: displayNameFromProfile(vice),
      viceEmail: emailFromProfile(vice),
      vicePhone: phoneFromProfile(vice),
      rinks: sheetRinks,
      reserves: const [],
      primaryColor: 0xFF0B3D91,
      secondaryColor: 0xFFFFD200,
      logoBytes: null,
      fixtureTypeName: fixtureTypeName,
      fixtureTypeBgColor: fixtureTypeBgColor,
      fixtureTypeFgColor: fixtureTypeFgColor,
      isInternal: isInternal,
      selectionMode: selectionMode,
    );

    return TeamSheetBuildResult(data: data, header: header);
  }

  Future<Map<String, dynamic>> _loadFixtureHeader(String fixtureId) async {
    final row = await _client
        .from('fixtures')
        .select('''
          id,
          club_id,
          start_at,
          is_home,
          section,
          captain_member_profile_id,
          vice_captain_member_profile_id,
          clubs(name),
          venue:venues!fixtures_venue_id_fkey(name),
          opponent_venue:venues!fixtures_opponent_venue_id_fkey(name),
          captain:member_profiles!fixtures_captain_member_profile_id_fkey(
            display_name,
            first_name,
            last_name,
            email_address,
            phone
          ),
          vice_captain:member_profiles!fixtures_vice_captain_member_profile_id_fkey(
            display_name,
            first_name,
            last_name,
            email_address,
            phone
          ),
          competition_type:competition_types!fixtures_competition_type_id_fkey(
            id,
            name,
            is_internal,
            selection_mode,
            colour_scheme:fixture_colour_schemes(
              id,
              name,
              background_hex,
              foreground_hex
            )
          )
        ''')
        .eq('id', fixtureId)
        .single();

    return Map<String, dynamic>.from(row);
  }

  Future<List<Map<String, dynamic>>> _loadFixtureRinks(String fixtureId) async {
    final rows = await _client
        .from('fixture_rinks')
        .select('id, fixture_rink_no, home_rink_label, players_per_rink')
        .eq('fixture_id', fixtureId)
        .order('fixture_rink_no');

    return List<Map<String, dynamic>>.from(rows);
  }

  Future<Map<String, Map<int, Map<String, dynamic>>>> _loadAssignmentsByRink(
    String fixtureId,
  ) async {
    final rows = await _client
        .from('fixture_rink_assignments')
        .select('''
          id,
          fixture_rink_id,
          member_profile_id,
          position,
          member_profiles(
            id,
            display_name,
            first_name,
            last_name,
            email_address,
            phone
          )
        ''')
        .eq('fixture_id', fixtureId);

    final result = <String, Map<int, Map<String, dynamic>>>{};

    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final rinkId = row['fixture_rink_id']?.toString();
      final pos = row['position'] as int?;

      if (rinkId == null || pos == null) continue;

      result.putIfAbsent(rinkId, () => <int, Map<String, dynamic>>{});
      result[rinkId]![pos] = row;
    }

    return result;
  }
}
