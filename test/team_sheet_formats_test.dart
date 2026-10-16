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
  test('PDF data retains draft and published selection status', () {
    for (final status in ['draft', 'published']) {
      final input = payload();
      (input['team_selection'] as Map<String, dynamic>)['status'] = status;
      expect(TeamSheetBuilderService.buildFromAuthorizedPayload(input).data.selectionStatus, status);
    }
  });
  test('team sheet retains blank, zero and GBP fees from its authorized payload', () {
    for (final fee in [null, 0, 750]) {
      final input = payload();
      input['fixture'] = <String, dynamic>{
        ...input['fixture'] as Map<String, dynamic>,
        'match_fee_pence': fee,
      };
      expect(TeamSheetBuilderService.buildFromAuthorizedPayload(input).data.matchFeePence, fee);
    }
  });
  test('six full teams and two reserve rows fit on the first A4 page', () async {
    final data = TeamSheetData(
      clubName: 'Lewisham and Crystal Palace Indoor Bowls Club',
      opponentName: 'Bromley Town Bowling Club',
      startAt: DateTime.utc(2026, 10, 30, 14),
      isHome: true, venueName: 'Main Indoor Green', section: 'mixed',
      rinksRequired: 6, playersPerRink: 4, dress: 'Club shirts and whites',
      matchFeePence: 750,
      captainName: 'Captain Full Name', captainEmail: 'captain@example.com',
      captainPhone: '07700 900123', viceName: 'Vice Captain Full Name',
      viceEmail: 'vice@example.com', vicePhone: '07700 900456',
      fixtureTypeName: 'Friendly Weekend Fixture', selectionMode: 'selection',
      notes: 'Please arrive thirty minutes before the match.',
      primaryColor: 0xff345678, secondaryColor: 0xffddeeff,
      rinks: List.generate(6, (i) => TeamSheetRink(
        rinkNumber: i + 1, playersPerRink: 4,
        players: List.generate(4, (j) => 'Player ${i + 1} ${j + 1} Full Name'),
      )),
      reserves: List.generate(6, (i) => 'Reserve ${i + 1} Full Name'),
    );
    final bytes = await buildTeamSheetPdf(data);
    final text = String.fromCharCodes(bytes);
    await Directory('outputs').create(recursive: true);
    await File('outputs/six-team-sheet.pdf').writeAsBytes(bytes);
    expect(RegExp(r'/Type\s*/Page\b').allMatches(text).length, 1);
  });

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
