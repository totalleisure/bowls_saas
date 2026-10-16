import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/fixtures/fixture_display.dart';

void main() {
  for (final home in [true, false]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('full ${home ? 'home' : 'away'} opponent at scale $scale', (tester) async {
        tester.view.physicalSize = const Size(320, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        const opponent = 'Lewisham and Crystal Palace Indoor Bowling Club';
        final fixture = <String, dynamic>{
          'start_at': '2026-10-13T12:00:00Z',
          'is_home': home,
          'team_name': 'Friendly weekend team',
          'venue': {'name': home ? 'Home club' : opponent},
          'opponent_venue': {'name': home ? opponent : 'Home club'},
          'competition_type': {'is_internal': false},
        };
        var opened = false;
        await tester.pumpWidget(MaterialApp(home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: SingleChildScrollView(child: UnifiedFixtureCard(
            fixture: fixture, myClubName: 'Home club', onTap: () => opened = true,
          ))),
        )));
        final title = fixtureTitleUnified(fixture, myClubName: 'Home club');
        expect(title, contains(opponent));
        final finder = find.text(title);
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.size.height, greaterThan(40));
        expect(tester.takeException(), isNull);
        await tester.tap(finder);
        expect(opened, isTrue);
      });
    }
  }
}
