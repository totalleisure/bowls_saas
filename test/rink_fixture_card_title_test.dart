import 'package:bowls_saas/features/fixtures/rink_fixture_card_title.dart';
import 'package:bowls_saas/features/fixtures/member_booking_repository.dart';
import 'package:bowls_saas/features/fixtures/widgets/member_booking_timeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixture = <String, dynamic>{
    'team_name': '100 Up: Pat v Jane',
    'competition_types': {'name': 'Club Competition', 'is_internal': true},
    'start_at': '2042-11-19T11:00:00Z',
    'end_at': '2042-11-19T13:00:00Z',
    'rinks_required': 1,
    'fixture_rinks': [
      {'home_rink_label': 'R1'},
    ],
  };
  test(
    'Different labels are shown; empty and identical labels do not repeat the type',
    () {
      expect(
        rinkFixtureCardTitle(fixture),
        'Club Competition\n100 Up: Pat v Jane',
      );
      for (final label in ['', 'Club Competition', ' club   competition ']) {
        expect(
          rinkFixtureCardTitle({...fixture, 'team_name': label}),
          'Club Competition',
        );
      }
      expect(
        rinkFixtureCardTitle({
          ...fixture,
          'opponent_name': 'Bromley',
          'competition_types': {'name': 'League', 'is_internal': false},
        }),
        'Bromley\n100 Up: Pat v Jane',
      );
    },
  );
  for (final density in MemberTimelineDensity.values) {
    testWidgets(
      'Quick booking shows fixture type and distinct label without overflow: $density',
      (t) async {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 360,
                child: MemberBookingTimeline(
                  date: DateTime(2042, 11, 19),
                  labels: const ['R1'],
                  day: MemberBookingDay([fixture], []),
                  density: density,
                  onSelect: (_, _) {},
                ),
              ),
            ),
          ),
        );
        expect(
          find.text('Club Competition\n100 Up: Pat v Jane'),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
}
