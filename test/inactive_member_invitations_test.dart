import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/members/inactive_member_invitations_screen.dart';

void main() {
  testWidgets(
    'preview never sends; sending needs selection and explicit confirmation',
    (t) async {
      final calls = <String>[];
      var queued = false;
      await t.pumpWidget(
        MaterialApp(
          home: InactiveMemberInvitationsScreen(
            clubId: 'club',
            call: (name, params) async {
              calls.add(name);
              if (name == 'queue_staging_club_invitations') {
                expect(params['p_confirm'], isTrue);
                expect(params['p_memberships'], ['m']);
                queued = true;
                return {'queued': 1};
              }
              return [
                {
                  'membership_id': 'm',
                  'name': 'Test Member',
                  'email': 'test@example.invalid',
                  'eligible': !queued,
                  'status': queued ? 'pending' : 'ready',
                  'subject': 'Invitation preview',
                  'body': 'Use your existing password.',
                },
              ];
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(calls, ['preview_staging_club_invitations']);
      expect(
        t
            .widget<FilledButton>(
              find.widgetWithText(
                FilledButton,
                'Review and send 0 test invitations',
              ),
            )
            .onPressed,
        isNull,
      );
      await t.tap(find.text('Preview invitation'));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Use your existing password.'),
        findsOneWidget,
      );
      expect(queued, isFalse);
      await t.ensureVisible(find.text('Select all eligible test members'));
      await t.tap(find.text('Select all eligible test members'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('Review and send 1 test invitations'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('Review and send 1 test invitations'));
      await t.pumpAndSettle();
      expect(find.text('Send 1 club invitations?'), findsOneWidget);
      expect(queued, isFalse);
      await t.tap(find.text('Send test invitations'));
      await t.pumpAndSettle();
      expect(queued, isTrue);
      expect(
        find.textContaining('Memberships remain inactive until acceptance'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Queued; membership inactive'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'recipient acceptance requires confirmation and refreshes clubs',
    (t) async {
      var accepted = false, refreshed = false;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StagingClubInvitations(
              onAccepted: (clubId) async {
                expect(clubId, 'club');
                refreshed = true;
              },
              call: (name, params) async {
                if (name == 'accept_staging_club_invitation') {
                  accepted = true;
                  return true;
                }
                return accepted
                    ? []
                    : [
                        {
                          'id': 'invite',
                          'club_id': 'club',
                          'club_name': 'Test Club',
                        },
                      ];
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Accept invitation'));
      await t.pumpAndSettle();
      expect(accepted, isFalse);
      expect(find.text('Join Test Club?'), findsOneWidget);
      await t.tap(find.text('Accept invitation').last);
      await t.pumpAndSettle();
      expect(accepted, isTrue);
      expect(refreshed, isTrue);
      expect(find.text('Test Club'), findsNothing);
    },
  );
  testWidgets('unmatched contact is provisioned only after confirmed invite', (
    t,
  ) async {
    var provisioned = false;
    await t.pumpWidget(
      MaterialApp(
        home: InactiveMemberInvitationsScreen(
          clubId: 'club',
          call: (name, params) async {
            if (name == 'provision_staging_club_invitations') {
              expect(params['contact_ids'], ['contact']);
              expect(params['confirm'], isTrue);
              provisioned = true;
              return {'queued': 1, 'errors': []};
            }
            return provisioned
                ? []
                : [
                    {
                      'contact_id': 'contact',
                      'name': 'New Member',
                      'email': 'new@example.invalid',
                      'eligible': true,
                      'status': 'ready',
                      'subject': 'Invitation',
                      'body': 'Account created only when invited.',
                    },
                  ];
          },
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(provisioned, isFalse);
    await t.tap(find.text('Select all eligible test members'));
    await t.pumpAndSettle();
    await t.tap(find.text('Review and send 1 test invitations'));
    await t.pumpAndSettle();
    expect(provisioned, isFalse);
    await t.tap(find.text('Send test invitations'));
    await t.pumpAndSettle();
    expect(provisioned, isTrue);
  });
}

