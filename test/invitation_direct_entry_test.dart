import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/members/inactive_member_invitations_screen.dart';
import 'package:bowls_saas/features/clubs/club_registration_screen.dart';

void main() {
  testWidgets('confirmed acceptance opens the invited club directly', (
    t,
  ) async {
    String? entered;
    var accepted = false;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                const Text('My existing club'),
                StagingClubInvitations(
                  onAccepted: (clubId) async {
                    entered = clubId;
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(body: Text('Inside $clubId')),
                      ),
                    );
                  },
                  call: (name, params) async {
                    if (name == 'accept_staging_club_invitation') {
                      expect(params['p_id'], 'invite');
                      accepted = true;
                      return true;
                    }
                    return accepted
                        ? []
                        : [
                            {
                              'id': 'invite',
                              'club_id': 'invited-club',
                              'club_name': 'Coney Hall',
                            },
                          ];
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Accept invitation'));
    await t.pumpAndSettle();
    expect(entered, isNull);
    await t.tap(find.text('Accept invitation').last);
    await t.pumpAndSettle();
    expect(entered, 'invited-club');
    expect(find.text('Inside invited-club'), findsOneWidget);
    expect(find.text('My existing club'), findsNothing);
  });
  testWidgets('rejected acceptance never enters a club', (t) async {
    var entered = false;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StagingClubInvitations(
            onAccepted: (_) async {
              entered = true;
            },
            call: (name, params) async =>
                name == 'accept_staging_club_invitation'
                ? false
                : [
                    {
                      'id': 'invite',
                      'club_id': 'club',
                      'club_name': 'Coney Hall',
                    },
                  ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Accept invitation'));
    await t.pumpAndSettle();
    await t.tap(find.text('Accept invitation').last);
    await t.pumpAndSettle();
    expect(entered, isFalse);
    expect(find.textContaining('could not be accepted'), findsOneWidget);
  });
  testWidgets('welcome setup control is compact and still opens registration', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(home: Scaffold(body: ClubSetupEntry(welcome: true))),
    );
    await t.pumpAndSettle();
    final control = find.byType(TextButton);
    expect(t.getSize(control).width, lessThan(400));
    expect(t.getSize(control).height, lessThan(64));
    expect(find.byType(Card), findsNothing);
    await t.tap(control);
    await t.pumpAndSettle();
    expect(find.byType(ClubRegistrationScreen), findsOneWidget);
  });
}
