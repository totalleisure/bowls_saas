import 'package:bowls_saas/features/clubs/club_access.dart';
import 'package:bowls_saas/features/competitions/competition_repository.dart';
import 'package:bowls_saas/features/competitions/competition_draw_pdf.dart';
import 'dart:convert';
import 'dart:io';
import 'package:bowls_saas/features/competitions/screens/competitions_screen.dart';
import 'package:bowls_saas/features/competitions/screens/competition_season_screen.dart';
import 'package:bowls_saas/features/competitions/screens/competition_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

CompetitionData sample({
  bool published = true,
  bool resolved = false,
}) => CompetitionData(
  {
    'id': 'competition',
    'club_id': 'club',
    'fixture_type_id': 'type',
    'name': 'Club Singles',
    'season': '2026–2027',
    'status': published ? 'published' : 'draft',
    'settings': {
      'section': 'open',
      'scoring': '21 shots',
      'rinks_required': 1,
      'playing_format': 'singles',
      'players_per_entry': 1,
      'booking_minutes': 150,
      'time_limit_mode': 'none',
      'rules':
          '18 ends or 2.5 hours. Last jack before 2h20. Re-spotted jacks; no dead ends.',
    },
  },
  [
    {'id': 'a', 'name': 'Alex'},
    {'id': 'b', 'name': 'Blair'},
  ],
  [
    {
      'id': 'semi',
      'name': 'Semi-final',
      'round_number': 1,
      'play_by': '2026-10-01',
      'rule_overrides': <String, dynamic>{},
    },
    {
      'id': 'final',
      'name': 'Final',
      'round_number': 2,
      'play_by': null,
      'rule_overrides': <String, dynamic>{},
    },
  ],
  [
    {
      'id': 's1',
      'round_id': 'semi',
      'match_number': 1,
      'side_a_kind': 'entry',
      'side_b_kind': 'entry',
      'side_a_entry_id': 'a',
      'side_b_entry_id': 'b',
      'status': 'to_be_arranged',
    },
    {
      'id': 'f1',
      'round_id': 'final',
      'match_number': 1,
      'side_a_kind': 'winner',
      'side_b_kind': 'winner',
      'side_a_source_id': 's1',
      'side_b_source_id': 's2',
      'side_a_entry_id': resolved ? 'a' : null,
      'status': 'to_be_arranged',
    },
  ],
);

