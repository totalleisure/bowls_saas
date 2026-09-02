import 'package:supabase_flutter/supabase_flutter.dart';

import 'team_sheet_pdf.dart';

class TeamSheetBuildResult {
  TeamSheetBuildResult({
    required this.data,
    required this.header,
    required this.teamSelectionId,
    required this.selectionStatus,
    required this.compositionVersion,
    required this.canManage,
  });

  final TeamSheetData data;
  final Map<String, dynamic> header;
  final String teamSelectionId;
  final String selectionStatus;
  final int compositionVersion;
  final bool canManage;
}

abstract interface class TeamSheetDataSource {
  Future<TeamSheetBuildResult> buildForFixture(String fixtureId);
}

class TeamSheetBuilderService implements TeamSheetDataSource {
  TeamSheetBuilderService(this._client);

  final SupabaseClient _client;

  @override
  Future<TeamSheetBuildResult> buildForFixture(String fixtureId) async {
    final raw = await _client.rpc(
      'get_authorized_team_sheet_data',
      params: {'p_fixture_id': fixtureId},
    );
    if (raw is! Map) {
      throw const FormatException('Invalid authorised team-sheet response.');
    }
    return buildFromAuthorizedPayload(Map<String, dynamic>.from(raw));
  }

  static TeamSheetBuildResult buildFromAuthorizedPayload(
    Map<String, dynamic> payload,
  ) {
    Map<String, dynamic> mapValue(dynamic value) =>
        value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
    List<Map<String, dynamic>> listValue(dynamic value) => value is List
        ? value
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : <Map<String, dynamic>>[];
    int intValue(dynamic value, [int fallback = 0]) => value is int
        ? value
        : int.tryParse(value?.toString() ?? '') ?? fallback;

    int? parseColor(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      final text = value.toString().trim();
      if (text.isEmpty) return null;
      if (text.startsWith('#')) {
        final hex = text.substring(1);
        if (hex.length == 6) return int.tryParse('FF$hex', radix: 16);
        if (hex.length == 8) return int.tryParse(hex, radix: 16);
      }
      if (text.toLowerCase().startsWith('0x')) {
        return int.tryParse(text.substring(2), radix: 16);
      }
      return int.tryParse(text);
    }

    String profileName(Map<String, dynamic> profile) {
      final display = profile['display_name']?.toString().trim() ?? '';
      if (display.isNotEmpty) return display;
      final first = profile['first_name']?.toString().trim() ?? '';
      final last = profile['last_name']?.toString().trim() ?? '';
      return '$first $last'.trim();
    }

    final access = mapValue(payload['access']);
    final fixture = mapValue(payload['fixture']);
    final selection = mapValue(payload['team_selection']);
    final competitionType = mapValue(fixture['competition_type']);
    final captain = mapValue(fixture['captain']);
    final viceCaptain = mapValue(fixture['vice_captain']);
    final rinks = listValue(payload['rinks']);
    final assignments = listValue(payload['assignments']);
    final selectionMembers = listValue(payload['selection_members']);

    final assignmentsByRink = <String, Map<int, Map<String, dynamic>>>{};
    for (final assignment in assignments) {
      final rinkId = assignment['fixture_rink_id']?.toString();
      final position = int.tryParse(assignment['position']?.toString() ?? '');
      if (rinkId == null || position == null) continue;
      assignmentsByRink.putIfAbsent(rinkId, () => {})[position] = assignment;
    }

    final selectionMode = competitionType['selection_mode']?.toString();
    final isInternal = competitionType['is_internal'] as bool?;
    final isPreselect =
        selectionMode?.toLowerCase() == 'preselect' && isInternal == true;
    var playersPerRink = 4;
    final sheetRinks = <TeamSheetRink>[];

    for (final rink in rinks) {
      final rinkId = rink['id']?.toString() ?? '';
      final rinkPlayers = intValue(rink['players_per_rink'], 4);
      playersPerRink = rinkPlayers;
      final byPosition = assignmentsByRink[rinkId] ?? const {};
      final players = <String>[];
      final opponents = <String>[];
      String? marker;

      for (var position = 1; position <= rinkPlayers; position++) {
        final name =
            byPosition[position]?['display_name']?.toString().trim() ?? '';
        if (isPreselect || name.isNotEmpty) players.add(name);
        if (isPreselect) {
          opponents.add(
            byPosition[100 + position]?['display_name']?.toString().trim() ??
                '',
          );
        }
      }
      if (isPreselect) {
        final name = byPosition[201]?['display_name']?.toString().trim() ?? '';
        marker = name.isEmpty ? null : name;
      }

      sheetRinks.add(
        TeamSheetRink(
          rinkNumber: intValue(rink['fixture_rink_no']),
          homeRinkLabel: rink['home_rink_label']?.toString(),
          players: players,
          opponents: opponents,
          marker: marker,
        ),
      );
    }

    final reserves = selectionMembers
        .where(
          (row) =>
              row['is_selected'] == true &&
              row['role']?.toString().toLowerCase() == 'reserve',
        )
        .map((row) => row['display_name']?.toString().trim() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    final rawDress = fixture['dress_code'];
    final dressValues = rawDress is List
        ? rawDress.map((value) => value.toString().trim())
        : rawDress == null
        ? const <String>[]
        : <String>[rawDress.toString().trim()];
    final dress = dressValues
        .where((value) => value.isNotEmpty)
        .map((value) {
          return value[0].toUpperCase() + value.substring(1);
        })
        .join(' / ');
    final compositionVersion = intValue(selection['composition_version']);

    final data = TeamSheetData(
      clubName: fixture['club_name']?.toString().trim() ?? 'Club',
      opponentName: fixture['opponent_name']?.toString().trim() ?? '',
      startAt:
          DateTime.tryParse(fixture['start_at']?.toString() ?? '') ??
          DateTime.now(),
      isHome: fixture['is_home'] == true,
      venueName: fixture['venue_name']?.toString().trim() ?? '',
      section: fixture['section']?.toString() ?? '',
      rinksRequired: sheetRinks.length,
      playersPerRink: playersPerRink,
      dress: dress.isEmpty ? 'Open dress' : dress,
      notes: fixture['notes']?.toString(),
      captainName: profileName(captain),
      captainEmail: captain['email_address']?.toString().trim() ?? '',
      captainPhone: captain['phone']?.toString().trim() ?? '',
      viceName: profileName(viceCaptain),
      viceEmail: viceCaptain['email_address']?.toString().trim() ?? '',
      vicePhone: viceCaptain['phone']?.toString().trim() ?? '',
      rinks: sheetRinks,
      reserves: reserves,
      primaryColor: 0xFF0B3D91,
      secondaryColor: 0xFFFFD200,
      logoBytes: null,
      fixtureTypeName: competitionType['name']?.toString().trim(),
      fixtureTypeBgColor: parseColor(competitionType['background_hex']),
      fixtureTypeFgColor: parseColor(competitionType['foreground_hex']),
      isInternal: isInternal,
      selectionMode: selectionMode,
      compositionVersion: compositionVersion,
    );

    return TeamSheetBuildResult(
      data: data,
      header: fixture,
      teamSelectionId: selection['id']?.toString() ?? '',
      selectionStatus: selection['status']?.toString() ?? 'draft',
      compositionVersion: compositionVersion,
      canManage: access['can_manage'] == true,
    );
  }
}
