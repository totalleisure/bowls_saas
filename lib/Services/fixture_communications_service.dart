import 'dart:convert';

import 'package:bowls_saas/core/utils/date_format.dart';
import 'package:bowls_saas/services/team_sheet_builder_service.dart';
import 'package:bowls_saas/services/team_sheet_pdf.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FixtureCommunicationsRepairResult {
  const FixtureCommunicationsRepairResult({
    required this.repairResult,
    required this.attachmentResult,
  });

  final dynamic repairResult;
  final TeamSheetAttachmentResult attachmentResult;
}

class TeamSheetAttachmentBuild {
  const TeamSheetAttachmentBuild({
    required this.attachment,
    required this.compositionVersion,
    required this.teamSelectionId,
  });

  final Map<String, dynamic> attachment;
  final int compositionVersion;
  final String teamSelectionId;
}

class TeamSheetAttachmentResult {
  const TeamSheetAttachmentResult({
    required this.compositionVersion,
    required this.notificationRowsUpdated,
    required this.emailRowsUpdated,
  });

  final int compositionVersion;
  final int notificationRowsUpdated;
  final int emailRowsUpdated;

  factory TeamSheetAttachmentResult.fromRpc(dynamic result) {
    if (result is! Map) {
      throw const FormatException('Invalid team-sheet attachment response.');
    }
    final data = Map<String, dynamic>.from(result);
    int count(String key) => int.tryParse(data[key]?.toString() ?? '') ?? 0;
    return TeamSheetAttachmentResult(
      compositionVersion: count('composition_version'),
      notificationRowsUpdated: count('notification_rows_updated'),
      emailRowsUpdated: count('email_rows_updated'),
    );
  }
}

class FixtureCommunicationsService {
  FixtureCommunicationsService(this.client);

  final SupabaseClient client;

  Future<TeamSheetAttachmentBuild> buildTeamSheetAttachment({
    required Map<String, dynamic> fixture,
    String? teamSelectionId,
  }) async {
    final fixtureId = fixture['id']?.toString();
    if (fixtureId == null || fixtureId.isEmpty) {
      throw Exception('Fixture id not found');
    }

    final build = await TeamSheetBuilderService(
      client,
    ).buildForFixture(fixtureId);
    if (teamSelectionId != null &&
        teamSelectionId.isNotEmpty &&
        build.teamSelectionId != teamSelectionId) {
      throw Exception('Team selection does not match this fixture');
    }
    final data = build.data;

    final pdfBytes = await buildTeamSheetPdf(data);
    if (pdfBytes.isEmpty || pdfBytes.length > 2000000) {
      throw const FormatException(
        'The Team Sheet PDF is empty or exceeds the 2 MB email limit.',
      );
    }
    final d = toClubTime(data.startAt);
    final when =
        '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
    final safeClub = data.clubName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '-');
    final safeOpponent = data.opponentName.replaceAll(
      RegExp(r'[<>:"/\\|?*]'),
      '-',
    );

    return TeamSheetAttachmentBuild(
      compositionVersion: build.compositionVersion,
      teamSelectionId: build.teamSelectionId,
      attachment: {
        'name': '$safeClub v $safeOpponent - $when.pdf',
        'contentType': 'application/pdf',
        'contentBytes': base64Encode(pdfBytes),
        'compositionVersion': build.compositionVersion,
      },
    );
  }

  Future<TeamSheetAttachmentResult> rebuildTeamSheetAttachment({
    required Map<String, dynamic> fixture,
    required String teamSelectionId,
  }) async {
    final fixtureId = fixture['id']?.toString();
    if (fixtureId == null || fixtureId.isEmpty) {
      throw Exception('Fixture id not found');
    }

    final build = await buildTeamSheetAttachment(
      fixture: fixture,
      teamSelectionId: teamSelectionId,
    );
    if (build.teamSelectionId != teamSelectionId) {
      throw const FormatException(
        'Team selection does not match the authoritative fixture state.',
      );
    }

    final result = await client.rpc(
      'attach_publication_team_sheet',
      params: {
        'p_fixture_id': fixtureId,
        'p_team_selection_id': teamSelectionId,
        'p_expected_composition_version': build.compositionVersion,
        'p_attachment': build.attachment,
      },
    );

    return TeamSheetAttachmentResult.fromRpc(result);
  }

  Future<TeamSheetAttachmentResult> rebuildTeamSheetAttachmentForFixture({
    required String fixtureId,
  }) async {
    final build = await buildTeamSheetAttachment(fixture: {'id': fixtureId});

    final result = await client.rpc(
      'attach_publication_team_sheet',
      params: {
        'p_fixture_id': fixtureId,
        'p_team_selection_id': build.teamSelectionId,
        'p_expected_composition_version': build.compositionVersion,
        'p_attachment': build.attachment,
      },
    );
    return TeamSheetAttachmentResult.fromRpc(result);
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

    final attachmentResult = await rebuildTeamSheetAttachment(
      fixture: fixture,
      teamSelectionId: teamSelectionId,
    );

    return FixtureCommunicationsRepairResult(
      repairResult: repairResult,
      attachmentResult: attachmentResult,
    );
  }
}
