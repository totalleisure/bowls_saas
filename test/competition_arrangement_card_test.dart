import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/competitions/competition_repository.dart';
import 'package:bowls_saas/features/competitions/widgets/competition_arrangement_card.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('Arrangement card uses Fixture Type colours, dark=$dark', (
      tester,
    ) async {
      final background = dark ? '#123456' : '#FFF1AA';
      final foreground = dark ? '#FFFFFF' : '#142536';
      var opened = false;
      final data = CompetitionData(
        {
          'name': 'Mens Pairs',
          'fixture_type': {
            'name': 'Club Competition',
            'colour_scheme': {
              'background_hex': background,
              'foreground_hex': foreground,
            },
          },
          'settings': {
            'playing_format': 'pairs',
            'section': 'mens',
            'dress': 'Whites',
          },
        },
        [
          {'id': 'a', 'name': 'Opponent must not appear'},
        ],
        [
          {
            'id': 'r',
            'name': 'Quarter-final',
            'play_by': '2026-12-13',
            'rule_overrides': {'dress': 'Greys'},
          },
        ],
        [],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          home: Scaffold(
            body: CompetitionArrangementCard(
              data: data,
              match: {'round_id': 'r', 'match_number': 2},
              onTap: () => opened = true,
            ),
          ),
        ),
      );
      final card = tester.widget<Card>(find.byType(Card));
      expect(
        card.color,
        Color(int.parse(background.replaceFirst('#', 'FF'), radix: 16)),
      );
      final tile = tester.widget<ListTile>(find.byType(ListTile));
      final expectedForeground = Color(
        int.parse(foreground.replaceFirst('#', 'FF'), radix: 16),
      );
      expect(tile.textColor, expectedForeground);
      expect(tile.iconColor, expectedForeground);
      expect(find.byType(Chip), findsOneWidget);
      final roundPill = tester.widget<Chip>(find.byType(Chip));
      expect(roundPill.backgroundColor, expectedForeground);
      expect(roundPill.labelStyle?.color, card.color);
      expect(
        tester.getTopLeft(find.byType(Chip)).dy,
        lessThan(tester.getTopLeft(find.textContaining('Play by:')).dy),
      );
      expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);
      expect(find.text('Club Competition'), findsOneWidget);
      expect(find.textContaining('Competition Round : Quarter-final 2'), findsOneWidget);
      expect(find.textContaining('Play by: 13 Dec 2026'), findsOneWidget);
      expect(find.textContaining('Greys'), findsOneWidget);
      expect(find.text('Whites'), findsNothing);
      expect(find.text('Opponent must not appear'), findsNothing);
      await tester.tap(find.byType(ListTile));
      expect(opened, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Missing colour scheme uses theme colours', (tester) async {
    final theme = ThemeData();
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: CompetitionArrangementCard(
            data: const CompetitionData(
              {'name': 'Singles', 'settings': {}},
              [],
              [],
              [],
            ),
            match: const {'match_number': 1},
            onTap: () {},
          ),
        ),
      ),
    );
    expect(
      tester.widget<Card>(find.byType(Card)).color,
      theme.colorScheme.surface,
    );
    expect(
      tester.widget<ListTile>(find.byType(ListTile)).textColor,
      theme.colorScheme.onSurface,
    );
    expect(tester.takeException(), isNull);
  });
}
