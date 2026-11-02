import 'dart:convert';
import 'package:bowls_saas/features/competitions/competition_repository.dart';
import 'package:bowls_saas/core/widgets/club_member_picker_page.dart';
import 'package:bowls_saas/features/competitions/screens/competition_season_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EntryRepository extends CompetitionRepository {
  @override
  Future<bool> publicationEnabled(String clubId) async => true;
  final int players;
  final entries = <CompetitionRow>[];
  final entered = <String>{};
  String? savedName;
  List<String>? savedIds;
  List<String>? drawIds;
  @override
  Future<void> build(String id, List<String> order) async {
    drawIds = List.of(order);
  }

  EntryRepository(this.players) : super(Supabase.instance.client);
  @override
  Future<CompetitionData> load(String clubId, String id) async =>
      CompetitionData(
        {
          'id': id,
          'name': 'Test competition',
          'season': '2026',
          'status': 'draft',
          'settings': {'players_per_entry': players},
        },
        List.of(entries),
        [],
        [],
        Set.of(entered),
      );
  @override
  Future<void> addEntry(
    String id,
    String name,
    List<String> members,
    String payment,
    num? handicap,
  ) async {
    savedName = name;
    savedIds = members;
    entered.addAll(members);
    entries.add({
      'id': 'entry',
      'name': name,
      'payment_status': payment,
      'handicap': handicap,
    });
  }

  @override
  Future<int> addSingles(String id, List<String> members) async {
    savedIds = members;
    for (final m in members) {
      if (entered.add(m)) {
        entries.add({
          'id': m,
          'name': m == 'alex'
              ? 'Alex Smith'
              : m == 'blair'
              ? 'Blair Jones'
              : m,
          'payment_status': 'not_recorded',
          'handicap': null,
        });
      }
    }
    return members.length;
  }

  @override
  Future<int> addTeams(String id, List<String> members) async {
    savedIds = List.of(members);
    for (var i = 0; i < members.length; i += players) {
      final group = members.sublist(i, i + players);
      String label(String id) => id == 'alex'
          ? 'Alex Smith'
          : id == 'blair'
          ? 'Blair Jones'
          : id;
      final name = group.map(label).join(' / ');
      savedName = name;
      entries.add({
        'id': 'team-${entries.length + 1}',
        'name': name,
        'members': group,
        'payment_status': 'not_recorded',
        'handicap': null,
      });
      entered.addAll(group);
    }
    return members.length ~/ players;
  }

  @override
  Future<void> setPaid(String id, bool paid) async =>
      entries.firstWhere((e) => e['id'] == id)['payment_status'] = paid
      ? 'paid'
      : 'unpaid';
  @override
  Future<void> setHandicap(String id, num? handicap) async =>
      entries.firstWhere((e) => e['id'] == id)['handicap'] = handicap;
}

