import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/fixtures/fixture_display.dart';
import 'package:bowls_saas/features/fixtures/widgets/fixture_response_panel.dart';

void main() {
  final fixture = {
    'id': 'match',
    'start_at': '2026-10-13T12:00:00Z',
    'is_home': true,
    'team_name': 'Test match',
    'competition_type': {'is_internal': true},
  };
  Widget card({
    bool responses = true,
    bool cancelled = false,
    required VoidCallback open,
    required Future<void> Function(String) save,
  }) => MaterialApp(
    home: Scaffold(
      body: UnifiedFixtureCard(
        fixture: {...fixture, if (cancelled) 'cancelled_at': '2026-10-11'},
        myClubName: 'Club',
        onTap: open,
        responseBuilder: responses
            ? (colour) => FixtureResponsePanel(
                embedded: true,
                foregroundColor: colour,
                status: null,
                onResponse: save,
              )
            : null,
      ),
    ),
  );

  testWidgets(
    'response belongs inside one card and buttons do not open details',
    (tester) async {
      var opens = 0;
      String? saved;
      await tester.pumpWidget(
        card(open: () => opens++, save: (value) async => saved = value),
      );
      expect(find.byType(Card), findsOneWidget);
      expect(
        find.ancestor(of: find.text('Available'), matching: find.byType(Card)),
        findsOneWidget,
      );
      await tester.tap(find.text('Not available'));
      await tester.pumpAndSettle();
      expect(saved, 'no');
      expect(opens, 0);
      await tester.tap(find.text('Test match'));
      await tester.pumpAndSettle();
      expect(opens, 1);
    },
  );

  testWidgets(
    'ordinary and cancelled fixture cards show no response questions',
    (tester) async {
      for (final cancelled in [false, true]) {
        await tester.pumpWidget(
          card(
            responses: cancelled,
            cancelled: cancelled,
            open: () {},
            save: (_) async {},
          ),
        );
        expect(find.byType(FixtureResponsePanel), findsNothing);
        expect(find.text('Available'), findsNothing);
      }
    },
  );
}
