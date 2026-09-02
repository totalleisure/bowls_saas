import 'package:bowls_saas/features/team/team_sheet_screen.dart';
import 'package:bowls_saas/services/team_sheet_builder_service.dart';
import 'package:bowls_saas/services/team_sheet_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RefreshFailureSource implements TeamSheetDataSource {
  var calls = 0;

  @override
  Future<TeamSheetBuildResult> buildForFixture(String fixtureId) async {
    calls++;
    if (calls > 1) throw Exception('Access revoked');
    return TeamSheetBuildResult(
      data: TeamSheetData(
        clubName: 'Test Club',
        opponentName: 'Test Opponent',
        startAt: DateTime.utc(2026, 9, 29, 9, 15),
        isHome: true,
        venueName: 'Test Green',
        section: 'Mixed',
        rinksRequired: 1,
        playersPerRink: 2,
        dress: 'Whites',
        rinks: [
          TeamSheetRink(
            rinkNumber: 1,
            players: const ['Player One', 'Player Two'],
          ),
        ],
        reserves: const [],
        primaryColor: 0xFF0B3D91,
        secondaryColor: 0xFFFFD200,
        compositionVersion: 4,
      ),
      header: const {},
      teamSelectionId: 'selection-1',
      selectionStatus: 'published',
      compositionVersion: 4,
      canManage: true,
    );
  }
}

void main() {
  testWidgets('failed refresh removes stale export actions and PDF', (
    tester,
  ) async {
    final source = _RefreshFailureSource();
    await tester.pumpWidget(
      MaterialApp(
        home: TeamSheetScreen(fixtureId: 'fixture-1', dataSource: source),
      ),
    );
    for (var attempt = 0; attempt < 30; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find
          .byKey(const Key('team_sheet_share_action'))
          .evaluate()
          .isNotEmpty) {
        break;
      }
    }

    expect(find.byKey(const Key('team_sheet_share_action')), findsOneWidget);
    expect(find.byKey(const Key('team_sheet_print_action')), findsOneWidget);

    await tester.tap(find.byKey(const Key('team_sheet_refresh_action')));
    await tester.pump();

    expect(find.byKey(const Key('team_sheet_share_action')), findsNothing);
    expect(find.byKey(const Key('team_sheet_print_action')), findsNothing);

    await tester.pump();
    expect(find.textContaining('Access revoked'), findsOneWidget);
    expect(find.byKey(const Key('team_sheet_share_action')), findsNothing);
    expect(find.byKey(const Key('team_sheet_print_action')), findsNothing);
  });
}