void main() {
  var pickerRows = <Map<String, String>>[];
  setUp(
    () => pickerRows = [
      {'member_profile_id': 'alex', 'picker_name': 'Alex Smith'},
      {'member_profile_id': 'blair', 'picker_name': 'Blair Jones'},
    ],
  );
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        final search = '${body['p_search']}'.toLowerCase();
        final rows = pickerRows
            .where(
              (r) =>
                  search.isEmpty ||
                  r['picker_name']!.toLowerCase().contains(search),
            )
            .toList();
        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  Future<void> openEntries(WidgetTester tester, EntryRepository repo) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompetitionSeasonScreen(
          clubId: 'club',
          competitionId: 'competition',
          canManage: true,
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entries'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Entries and draw review use saved positions with reversed repository rows',
    (tester) async {
      final repo = EntryRepository(2);
      repo.entries.addAll(
        List.generate(24, (index) {
          final position = 24 - index;
          return <String, dynamic>{
            'id': 'pair-$position',
            'entry_order': position,
            'name': position == 1
                ? 'Richard Allen / Helen Prince'
                : position == 24
                ? 'Lesley Harris / Warren Harris'
                : 'Pair $position',
            'payment_status': 'not_recorded',
            'handicap': null,
          };
        }),
      );
      await openEntries(tester, repo);
      final first = find.widgetWithText(
        ListTile,
        'Richard Allen / Helen Prince',
      );
      expect(first, findsOneWidget);
      expect(
        find.descendant(of: first, matching: find.text('1')),
        findsOneWidget,
      );
      await tester.tap(find.text('Draw'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review and create draw'));
      await tester.pumpAndSettle();
      final review = find.byType(AlertDialog);
      final reviewedFirst = find.descendant(
        of: review,
        matching: find.widgetWithText(ListTile, 'Richard Allen / Helen Prince'),
      );
      expect(reviewedFirst, findsOneWidget);
      expect(
        find.descendant(of: reviewedFirst, matching: find.text('1')),
        findsOneWidget,
      );
      await tester.tap(find.text('Create draw'));
      await tester.pumpAndSettle();
      expect(repo.drawIds, List.generate(24, (i) => 'pair-${i + 1}'));
      expect(
        repo.entries.first['entry_order'],
        24,
        reason: 'Sorting must not mutate repository records',
      );
    },
  );

  testWidgets(
    '35 selections retain click sequence through search, review and save',
    (tester) async {
      pickerRows = List.generate(
        35,
        (i) => {
          'member_profile_id': 'm${i + 1}',
          'picker_name': 'Player ${(i + 1).toString().padLeft(2, '0')}',
        },
      );
      final repo = EntryRepository(1);
      await openEntries(tester, repo);
      await tester.tap(find.text('Add players'));
      await tester.pumpAndSettle();
      for (var i = 35; i >= 1; i--) {
        final name = 'Player ${i.toString().padLeft(2, '0')}';
        await tester.enterText(find.byType(TextField), name);
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, name));
        await tester.pumpAndSettle();
      }
      expect(find.text('First: Player 35 · Last: Player 01'), findsOneWidget);
      await tester.tap(find.text('Review 35'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm player order'), findsOneWidget);
      expect(find.text('Player 35'), findsOneWidget);
      await tester.tap(find.text('Add 35 players'));
      await tester.pumpAndSettle();
      expect(repo.savedIds, List.generate(35, (i) => 'm${35 - i}'));
      expect(
        repo.entries.map((e) => e['id']).toList(),
        List.generate(35, (i) => 'm${35 - i}'),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    '46 selected players are reviewed and saved as 23 consecutive pairs',
    (tester) async {
      pickerRows = List.generate(
        46,
        (i) => {
          'member_profile_id': 'm${i + 1}',
          'picker_name': 'Player ${(i + 1).toString().padLeft(2, '0')}',
        },
      );
      final repo = EntryRepository(2);
      await openEntries(tester, repo);
      await tester.tap(find.text('Add pairs'));
      await tester.pumpAndSettle();
      for (var i = 1; i <= 46; i++) {
        final name = 'Player ${i.toString().padLeft(2, '0')}';
        await tester.enterText(find.byType(TextField), name);
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ListTile, name));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Review 46'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm 23 pairs'), findsOneWidget);
      expect(find.text('Player 01 / Player 02'), findsOneWidget);
      final list = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Pair 23'),
        250,
        scrollable: list,
      );
      await tester.pumpAndSettle();
      expect(find.text('Player 45 / Player 46'), findsOneWidget);
      await tester.tap(find.text('Save 23 pairs'));
      await tester.pumpAndSettle();
      expect(repo.savedIds, List.generate(46, (i) => 'm${i + 1}'));
      expect(repo.entries.length, 23);
      for (var i = 0; i < 23; i++) {
        expect(repo.entries[i]['members'], ['m${i * 2 + 1}', 'm${i * 2 + 2}']);
      }
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'Repository sends all 35 member IDs to RPC in the supplied sequence',
    () async {
      final ids = List.generate(35, (i) => 'member-${35 - i}');
      List<dynamic>? received;
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          received = jsonDecode(request.body)['p_members'];
          return http.Response(
            '35',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      expect(
        await CompetitionRepository(client).addSingles('competition', ids),
        35,
      );
      expect(received, ids);
      await client.dispose();
    },
  );
  testWidgets(
    'Existing picker callers return their selection without a review step',
    (tester) async {
      List<String>? returned;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  returned = await Navigator.of(context).push<List<String>>(
                    MaterialPageRoute(
                      builder: (_) => const ClubMemberPickerPage(
                        clubId: 'club',
                        title: 'Select members',
                        allowMultiple: true,
                      ),
                    ),
                  );
                },
                child: const Text('Pick'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pick'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blair Jones'));
      await tester.tap(find.text('Alex Smith'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Return 2'));
      await tester.pumpAndSettle();
      expect(returned, ['blair', 'alex']);
      expect(find.text('Confirm player order'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final players in [1, 2]) {
    testWidgets(
      'Select multiple players: ${players == 1 ? 'separate singles' : 'one pairs team'} without extra questions',
      (tester) async {
        final repo = EntryRepository(players);
        await openEntries(tester, repo);
        await tester.tap(find.text(players == 1 ? 'Add players' : 'Add pairs'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Blair Jones'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Alex');
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Alex Smith'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Review 2'));
        await tester.pumpAndSettle();
        expect(
          find.text(players == 1 ? 'Confirm player order' : 'Confirm 1 pair'),
          findsOneWidget,
        );
        await tester.tap(
          find.text(players == 1 ? 'Add 2 players' : 'Save 1 pair'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Add entry'), findsNothing);
        expect(repo.savedIds, ['blair', 'alex']);
        expect(repo.entries.length, players == 1 ? 2 : 1);
        if (players == 2) expect(repo.savedName, 'Blair Jones / Alex Smith');
        expect(
          repo.entries.every(
            (e) =>
                e['handicap'] == null && e['payment_status'] == 'not_recorded',
          ),
          isTrue,
        );
        await tester.tap(find.text(players == 1 ? 'Add players' : 'Add pairs'));
        await tester.pumpAndSettle();
        expect(find.text('Alex Smith'), findsNothing);
        expect(find.text('Blair Jones'), findsNothing);
        expect(find.text('No members found.'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'An incomplete pair stays selected until the second player is added',
    (tester) async {
      final repo = EntryRepository(2);
      await openEntries(tester, repo);
      await tester.tap(find.text('Add pairs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alex Smith'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review 1'));
      await tester.pumpAndSettle();
      expect(
        find.text('Select players in pair order · 1 selected'),
        findsOneWidget,
      );
      expect(repo.savedIds, isNull);
      await tester.tap(find.text('Blair Jones'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review 2'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm 1 pair'), findsOneWidget);
      await tester.tap(find.text('Save 1 pair'));
      await tester.pumpAndSettle();
      expect(repo.savedIds, ['alex', 'blair']);
      expect(repo.entries.length, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Entry list changes Paid and positive/negative handicap independently',
    (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = EntryRepository(1);
      await repo.addSingles('competition', ['alex']);
      await openEntries(tester, repo);
      await tester.tap(find.text('Paid'));
      await tester.pumpAndSettle();
      expect(repo.entries.single['payment_status'], 'paid');
      await tester.tap(find.text('Handicap'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '+3');
      await tester.tap(find.text('Save handicap'));
      await tester.pumpAndSettle();
      expect(repo.entries.single['handicap'], 3);
      expect(find.text('Handicap +3'), findsOneWidget);
      await tester.tap(find.byTooltip('Edit handicap'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '-2');
      await tester.tap(find.text('Save handicap'));
      await tester.pumpAndSettle();
      expect(repo.entries.single['handicap'], -2);
      expect(repo.entries.single['payment_status'], 'paid');
      await tester.tap(find.text('Handicap -2'));
      await tester.pumpAndSettle();
      expect(repo.entries.single['handicap'], isNull);
      await tester.tap(find.text('Paid'));
      await tester.pumpAndSettle();
      expect(repo.entries.single['payment_status'], 'unpaid');
      expect(tester.takeException(), isNull);
    },
  );
}
