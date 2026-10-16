import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/team/selected_member_interaction_card.dart';
import 'package:bowls_saas/features/fixtures/widgets/fixture_timing_controls.dart';

void main() {
  for (final width in [320.0, 393.0, 900.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('player actions and timing at $width / $scale', (tester) async {
        tester.view.physicalSize = Size(width, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var returned = false;
        var edited = false;
        await tester.pumpWidget(MaterialApp(home: MediaQuery(
          data: MediaQueryData(size: Size(width, 1800), textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: SingleChildScrollView(child: Column(children: [
            SelectedMemberInteractionCard(color: Colors.blue.shade50,
              title: const Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text('Alexandra Example Player'), Text('SELECTED')]),
              subtitle: const Text('Not allocated\nSelected — not awaiting acceptance\n07710 325696'),
              trailing: Wrap(children: [
                TextButton.icon(onPressed: () => returned = true,
                  icon: const Icon(Icons.undo), label: const Text('Return to pool')),
                PopupMenuButton<String>(itemBuilder: (_) => [
                  const PopupMenuItem(value: 'reserve', child: Text('Make reserve')),
                ]),
              ])),
            Padding(padding: const EdgeInsets.all(16), child: FixtureTimingControls(
              start: 'Friday 30 October 2026, 9:00 a.m.',
              end: 'Friday 30 October 2026, 11:00 a.m.',
              onEditStart: () => edited = true,
            )),
          ]))),
        )));
        expect(tester.takeException(), isNull);
        if (width < 600 * scale) {
          expect(tester.getTopLeft(find.text('Return to pool')).dy,
            greaterThan(tester.getBottomLeft(find.textContaining('Not allocated')).dy));
          expect(tester.getTopLeft(find.text('End')).dy,
            greaterThan(tester.getBottomLeft(find.text('9:00\u00a0a.m.')).dy));
        }
        await tester.tap(find.text('Return to pool'));
        expect(returned, isTrue);
        await tester.ensureVisible(find.text('9:00\u00a0a.m.'));
        await tester.tap(find.text('9:00\u00a0a.m.'));
        expect(edited, isTrue);
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        expect(find.text('Make reserve'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
