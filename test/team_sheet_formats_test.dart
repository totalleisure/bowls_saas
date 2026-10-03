import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/services/team_sheet_builder_service.dart';
import 'package:bowls_saas/services/team_sheet_pdf.dart';

Map<String, dynamic> payload({bool vacant = false}) => {
  'fixture': {
    'club_name': 'Lewisham and Crystal Palace Indoor Bowls Club',
    'opponent_name': 'Bromley Town Bowling Club',
    'start_at': '2026-09-30T13:00:00Z',
    'is_home': true,
    'section': 'mixed',
    'competition_type': {'name': 'Friendly', 'selection_mode': 'rsvp', 'is_internal': false},
  },
  'team_selection': {'id': 'selection', 'status': 'published', 'composition_version': 9},
  'rinks': [
    {'id': 'triple', 'fixture_rink_no': 1, 'players_per_rink': 3, 'home_rink_label': 'R3'},
    {'id': 'pair', 'fixture_rink_no': 2, 'players_per_rink': 2, 'home_rink_label': 'R1'},
  ],
  'assignments': [
    {'fixture_rink_id': 'triple', 'position': 1, 'display_name': 'Wayne Symmetry'},
    if (!vacant) {'fixture_rink_id': 'triple', 'position': 2, 'display_name': 'Sue Sayers'},
    {'fixture_rink_id': 'triple', 'position': 3, 'display_name': 'Wayne Sayers'},
    {'fixture_rink_id': 'pair', 'position': 1, 'display_name': 'wayne.streem@gmail.com'},
  ],
};

void main() {
  test('mixed formats retain each team size and all players', () async {
    final data = TeamSheetBuilderService.buildFromAuthorizedPayload(payload()).data;
    expect(data.rinks.map((r) => r.playersPerRink), [3, 2]);
    expect(data.rinks.first.players, ['Wayne Symmetry', 'Sue Sayers', 'Wayne Sayers']);
    expect(data.rinks.last.players, ['wayne.streem@gmail.com', '']);
    final bytes = await buildTeamSheetPdf(data);
    expect(bytes.take(4), [37, 80, 68, 70]);
    final output = Platform.environment['TEAM_SHEET_TEST_PDF'];
    if (output != null) await File(output).writeAsBytes(bytes);
  });

  test('vacant middle position does not turn the skip into number two', () {
    final data = TeamSheetBuilderService.buildFromAuthorizedPayload(payload(vacant: true)).data;
    expect(data.rinks.first.players, ['Wayne Symmetry', '', 'Wayne Sayers']);
  });

  test('team order does not change either format', () {
    final input = payload();
    input['rinks'] = (input['rinks'] as List).reversed.toList();
    final data = TeamSheetBuilderService.buildFromAuthorizedPayload(input).data;
    expect(data.rinks.map((r) => r.playersPerRink), [2, 3]);
    expect(data.rinks.last.players.last, 'Wayne Sayers');
  });
}
