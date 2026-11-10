import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/scorecards/fixture_scorecard_identity.dart';

void main() {
  testWidgets(
    'Entry identifies both pairs, marker, round and Club date/time on a narrow screen',
    (t) async {
      t.view.physicalSize = const Size(360, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FixtureScorecardIdentity(
              snapshot: {
                'playersPerSide': 2,
                'roundName': 'Preliminary 2',
                'startAt': '2026-11-05T13:30:00Z',
                'endAt': '2026-11-05T16:30:00Z',
                'players': [
                  {'position': 102, 'name': 'Ajay Cambridge'},
                  {'position': 1, 'name': 'Dave Hever'},
                  {'position': 201, 'name': 'Wayne @ Me'},
                  {'position': 101, 'name': 'Wayne iCloud'},
                  {'position': 2, 'name': 'Wayne Telius'},
                ],
                'rules': {'scoring': 'Unrecognised rule prose'},
              },
            ),
          ),
        ),
      );
      expect(find.text('Preliminary 2'), findsOneWidget);
      expect(find.text('Thu 5 Nov 2026 · 13:30–16:30'), findsOneWidget);
      expect(
        find.text('Dave Hever / Wayne Telius\nv Wayne iCloud / Ajay Cambridge'),
        findsOneWidget,
      );
      expect(find.text('Marker: Wayne @ Me'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
