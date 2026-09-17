import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/fixtures/open_session_communications.dart';

void main() {
  Map<String, dynamic> fixture(String mode, {bool usesRinks = true}) => {
    'requires_rsvp': true, // A legacy flag must not override the current type.
    'competition_type': {'selection_mode': mode, 'uses_rinks': usesRinks},
  };

  test('open sessions display Open regardless of legacy selection status', () {
    for (final status in ['draft', 'published', '']) {
      expect(fixtureCommunicationStatus(fixture('open'), status), 'Open');
    }
    expect(isOpenSessionFixture(fixture(' OPEN ')), isTrue);
  });

  test('selected squads and RSVP events retain publication status', () {
    for (final mode in ['rsvp', 'preselect', 'team', 'no_players', '']) {
      expect(isOpenSessionFixture(fixture(mode)), isFalse);
      expect(fixtureCommunicationStatus(fixture(mode), 'draft'), 'draft');
      expect(
        fixtureCommunicationStatus(fixture(mode), 'published'),
        'published',
      );
    }
    expect(isOpenSessionFixture(fixture('open', usesRinks: false)), isFalse);
    expect(isOpenSessionFixture(null), isFalse);
    expect(isOpenSessionFixture({}), isFalse);
  });

  testWidgets(
    'open session explains turn-up participation without repair controls',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OpenSessionCommunicationsCard()),
        ),
      );
      expect(find.text('Open session'), findsOneWidget);
      expect(find.textContaining('Players turn up'), findsOneWidget);
      expect(find.text('Fixture setup needs attention'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.text('Ready for publication'), findsNothing);
    },
  );
}
