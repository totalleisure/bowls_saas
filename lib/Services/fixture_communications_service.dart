import 'dart:convert';

import 'package:bowls_saas/core/utils/date_format.dart';
import 'package:bowls_saas/services/team_sheet_pdf.dart';
import 'package:bowls_saas/services/team_sheet_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FixtureCommunicationsRepairResult {
  const FixtureCommunicationsRepairResult({
    required this.repairResult,
    required this.attachedTeamSheets,
  });

  final dynamic repairResult;
  final int attachedTeamSheets;
}

class FixtureCommunicationsService {
  FixtureCommunicationsService(this.client);

  final SupabaseClient client;

  Map<String, dynamic>? _map(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  String _nestedName(dynamic value) {
    final row = _map(value);
    return row?['name']?.toString().trim() ?? '';
  }

  String _clubName(Map<String, dynamic> fixture) {
    final direct = fixture['club_name']?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;

    final nested = _nestedName(fixture['clubs']);
    return nested.isEmpty ? 'Club' : nested;
  }

  String _opponentName(Map<String, dynamic> fixture) {
    final direct = fixture['opponent_name']?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;

    final isHome = fixture['is_home'] == true;
    final venue = _nestedName(fixture['venue']);
    final opponentVenue = _nestedName(fixture['opponent_venue']);

    final resolved = isHome ? opponentVenue : venue;
    return resolved.isEmpty ? 'Opponent' : resolved;
  }

  Future<Map<String, dynamic>> buildTeamSheetAttachment({
    required Map<String, dynamic> fixture,
    required String teamSelectionId,
  }) async {
    final fixtureId = fixture['id']?.toString();
    if (fixtureId == null || fixtureId.isEmpty) {
      throw Exception('Fixture id not found');
    }

    final startText = fixture['start_at']?.toString();
    final startAt = startText == null ? null : DateTime.tryParse(startText);
    if (startAt == null) {
      throw Exception('Fixture start date/time not found');
    }

    final clubName = _clubName(fixture);
    final opponentName = _opponentName(fixture);

    final service = TeamSheetService(client);
    final data = await service.loadTeamSheetData(
      fixtureId: fixtureId,
      teamSelectionId: teamSelectionId,
      clubName: clubName,
      opponentName: opponentName,
      startAt: startAt,
      isHome: fixture['is_home'] == true,
      section: (fixture['section'] ?? '').toString(),
      primaryColor: 0xFF0B3D91,
      secondaryColor: 0xFFFFD200,
      dress: (fixture['dress'] ?? 'Greys/Whites or Blacks').toString(),
      notes: fixture['notes']?.toString(),
    );

    final pdfBytes = await buildTeamSheetPdf(data);
    final d = toClubTime(data.startAt);
    final when =
        '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
    final safeClub = data.clubName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '-');
    final safeOpponent = data.opponentName.replaceAll(
      RegExp(r'[<>:"/\\|?*]'),
      '-',
    );

    return {
      'name': '$safeClub v $safeOpponent - $when.pdf',
      'contentType': 'application/pdf',
      'contentBytes': base64Encode(pdfBytes),
    };
  }

  Future<int> rebuildTeamSheetAttachment({
    required Map<String, dynamic> fixture,
    required String teamSelectionId,
  }) async {
    final fixtureId = fixture['id']?.toString();
    if (fixtureId == null || fixtureId.isEmpty) {
      throw Exception('Fixture id not found');
    }

    final attachment = await buildTeamSheetAttachment(
      fixture: fixture,
      teamSelectionId: teamSelectionId,
    );

    final result = await client.rpc(
      'attach_publication_team_sheet',
      params: {
        'p_fixture_id': fixtureId,
        'p_team_selection_id': teamSelectionId,
        'p_attachment': attachment,
      },
    );

    if (result is int) return result;
    return int.tryParse(result?.toString() ?? '') ?? 0;
  }

  Future<int> processPublicationNotifications({int limit = 50}) async {
    final result = await client.rpc(
      'process_notification_queue',
      params: {'p_limit': limit},
    );

    if (result is int) return result;
    return int.tryParse(result?.toString() ?? '') ?? 0;
  }

  Future<FixtureCommunicationsRepairResult> repairPublicationCommunications({
    required Map<String, dynamic> fixture,
    required String teamSelectionId,
  }) async {
    final fixtureId = fixture['id']?.toString();
    if (fixtureId == null || fixtureId.isEmpty) {
      throw Exception('Fixture id not found');
    }

    final repairResult = await client.rpc(
      'repair_fixture_publication_communications',
      params: {'p_fixture_id': fixtureId},
    );

    final attached = await rebuildTeamSheetAttachment(
      fixture: fixture,
      teamSelectionId: teamSelectionId,
    );

    return FixtureCommunicationsRepairResult(
      repairResult: repairResult,
      attachedTeamSheets: attached,
    );
  }
}
