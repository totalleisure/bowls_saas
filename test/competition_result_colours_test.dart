import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/competitions/competition_repository.dart';
import 'package:bowls_saas/features/competitions/widgets/competition_result_card.dart';
import 'package:bowls_saas/features/competitions/screens/competition_season_screen.dart';
import 'competition_player_result_screen_test.dart' show ResultRepository;

class PersonalResults extends ResultRepository {
  String entry = 'a';
  @override
  Future<List<CompetitionRow>> myEntries(
    String memberId,
    List<String> ids,
  ) async => [
    {'competition_id': 'c', 'entry_id': entry},
  ];
}

void main() {
  for (final hasEntries in [false, true]) {
    testWidgets('Admin initial tab follows entries: $hasEntries', (t) async {
      final repo = ResultRepository();
      if (!hasEntries) repo.data.entries.clear();
      await t.pumpWidget(
        MaterialApp(
          home: CompetitionSeasonScreen(
            clubId: 'club',
            competitionId: 'c',
            canManage: true,
            repository: repo,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        DefaultTabController.of(t.element(find.byType(TabBar))).index,
        hasEntries ? 1 : 0,
      );
    });
  }
  for (final side in ['a', 'b']) {
    testWidgets(
      'Confirmed result reflects viewer entry $side in the Draw card',
      (t) async {
        final repo = PersonalResults()..entry = side;
        final m = repo.data.matches.first;
        m.addAll({
          'status': 'completed',
          'score_a': 21,
          'score_b': 12,
          'winner_entry_id': 'a',
        });
        await t.pumpWidget(
          MaterialApp(
            home: CompetitionSeasonScreen(
              clubId: 'club',
              competitionId: 'c',
              canManage: false,
              memberId: 'me',
              repository: repo,
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(
          DefaultTabController.of(t.element(find.byType(TabBar))).index,
          1,
        );
        expect(find.text(side == 'a' ? 'You won' : 'You lost'), findsOneWidget);
        final card = t.widget<Card>(
          find.descendant(
            of: find.byType(CompetitionResultCard),
            matching: find.byType(Card),
          ),
        );
        expect(
          card.color,
          side == 'a' ? Colors.green.shade100 : Colors.red.shade100,
        );
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('Pending result never announces a win or loss', (t) async {
    final repo = PersonalResults();
    repo.data.matches.first.addAll({
      'status': 'result_pending',
      'score_a': 21,
      'score_b': 12,
      'proposed_winner_entry_id': 'a',
    });
    await t.pumpWidget(
      MaterialApp(
        home: CompetitionSeasonScreen(
          clubId: 'club',
          competitionId: 'c',
          canManage: false,
          memberId: 'me',
          repository: repo,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byType(CompetitionResultCard), findsNothing);
    expect(find.text('You won'), findsNothing);
    expect(find.text('You lost'), findsNothing);
  });
  testWidgets('Admin who is not an entrant sees a neutral result', (t) async {
    final repo = ResultRepository();
    final m = repo.data.matches.first;
    m.addAll({
      'status': 'completed',
      'score_a': 12,
      'score_b': 21,
      'winner_entry_id': 'b',
    });
    await t.pumpWidget(
      MaterialApp(
        home: CompetitionResultCard(data: repo.data, match: m),
      ),
    );
    expect(find.text('Confirmed result'), findsOneWidget);
    expect(find.text('You lost'), findsNothing);
    expect(t.widget<Card>(find.byType(Card)).color, Colors.blue.shade50);
  });
  testWidgets('Fixture Type styles competition, names and instruction cards', (
    t,
  ) async {
    final repo = ResultRepository();
    repo.data.competition['fixture_type'] = {
      'colour_scheme': {
        'background_hex': '#123456',
        'foreground_hex': '#FFFFFF',
      },
    };
    t.view.physicalSize = const Size(1000, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MaterialApp(
        home: CompetitionMatchScreen(
          data: repo.data,
          match: repo.data.matches.first,
          canManage: false,
          canSubmit: true,
          ownEntryIds: const {'a'},
          repository: repo,
        ),
      ),
    );
    await t.pumpAndSettle();
    final heading = t.widget<Card>(
      find.byKey(const ValueKey('competition-heading-card')),
    );
    final names = t.widget<Card>(
      find.byKey(const ValueKey('competition-names-card')),
    );
    final instructions = t.widget<Card>(
      find.byKey(const ValueKey('competition-instructions-card')),
    );
    expect(heading.color, const Color(0xff123456));
    expect(names.color, isNot(heading.color));
    expect(instructions.color, isNot(names.color));
    expect(t.takeException(), isNull);
  });
}
