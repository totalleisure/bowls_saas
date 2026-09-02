import 'package:bowls_saas/services/team_sheet_builder_service.dart';
import 'package:bowls_saas/services/team_sheet_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'restores all authoritative team-sheet content from the RPC payload',
    () async {
      final result = TeamSheetBuilderService.buildFromAuthorizedPayload({
        'access': {'can_manage': true, 'selection_status': 'published'},
        'fixture': {
          'club_name': 'Test Club',
          'opponent_name': 'Test Opponent',
          'start_at': '2026-09-29T09:15:00Z',
          'is_home': true,
          'venue_name': 'Test Green',
          'section': 'Mixed',
          'dress_code': ['whites', 'club_shirt'],
          'notes': 'Arrive 30 minutes early.',
          'captain': {
            'display_name': 'Captain One',
            'email_address': 'captain@example.test',
            'phone': '01234 567890',
          },
          'vice_captain': {'display_name': 'Vice Captain'},
          'competition_type': {
            'name': 'Internal Pairs',
            'is_internal': true,
            'selection_mode': 'preselect',
            'background_hex': '#123456',
            'foreground_hex': '#FFFFFF',
          },
        },
        'team_selection': {
          'id': 'selection-1',
          'status': 'published',
          'composition_version': 4,
        },
        'rinks': [
          {
            'id': 'rink-1',
            'fixture_rink_no': 1,
            'home_rink_label': 'A',
            'players_per_rink': 2,
          },
        ],
        'assignments': [
          {
            'fixture_rink_id': 'rink-1',
            'position': 1,
            'display_name': 'Player One',
          },
          {
            'fixture_rink_id': 'rink-1',
            'position': 2,
            'display_name': 'Player Two',
          },
          {
            'fixture_rink_id': 'rink-1',
            'position': 101,
            'display_name': 'Opponent One',
          },
          {
            'fixture_rink_id': 'rink-1',
            'position': 102,
            'display_name': 'Opponent Two',
          },
          {
            'fixture_rink_id': 'rink-1',
            'position': 201,
            'display_name': 'Named Marker',
          },
        ],
        'selection_members': [
          {
            'role': 'reserve',
            'is_selected': true,
            'display_name': 'Reserve One',
          },
        ],
      });

      expect(result.canManage, isTrue);
      expect(result.compositionVersion, 4);
      expect(result.data.venueName, 'Test Green');
      expect(result.data.dress, 'Whites / Club_shirt');
      expect(result.data.notes, 'Arrive 30 minutes early.');
      expect(result.data.reserves, ['Reserve One']);
      expect(result.data.fixtureTypeName, 'Internal Pairs');
      expect(result.data.fixtureTypeBgColor, 0xFF123456);
      expect(result.data.fixtureTypeFgColor, 0xFFFFFFFF);
      expect(result.data.rinks.single.homeRinkLabel, 'A');
      expect(result.data.rinks.single.players, ['Player One', 'Player Two']);
      expect(result.data.rinks.single.opponents, [
        'Opponent One',
        'Opponent Two',
      ]);
      expect(result.data.rinks.single.marker, 'Named Marker');

      final bytes = await buildTeamSheetPdf(result.data);
      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    },
  );
}
