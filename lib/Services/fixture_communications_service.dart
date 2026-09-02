import 'dart:convert';

import 'package:bowls_saas/core/utils/date_format.dart';
import 'package:bowls_saas/services/team_sheet_builder_service.dart';
import 'package:bowls_saas/services/team_sheet_pdf.dart';
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

  Future<Map<String, dynamic>> buildTeamSheetAttachment({
    required Map<String, dynamic> fixture,
    required String teamSelectionId,
  }) async {
    final fixtureId = fixture['id']?.toString();
    if (fixtureId == null || fixtureId.isEmpty) {
      throw Exception('Fixture id not found');
    }

    final build = await TeamSheetBuilderService(
      client,
    ).buildForFixture(fixtureId);
    if (build.teamSelectionId != teamSelectionId) {
      throw Exception('Team selection does not match this fixture');
    }
    final data = build.data;

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
