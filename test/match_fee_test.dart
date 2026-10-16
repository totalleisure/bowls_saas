import 'package:bowls_saas/features/fixtures/widgets/match_fee_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  testWidgets(
    'fee dialog can save, cancel, clear and reopen without lifecycle errors',
    (tester) async {
      MatchFeeEditResult? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showDialog<MatchFeeEditResult>(
                    context: context,
                    builder: (_) => const MatchFeeDialog(initialPence: 750),
                  );
                },
                child: const Text('Edit fee'),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        final action = i == 1 ? 'Cancel' : 'Save';
        await tester.tap(find.text('Edit fee'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextFormField),
          i == 2 ? '' : '8.25',
        );
        await tester.tap(find.text(action));
        // Exercise the outgoing route while its text field is still mounted.
        await tester.pump();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (i == 0) expect(result!.pence, 825);
        if (i == 1) expect(result, isNull);
        if (i == 2) {
          expect(result, isNotNull);
          expect(result!.pence, isNull);
        }
      }
    },
  );
  test('GBP fees parse exactly without floating point rounding', () {
    expect(parseMatchFeePence('7.50'), 750);
    expect(parseMatchFeePence('7.5'), 750);
    expect(parseMatchFeePence('7'), 700);
    expect(parseMatchFeePence('0'), 0);
    expect(parseMatchFeePence(''), isNull);
    expect(matchFeeAmount(750), '7.50');
    for (final input in ['-1', '1.234', 'NaN', '1e3', '£7.50', '1,50']) {
      expect(() => parseMatchFeePence(input), throwsFormatException);
    }
  });
}
