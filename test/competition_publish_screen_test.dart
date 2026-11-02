import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/competitions/screens/competition_publish_screen.dart';

Map<String, dynamic> summary({
  bool published = false,
  bool prepared = false,
  int eligible = 5,
  int pending = 5,
  int sent = 0,
  int uncertain = 0,
}) => {
  'competitionName': 'Mens Pairs',
  'published': published,
  'event_id': prepared ? 'event' : null,
  'total_players': 52,
  'eligible_count': eligible,
  'missing_email_count': 3,
  'restricted_count': 49 - eligible,
  'pending': pending,
  'sent': sent,
  'claimed': 0,
  'uncertain': uncertain,
  'recipients': <dynamic>[],
};
Future<void> open(
  WidgetTester t,
  Future<Map<String, dynamic>> Function(Map<String, dynamic>) request,
) async {
  t.view.physicalSize = const Size(1000, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      home: CompetitionPublishScreen(
        clubId: 'club',
        competitionId: 'pairs',
        request: request,
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'Publish is competition-specific and requires confirmation; completed publication cannot resend',
    (t) async {
      final calls = <Map<String, dynamic>>[];
      await open(t, (body) async {
        calls.add(body);
        return body['action'] == 'publication_status'
            ? summary()
            : summary(published: true, prepared: true, pending: 0, sent: 5);
      });
      expect(calls.single['action'], 'publication_status');
      await t.tap(find.text('Publish competition and send emails'));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(calls, hasLength(1));
      await t.tap(find.text('Publish competition and send emails'));
      await t.pumpAndSettle();
      await t.tap(find.text('Publish and send'));
      await t.pumpAndSettle();
      expect(calls.last, {
        'action': 'publish',
        'clubId': 'club',
        'competitionId': 'pairs',
      });
      expect(find.text('Published'), findsOneWidget);
      expect(find.textContaining('Sent: 5'), findsOneWidget);
      expect(find.text('Publish competition and send emails'), findsNothing);
      expect(find.text('Send pending publication emails'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('Already published draw can send its first publication emails', (
    t,
  ) async {
    final actions = <String>[];
    await open(t, (body) async {
      actions.add(body['action'].toString());
      return actions.length == 1
          ? summary(published: true)
          : summary(published: true, prepared: true, pending: 0, sent: 5);
    });
    await t.tap(find.text('Send publication emails'));
    await t.pumpAndSettle();
    await t.tap(find.text('Send emails'));
    await t.pumpAndSettle();
    expect(actions, ['publication_status', 'publish']);
  });
  testWidgets(
    'No eligible accounts still allows publishing without sending; uncertain rows cannot auto-resend',
    (t) async {
      await open(
        t,
        (body) async => body['action'] == 'publication_status'
            ? summary(eligible: 0, pending: 0)
            : summary(published: true, prepared: true, eligible: 0, pending: 0),
      );
      await t.tap(find.text('Publish competition and send emails'));
      await t.pumpAndSettle();
      expect(find.textContaining('without sending emails'), findsOneWidget);
      await t.tap(find.text('Publish and send'));
      await t.pumpAndSettle();
      expect(find.textContaining('0 emails sent:'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await open(
        t,
        (body) async => summary(
          published: true,
          prepared: true,
          pending: 0,
          sent: 4,
          uncertain: 1,
        ),
      );
      expect(
        find.textContaining('will not be retried automatically'),
        findsOneWidget,
      );
      expect(find.byType(FilledButton), findsNothing);
    },
  );
}
