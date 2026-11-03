import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/competitions/screens/competition_publication_screen.dart';

void main() {
  testWidgets('Player preview never sends until explicit test confirmation', (
    tester,
  ) async {
    final calls = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: CompetitionPublicationScreen(
          clubId: 'club',
          request: (body) async {
            calls.add(body);
            if (body['action'] == 'send_test') {
              return {
                'outcomes': [
                  {'recipient': 'wayne@totalleisure.com', 'status': 'sent'},
                ],
              };
            }
            return {
              'id': 'preview',
              'subject': 'Competition entries',
              'html': '<p>preview</p>',
              'testRecipients': ['wayne@totalleisure.com'],
              'content': {
                'recipientName': 'Wayne Sayers',
                'entries': [
                  {
                    'competitionName': 'Singles',
                    'stageName': 'Last 16',
                    'playBy': '2027-01-22',
                    'entryName': 'Wayne',
                    'opponentName': 'Opponent',
                    'rules': '21 shots',
                  },
                ],
                'teamContacts': [
                  {
                    'name': 'My Partner',
                    'email': 'partner@example.org',
                    'mobile': '01234',
                  },
                ],
                'contacts': [],
              },
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls.length, 1);
    expect(calls.single['action'], 'preview');
    expect(find.text('Email for Wayne Sayers'), findsOneWidget);
    expect(find.text('Opponent: Opponent'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Your team contact details'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Your team contact details'), findsOneWidget);
    expect(find.text('My Partner'), findsOneWidget);
    expect(find.textContaining('partner@example.org'), findsOneWidget);
    final button = find.text('Send test copy');
    await tester.scrollUntilVisible(
      button,
      350,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Send test email?'), findsOneWidget);
    expect(calls.length, 1);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls.length, 1);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send test'));
    await tester.pumpAndSettle();
    expect(calls.length, 2);
    expect(calls.last['action'], 'send_test');
    expect(calls.last['previewId'], 'preview');
    expect(calls.last['recipients'], ['wayne@totalleisure.com']);
    expect(
      find.text('wayne@totalleisure.com: Test email sent'),
      findsOneWidget,
    );
  });
  testWidgets(
    'No-entry function exception is a helpful empty state, not a raw error',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompetitionPublicationScreen(
            clubId: 'club',
            competitionId: 'competition',
            request: (_) async => throw FunctionException(
              status: 400,
              details: {'error': 'This member has no competition entries'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('This member has no entries in this competition'),
        findsOneWidget,
      );
      expect(find.textContaining('FunctionException'), findsNothing);
      expect(find.text('Send test copy'), findsNothing);
      expect(find.text('Choose player'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
