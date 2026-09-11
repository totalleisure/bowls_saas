import 'package:bowls_saas/features/members/member_import_options_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(WidgetTester tester, ValueChanged<bool?> onResult) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => onResult(
                await showMemberImportOptions(
                  context: context,
                  fileName: 'committee.csv',
                  bytes: 100,
                ),
              ),
              child: const Text('Choose CSV'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose CSV'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'each import defaults to Inactive and confirms false, not cancellation',
    (tester) async {
      bool? result;
      var called = false;
      await open(tester, (value) {
        result = value;
        called = true;
      });
      expect(find.text('Inactive'), findsOneWidget);
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(called, isTrue);
      expect(result, isFalse);
    },
  );

  testWidgets(
    'Active choice returns true; next import starts with Inactive again',
    (tester) async {
      bool? result;
      await open(tester, (value) => result = value);
      await tester.tap(find.text('Inactive'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Active').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      await tester.tap(find.text('Choose CSV'));
      await tester.pumpAndSettle();
      expect(find.text('Inactive'), findsOneWidget);
      await tester.tap(find.text('Import'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    },
  );

  testWidgets('Cancel returns null rather than choosing a status', (
    tester,
  ) async {
    bool? result = true;
    await open(tester, (value) => result = value);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
