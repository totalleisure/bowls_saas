import 'dart:io';

import 'package:bowls_saas/features/clubs/club_access.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

ClubAccess accessFor(String role) => ClubAccess(
  currentMemberId: 'member-id',
  isSuperuser: false,
  isClubAdmin: role == 'admin',
  isSelector: role == 'selector',
  membershipRole: role,
  hasActiveMembership: true,
);

class _ProcessingAccessHarness extends StatelessWidget {
  const _ProcessingAccessHarness({required this.access});

  final ClubAccess access;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Text('Historical fixture'),
            if (access.canWrite) ...[
              const Text('Book Fixture'),
              const Text('Manage Team'),
              const Text('RSVP'),
            ],
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('Guest sees view content but no processing controls', (
    tester,
  ) async {
    await tester.pumpWidget(
      _ProcessingAccessHarness(access: accessFor('guest')),
    );

    expect(find.text('Historical fixture'), findsOneWidget);
    expect(find.text('Book Fixture'), findsNothing);
    expect(find.text('Manage Team'), findsNothing);
    expect(find.text('RSVP'), findsNothing);
  });

  testWidgets('ordinary Member retains processing controls', (tester) async {
    await tester.pumpWidget(
      _ProcessingAccessHarness(access: accessFor('member')),
    );

    expect(find.text('Historical fixture'), findsOneWidget);
    expect(find.text('Book Fixture'), findsOneWidget);
    expect(find.text('Manage Team'), findsOneWidget);
    expect(find.text('RSVP'), findsOneWidget);
  });

  test('active processing entry points use the central capability', () {
    final dashboard = source('lib/features/clubs/club_dashboard_screen.dart');
    final fixtures = source('lib/features/fixtures/fixtures_screen.dart');
    final create = source('lib/features/fixtures/create_fixture_page.dart');
    final rinks = source('lib/features/diary/rinks_day_view.dart');
    final controlPanel = source('lib/features/clubs/club_home_screen.dart');
    final details = source('lib/features/fixtures/fixture_details_page.dart');
    final volunteerLists = source(
      'lib/features/communications/member_mailing_lists_screen.dart',
    );

    for (final dart in [
      dashboard,
      fixtures,
      create,
      rinks,
      controlPanel,
      volunteerLists,
    ]) {
      expect(dart, contains('loadClubAccess('));
      expect(dart, contains('access.canWrite'));
    }

    expect(dashboard, contains('if (_canWrite)'));
    expect(dashboard, contains('allowVolunteerLists: _canWrite'));
    expect(fixtures, contains('floatingActionButton: _canWrite'));
    expect(fixtures, contains('if (!_canWrite) return;'));
    expect(create, contains('if (!_loading && !_canWrite)'));
    expect(create, contains('if (!_canWrite) return;'));
    expect(rinks, contains('if (!_canBookFixtureFromRinks) return;'));
    expect(controlPanel, contains('if (!_canWrite)'));
    expect(volunteerLists, contains('if (!_canWrite) return;'));
    expect(
      volunteerLists,
      contains('Volunteer list changes are not available'),
    );
    expect(details, contains('final canRespondToTeamSelection = _canWrite'));
    expect(details, contains('return _canWrite &&'));
    expect(details, contains('if (!_canRsvpToFixture) return;'));
    expect(details, contains('if (!_canWrite) return;'));
  });
}