class FakeCompetitions extends CompetitionRepository {
  @override
  Future<bool> publicationEnabled(String clubId) async => communicationsEnabled;
  bool communicationsEnabled = true;
  FakeCompetitions()
    : super(
        SupabaseClient(
          'https://example.supabase.co',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final calls = <String>[];
  List<CompetitionRow> personalEntries = [];
  List<CompetitionRow> additionalCompetitions = [];
  @override
  Future<List<CompetitionRow>> myEntries(
    String memberId,
    List<String> competitionIds,
  ) async => personalEntries;
  CompetitionRow? createdSettings;
  String? savedFixtureTypeId;
  @override
  Future<List<CompetitionRow>> fixtureTypes(String clubId) async => [
    {'id': 'type', 'name': 'Club Competition'},
  ];
  @override
  Future<void> update(
    String id,
    String name,
    String season,
    CompetitionRow settings, {
    String? fixtureTypeId,
  }) async {
    savedFixtureTypeId = fixtureTypeId;
    createdSettings = settings;
  }

  bool draft = false, discarded = false;
  String? savedDeadline;
  CompetitionRow? savedOverrides;
  @override
  Future<void> updateRound(
    String id,
    String? deadline,
    CompetitionRow overrides,
  ) async {
    savedDeadline = deadline;
    savedOverrides = overrides;
  }

  @override
  Future<void> discardDraftDraw(String id) async {
    discarded = true;
  }

  @override
  Future<List<CompetitionRow>> list(String clubId) async {
    calls.add('list:$clubId');
    return [sample().competition, ...additionalCompetitions];
  }

  @override
  Future<CompetitionData> load(String clubId, String id) async {
    calls.add('load:$clubId:$id');
    final d = sample(published: !draft);
    return discarded ? CompetitionData(d.competition, d.entries, [], []) : d;
  }

  @override
  Future<String> create(
    String clubId,
    String name,
    String season,
    CompetitionRow settings, {
    String? fixtureTypeId,
  }) async {
    savedFixtureTypeId = fixtureTypeId;
    createdSettings = settings;
    calls.add('create:$clubId:$name');
    return 'competition';
  }
}

ClubAccess access(bool admin) => ClubAccess(
  currentMemberId: 'me',
  isSuperuser: false,
  isClubAdmin: admin,
  isSelector: false,
  membershipRole: admin ? 'admin' : 'member',
  hasActiveMembership: true,
);

void main() {
  testWidgets(
    'Reconciliation mode hides publication and offers non-sending date edits',
    (tester) async {
      final repo = FakeCompetitions()..communicationsEnabled = false;
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
      expect(find.textContaining('Reconciliation mode:'), findsOneWidget);
      expect(find.text('Publication emails / status'), findsNothing);
      expect(find.text('Preview player email (test only)'), findsNothing);
      await tester.tap(find.text('Edit play-by date').first);
      await tester.pumpAndSettle();
      expect(find.text('Save date — no emails'), findsOneWidget);
    },
  );
  test('Round and match order is explicit, even for reversed input', () async {
    final d = sample();
    final reversed = CompetitionData(
      d.competition,
      d.entries,
      d.rounds.reversed.toList(),
      d.matches.reversed.toList(),
    );
    expect(reversed.orderedRounds.map((r) => r['name']), [
      'Semi-final',
      'Final',
    ]);
    expect(competitionRoundDeadline(d.rounds.first), 'Play by 1 Oct 2026');
    final pdf = await buildCompetitionDrawPdf(reversed);
    expect(ascii.decode(pdf.take(4).toList()), '%PDF');
  });
  test('Blank winner labels retain known entrants for every layout', () async {
    final d = sample(resolved: true);
    expect(
      competitionPrintedSide(d, d.matches.last, 'a', blankWinnerLabels: true),
      'Alex',
    );
    expect(
      competitionPrintedSide(d, d.matches.last, 'b', blankWinnerLabels: true),
      '',
    );
    expect(
      competitionPrintedSide(sample(), sample().matches.last, 'a'),
      startsWith('Winner of'),
    );
    for (final layout in CompetitionPrintLayout.values) {
      for (final orientation in CompetitionPrintOrientation.values) {
        final bytes = await buildCompetitionDrawPdf(
          d,
          layout: layout,
          orientation: orientation,
          blankWinnerLabels: true,
        );
        expect(bytes.length, greaterThan(1000));
        final format = competitionPageFormat(layout, orientation);
        expect(
          format.width > format.height,
          orientation == CompetitionPrintOrientation.landscape,
        );
      }
    }
  });
  testWidgets(
    'Original setup stays editable after draw with structural fields locked',
    (tester) async {
      final repo = FakeCompetitions();
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
      await tester.tap(find.text('Rules'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit competition setup'));
      await tester.pumpAndSettle();
      final format = find.widgetWithText(
        DropdownButtonFormField<String>,
        'Playing format',
      );
      expect(
        tester.widget<DropdownButtonFormField<String>>(format).onChanged,
        isNull,
      );
      final players = find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == '1',
      );
      expect(players, findsWidgets);
      final scoring = find.byWidgetPredicate(
        (w) => w is TextFormField && w.controller?.text == '21 shots',
      );
      await tester.scrollUntilVisible(
        scoring,
        300,
        scrollable: find
            .descendant(
              of: find.byType(CompetitionSetupScreen),
              matching: find.byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              ),
            )
            .first,
      );
      await tester.enterText(scoring, '18 ends');
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      final save = find.text('Save competition');
      await tester.scrollUntilVisible(
        save,
        400,
        scrollable: find
            .descendant(
              of: find.byType(CompetitionSetupScreen),
              matching: find.byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              ),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.savedFixtureTypeId, 'type');
      expect(repo.createdSettings?['scoring'], '18 ends');
      expect(repo.createdSettings?['playing_format'], 'singles');
      expect(repo.createdSettings?['players_per_entry'], 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Members see only their entered competitions', (tester) async {
    final repo = FakeCompetitions();
    repo.personalEntries = [
      {
        'competition_id': 'competition',
        'entry_id': 'entry',
        'competition_entries': {'name': 'Alex / Blair'},
      },
    ];
    repo.additionalCompetitions = [
      {...sample().competition, 'id': 'other', 'name': 'Another competition'},
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: CompetitionsScreen(
          clubId: 'club',
          clubName: 'Test Club',
          repository: repo,
          accessLoader: () async => access(false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('All competitions'), findsNothing);
    expect(find.text('Another competition'), findsNothing);
    expect(find.textContaining('Alex / Blair'), findsOneWidget);
    expect(find.text('New competition'), findsNothing);
  });
  test('Lewisham badge is restricted to Lewisham competition documents', () {
    final d = sample();
    expect(competitionUsesLewishamBadge(d), false);
    d.competition['club_id'] = '8ae87bbe-cb16-4330-a5b0-e62366479f07';
    expect(competitionUsesLewishamBadge(d), true);
    d.competition['club_id'] = 'another-club';
    expect(competitionUsesLewishamBadge(d), false);
  });
  testWidgets(
    'Ordinary member draw never exposes publishing or player-email preview',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CompetitionSeasonScreen(
            clubId: 'club',
            competitionId: 'competition',
            canManage: false,
            memberId: 'member',
            repository: FakeCompetitions(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Preview player email (test only)'), findsNothing);
      expect(find.text('Publish draw to members'), findsNothing);
      expect(find.text('Submit result for confirmation'), findsNothing);
    },
  );
  test(
    'Compact printed results retain prior scores and advanced winner names',
    () {
      final d = sample(resolved: true);
      d.matches.first['score_a'] = 21;
      d.matches.first['score_b'] = 12;
      expect(
        competitionPrintedSide(d, d.matches.first, 'a', includeScore: true),
        'Alex  (21)',
      );
      expect(
        competitionPrintedSide(d, d.matches.first, 'b', includeScore: true),
        'Blair  (12)',
      );
      expect(
        competitionPrintedSide(
          d,
          d.matches.last,
          'a',
          includeScore: true,
          blankWinnerLabels: true,
        ),
        'Alex',
      );
    },
  );
  test(
    'A3 print honours actual A4 paper and asymmetric hardware margins',
    () async {
      final actual = PdfPageFormat.a4.copyWith(
        marginLeft: 35,
        marginTop: 40,
        marginRight: 32,
        marginBottom: 38,
      );
      final data = sample();
      data.matches.add({...data.matches.first, 'id': 's2', 'match_number': 2});
      final bytes = await buildCompetitionDrawPdf(
        data,
        layout: CompetitionPrintLayout.wholeA3,
        orientation: CompetitionPrintOrientation.portrait,
        printRules: true,
        printBackground: true,
        pageFormat: actual,
      );
      await Directory('tmp/pdfs').create(recursive: true);
      await File('tmp/pdfs/a3-print-on-actual-a4.pdf').writeAsBytes(bytes);
      expect(bytes.length, greaterThan(1000));
    },
  );
  test(
    'Printed rules include competition defaults and named round rules in order',
    () {
      final d = sample();
      d.rounds.first['rule_overrides'] = {'rules': '18 ends in the semi-final'};
      d.rounds.last['rule_overrides'] = {'rules': '21 shots in the final'};
      final rules = competitionPrintRules(d);
      expect(rules, contains('Semi-final: 18 ends in the semi-final'));
      expect(rules, contains('Final: 21 shots in the final'));
      expect(rules.indexOf('Semi-final:'), lessThan(rules.indexOf('Final:')));
    },
  );
  test(
    'Export corrected Mixed Pairs samples in all three formats and both orientations',
    () async {
      final input = File('tmp/member-sync-mixed-confirmed-map.json');
      if (!input.existsSync()) return;
      final pairs = jsonDecode(await input.readAsString()) as List;
      final entries = List<CompetitionRow>.generate(
        24,
        (i) => {
          'id': 'e$i',
          'name': (pairs[i] as List)
              .map(
                (p) => p['match'] == null
                    ? 'Keith Stone'
                    : "${p['match']['first']} ${p['match']['last']}",
              )
              .join(' / '),
          'entry_order': i + 1,
        },
      );
      final rounds = List<CompetitionRow>.generate(
        5,
        (i) => {
          'id': 'r$i',
          'round_number': i + 1,
          'name': [
            'Preliminary',
            'Last 16',
            'Quarter-final',
            'Semi-final',
            'Final',
          ][i],
          'play_by': [
            '2026-12-13',
            '2027-01-22',
            '2027-02-26',
            '2027-03-21',
            null,
          ][i],
          'rule_overrides': i == 4
              ? {'rules': '3/4 April 2027'}
              : <String, dynamic>{},
        },
      );
      final positions = <String?>[
        ...entries.take(16).map((e) => e['id'] as String),
        for (final e in entries.skip(16)) ...[e['id'] as String, null],
      ];
      final matches = <CompetitionRow>[];
      var previous = <CompetitionRow>[];
      for (var r = 0; r < 5; r++) {
        final current = <CompetitionRow>[];
        for (var j = 0; j < (16 >> r); j++) {
          final a = r == 0
              ? positions[j * 2]
              : previous[j * 2]['winner_entry_id'];
          final b = r == 0
              ? positions[j * 2 + 1]
              : previous[j * 2 + 1]['winner_entry_id'];
          final bye = r == 0 && (a == null || b == null);
          current.add({
            'id': 'r$r-m$j',
            'round_id': 'r$r',
            'match_number': j + 1,
            'side_a_kind': r == 0 ? 'entry' : 'winner',
            'side_b_kind': r == 0 ? (b == null ? 'bye' : 'entry') : 'winner',
            'side_a_entry_id': a,
            'side_b_entry_id': b,
            'side_a_source_id': r == 0 ? null : previous[j * 2]['id'],
            'side_b_source_id': r == 0 ? null : previous[j * 2 + 1]['id'],
            'status': bye ? 'bye' : 'to_be_arranged',
            'winner_entry_id': bye ? a ?? b : null,
          });
        }
        matches.addAll(current);
        previous = current;
      }
      final d = CompetitionData(
        {
          'name': 'Mixed Pairs',
          'club_id': '8ae87bbe-cb16-4330-a5b0-e62366479f07',
          'season': '2026–2027',
          'settings': {
            'rules':
                '18 ends or 2.5 hours. Last jack must be cast before 2h20 including trial ends. Games must be timed. No dead ends; re-spotted jacks.',
          },
        },
        entries,
        rounds,
        matches,
      );
      await Directory('tmp/pdfs').create(recursive: true);
      for (final layout in CompetitionPrintLayout.values) {
        for (final orientation in CompetitionPrintOrientation.values) {
          final bytes = await buildCompetitionDrawPdf(
            d,
            layout: layout,
            orientation: orientation,
            blankWinnerLabels: true,
            printBackground: true,
            printRules: true,
          );
          await File(
            'tmp/pdfs/Mixed-Pairs-round-rules-${layout.name}-${orientation.name}.pdf',
          ).writeAsBytes(bytes);
          if (layout != CompetitionPrintLayout.readableA4) {
            expect(competitionBracketSheets(d, layout).length, 1);
          }
        }
      }
    },
  );
  test(
    'Generate real championship PDF for order/layout verification when snapshot exists',
    () async {
      final input = File('tmp/member-sync-championship-draw-after.raw');
      if (!input.existsSync()) return;
      final text = await input.readAsString();
      final snapshot = jsonDecode(
        text.substring(text.indexOf('{'), text.lastIndexOf('}') + 1),
      )['rows'][0]['snapshot'];
      final data = CompetitionData(
        {'name': "Men's Singles Championship", 'season': '2026–2027'},
        List<CompetitionRow>.from(snapshot['entries']),
        List<CompetitionRow>.from(snapshot['rounds']),
        List<CompetitionRow>.from(snapshot['matches']),
      );
      final pdf = await buildCompetitionDrawPdf(data);
      expect(
        competitionBracketSheets(
          data,
          CompetitionPrintLayout.readableA4,
        ).length,
        5,
      );
      expect(
        competitionBracketSheets(data, CompetitionPrintLayout.wholeA3).length,
        1,
      );
      await Directory('tmp/pdfs').create(recursive: true);
      await File('tmp/pdfs/championship-order-check.pdf').writeAsBytes(pdf);
      final a3 = await buildCompetitionDrawPdf(
        data,
        layout: CompetitionPrintLayout.wholeA3,
      );
      await File('tmp/pdfs/championship-a3-check.pdf').writeAsBytes(a3);
      if (const bool.fromEnvironment('EXPORT_COMPETITION_SAMPLES')) {
        await Directory('output/pdf').create(recursive: true);
        await File(
          'output/pdf/Mens-Singles-Championship-A4-Bracket.pdf',
        ).writeAsBytes(pdf);
        await File(
          'output/pdf/Mens-Singles-Championship-A3-Bracket.pdf',
        ).writeAsBytes(a3);
      }
    },
  );
  testWidgets('Print action offers readable sections and a whole-draw sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CompetitionSeasonScreen(
          clubId: 'club',
          competitionId: 'competition',
          canManage: true,
          repository: FakeCompetitions(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Print competition bracket'));
    await tester.pumpAndSettle();
    expect(find.text('Compact A4 — single sheet'), findsOneWidget);
    expect(find.text('Leave winner labels blank'), findsOneWidget);
    expect(find.text('Print background'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    final rulesSwitch = find.widgetWithText(
      SwitchListTile,
      'Print competition rules',
    );
    expect(tester.widget<SwitchListTile>(rulesSwitch).value, false);
    await tester.tap(rulesSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(rulesSwitch).value, true);
    final backgroundSwitch = find.widgetWithText(
      SwitchListTile,
      'Print background',
    );
    expect(tester.widget<SwitchListTile>(backgroundSwitch).value, false);
    await tester.tap(backgroundSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(backgroundSwitch).value, true);
    expect(find.text('Landscape'), findsOneWidget);
    await tester.tap(find.text('Compact A4 — single sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Readable A4 — sections').last, findsOneWidget);
    expect(find.text('Whole draw on A3').last, findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Published round exposes date-only edit and notification action',
    (tester) async {
      final repo = FakeCompetitions();
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
      await tester.tap(find.text('Edit play-by date').first);
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      expect(
        find.textContaining('unfinished match(es) affected'),
        findsOneWidget,
      );
      await tester.tap(find.text('Clear deadline'));
      await tester.tap(find.text('Save and notify affected players'));
      await tester.pumpAndSettle();
      expect(repo.savedDeadline, isNull);
      expect(repo.savedOverrides, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Round date can be maintained through its draft round control', (
    tester,
  ) async {
    final repo = FakeCompetitions()..draft = true;
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
    await tester.tap(find.text('Draw'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit round rules').first);
    await tester.pumpAndSettle();
    expect(find.text('Thu 1 Oct 2026'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField),
      'Final: 21 shots, no time limit.',
    );
    await tester.tap(find.text('Save round'));
    await tester.pumpAndSettle();
    expect(repo.savedDeadline, '2026-10-01');
    expect(repo.savedOverrides?['rules'], 'Final: 21 shots, no time limit.');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Discard unused draft draw keeps entries and enables adding players',
    (tester) async {
      final repo = FakeCompetitions()..draft = true;
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
      await tester.tap(find.text('Draw'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard draft draw'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Entries, Paid settings and handicaps are kept.'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Discard draw'));
      await tester.pumpAndSettle();
      expect(repo.discarded, isTrue);
      await tester.tap(find.text('Entries'));
      await tester.pumpAndSettle();
      expect(find.text('Add players'), findsOneWidget);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Blair'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'Unresolved winner differs from a bye; resolved winner retains identity',
    () {
      final d = sample();
      expect(d.side(d.matches.last, 'a'), 'Winner of Semi-final 1');
      expect(d.side({'side_b_kind': 'bye'}, 'b'), 'Bye');
      final resolved = sample(resolved: true);
      expect(resolved.side(resolved.matches.last, 'a'), 'Alex');
    },
  );
  test('Overdue is a flag; end dates never mark matches completed', () {
    final d = sample();
    expect(
      d.status(d.matches.first, now: DateTime(2026, 10, 2)),
      'To be arranged · Overdue',
    );
    expect(
      d.status({
        ...d.matches.first,
        'status': 'result_pending',
      }, now: DateTime(2026, 10, 2)),
      'Result pending confirmation · Overdue',
    );
    expect(
      d.status({
        ...d.matches.first,
        'status': 'completed',
      }, now: DateTime(2026, 10, 2)),
      'Completed',
    );
  });
  for (final admin in [false, true]) {
    testWidgets('Member competition navigation, admin=$admin', (tester) async {
      final repo = FakeCompetitions()
        ..personalEntries = [
          {'competition_id': 'competition', 'entry_id': 'a'},
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: CompetitionsScreen(
            clubId: 'club',
            clubName: 'Our Club',
            repository: repo,
            accessLoader: () async => access(admin),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Club Singles'), findsOneWidget);
      expect(
        find.text('New competition'),
        admin ? findsOneWidget : findsNothing,
      );
      await tester.tap(find.text('Club Singles'));
      await tester.pumpAndSettle();
      expect(
        DefaultTabController.of(tester.element(find.byType(TabBar))).index,
        1,
      );
      await tester.tap(find.text('Draw'));
      await tester.pumpAndSettle();
      expect(find.text('Alex\nv Blair'), findsOneWidget);
      expect(repo.calls, contains('load:club:competition'));
      await tester.tap(find.text('Alex\nv Blair'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Submit result for confirmation'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Submit result for confirmation'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Winner advances to Final 1.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Winner advances to Final 1.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Small-phone rules and draw pages scroll without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: CompetitionSeasonScreen(
          clubId: 'club',
          competitionId: 'competition',
          canManage: true,
          repository: FakeCompetitions(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Setup separates explicit no limit from unknown and booking duration',
    (tester) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeCompetitions();
      await tester.pumpWidget(
        MaterialApp(
          home: CompetitionSetupScreen(clubId: 'club', repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> fill(String label, String value) async {
        final field = find.widgetWithText(TextFormField, label);
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
      }

      await tester.tap(find.text('Fixture Type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Club Competition').last);
      await tester.pumpAndSettle();
      await fill('Competition name', 'Men’s Singles');
      await fill('Winning condition / scoring (e.g. first to 21)', '21 shots');
      await tester.ensureVisible(find.text('Not yet confirmed'));
      await tester.tap(find.text('Not yet confirmed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No playing time limit').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Create draft competition'));
      await tester.tap(find.text('Create draft competition'));
      await tester.pumpAndSettle();
      expect(repo.savedFixtureTypeId, 'type');
      expect(repo.createdSettings?['time_limit_mode'], 'none');
      expect(repo.createdSettings?['booking_minutes'], 150);
      expect(repo.createdSettings?['woods_per_player'], isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
