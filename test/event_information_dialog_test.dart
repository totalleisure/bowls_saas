import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/fixtures/widgets/fixture_information_dialog.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final action in ['Save', 'Cancel', 'Back']) {
      testWidgets(
        '$platform $action with focused input and keyboard transition',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 1600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          String saved = 'Quiz Night';
          int saves = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: platform),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () async {
                      final result = await showDialog<String>(
                        context: context,
                        builder: (_) => FixtureInformationDialog(
                          initialText: saved,
                          isEvent: true,
                        ),
                      );
                      if (result != null) {
                        saved = result;
                        saves++;
                      }
                    },
                    child: const Text('Edit'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Edit'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField),
            'Quiz Night - Bring a friend.',
          );
          expect(tester.testTextInput.isVisible, isTrue);
          if (action == 'Back') {
            await tester.binding.handlePopRoute();
          } else {
            await tester.tap(find.text(action));
          }
          await tester.pump();
          // A keyboard metrics update can rebuild the field while the route exits.
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pump();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(saves, action == 'Save' ? 1 : 0);
          expect(
            saved,
            action == 'Save' ? 'Quiz Night - Bring a friend.' : 'Quiz Night',
          );
          tester.view.resetViewInsets();
          await tester.tap(find.text('Edit'));
          await tester.pumpAndSettle();
          expect(find.text(saved), findsOneWidget);
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
