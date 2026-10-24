import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/fixtures/next_fixture_reminder.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(768, 1024),
    const Size(1440, 1000),
  ]) {
    testWidgets('next-match overlay keeps both cards inset at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open'),
                onPressed: () => NextFixtureReminder(
                  context: context,
                  clubName: 'Club',
                  nextMatch: null,
                  now: () => DateTime.utc(2026, 10, 10),
                  openFixture: (_) async {},
                  fixtures: List.generate(
                    2,
                    (i) => {
                      'id': 'f$i',
                      'start_at': '2026-10-1${i + 1}T12:00:00Z',
                      'is_home': true,
                      'team_name': 'Team $i',
                      'competition_type': {'is_internal': true},
                      '_reminderAcceptance': i == 0 ? 'pending' : 'accepted',
                    },
                  ),
                ).show(),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final second = find.byType(Card);
      final first = find
          .ancestor(of: find.text('Team 0'), matching: find.byType(Material))
          .first;
      final firstRect = tester.getRect(first);
      final secondRect = tester.getRect(second);
      expect(firstRect.left, greaterThanOrEqualTo(32));
      expect(firstRect.right, lessThanOrEqualTo(size.width - 32));
      expect(firstRect.width, lessThanOrEqualTo(560));
      expect(secondRect.width, firstRect.width);
      expect(tester.takeException(), isNull);
      final close = find.text('OK');
      await tester.ensureVisible(close);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });
  }
}
