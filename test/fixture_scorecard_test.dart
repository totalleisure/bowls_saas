import 'package:bowls_saas/features/scorecards/fixture_scorecard_preview.dart';
import 'package:bowls_saas/features/scorecards/scorecard_match_summary.dart';
import 'package:bowls_saas/features/scorecards/scorecard_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/scorecards/scorecard.dart';
import 'package:bowls_saas/features/scorecards/scorecard_screen.dart';
import 'package:bowls_saas/features/scorecards/fixture_scorecard_template.dart';
import 'package:bowls_saas/features/scorecards/fixture_scorecard_screen.dart';
import 'package:bowls_saas/features/scorecards/scorecard_repository.dart';
import 'scorecard_recovery_test.dart' show RecoveryMemoryStore;
import 'package:bowls_saas/features/scorecards/scorecard_recovery_host.dart';

Map<String, dynamic> snapshot(int ppr) => {
  'fixtureId': 'fixture',
  'fixtureRinkId': 'rink',
  'startAt': '2026-11-03T10:00:00Z',
  'endAt': '2026-11-03T13:00:00Z',
  'title': 'Club competition',
  'playersPerSide': ppr,
  'players': [
    {'position': 100 + ppr, 'name': 'Away Skip'},
    if (ppr > 1) {'position': 1, 'name': 'Home Lead'},
    {'position': ppr, 'name': 'Home Skip'},
    if (ppr > 1) {'position': 101, 'name': 'Away Lead'},
    {'position': 201, 'name': 'Marker'},
  ],
  'rules': <String, dynamic>{
    'scoring': '18 ends',
    'time_limit_mode': 'minutes',
    'time_limit_minutes': 150,
    'last_jack_before_end_minutes': 10,
    'rules': 'Last jack must be cast before 2hr20mins.',
  },
  'handicapA': -2,
};
void main() {
  test(
    'Singles and pairs use actual playing positions and skips, not database order',
    () {
      final singles = scorecardFromFixture(snapshot(1));
      expect(singles.sideA, 'Home Skip');
      expect(singles.sideB, 'Away Skip');
      expect(singles.suggestedSignerA, 'Home Skip');
      expect(singles.suggestedSignerB, 'Away Skip');
      final pairs = scorecardFromFixture(snapshot(2));
      expect(pairs.sideA, 'Home Lead / Home Skip');
      expect(pairs.sideB, 'Away Lead / Away Skip');
      expect(pairs.suggestedSignerA, 'Home Skip');
      expect(pairs.suggestedSignerB, 'Away Skip');
      expect(pairs.marker, 'Marker');
      expect(pairs.durationMinutes, 150);
      expect(pairs.lastJackMinutes, 140);
      expect(pairs.maxEnds, 18);
      expect(pairs.handicapA, -2);
      final restored = Scorecard.fromJson(pairs.toJson());
      expect(restored.suggestedSignerA, 'Home Skip');
      expect(restored.fixtureLink?['fixtureId'], 'fixture');
    },
  );
  test(
    'Ordinary booking duration does not become match timer; multi-rink handicap requires review',
    () {
      final data = snapshot(2)..['rules'] = {};
      final c = scorecardFromFixture(data, applyEntryHandicap: false);
      expect(c.durationMinutes, isNull);
      expect(c.lastJackMinutes, isNull);
      expect(c.handicapA, 0);
    },
  );
  test(
    'Shared conditions copy rules without copying identity, timer, scores or signatures',
    () {
      final first = scorecardFromFixture(snapshot(2))
        ..woods = 2
        ..maxEnds = 21;
      first.startMatch(DateTime.now().toUtc());
      first.startEnd(DateTime.now().toUtc());
      first.recordEnd(0, 3, 0);
      final other = scorecardFromFixture(
        snapshot(2),
        conditions: fixtureScorecardConditions(first),
      );
      expect(other.id, isNot(first.id));
      expect(other.maxEnds, 21);
      expect(other.woods, 2);
      expect(other.ends, isEmpty);
      expect(other.startedAt, isNull);
      expect(other.signatureA, isNull);
      expect(other.suggestedSignerB, 'Away Skip');
    },
  );
  test(
    'Last jack uses explicit allowance, adjusts with limit, and ignores rule prose',
    () {
      final data = snapshot(2);
      final rules = data['rules'] as Map<String, dynamic>;
      rules['rules'] = 'Last jack before 2h20m';
      expect(scorecardFromFixture(data).lastJackMinutes, 140);
      rules['time_limit_minutes'] = 180;
      expect(scorecardFromFixture(data).lastJackMinutes, 170);
      rules['last_jack_before_end_minutes'] = null;
      expect(scorecardFromFixture(data).lastJackMinutes, isNull);
      rules['last_jack_before_end_minutes'] = 10;
      rules['time_limit_mode'] = 'none';
      expect(scorecardFromFixture(data).lastJackMinutes, isNull);
      rules['time_limit_mode'] = 'minutes';
      rules['last_jack_before_end_minutes'] = 180;
      expect(() => scorecardFromFixture(data), throwsFormatException);
    },
  );
  for (final started in [false, true]) {
    testWidgets('Existing card timing update, started=$started', (t) async {
      final repository = ScorecardRepository(store: RecoveryMemoryStore());
      final data = snapshot(2)..['competitionId'] = 'competition';
      final card = scorecardFromFixture(data)..lastJackMinutes = null;
      card.fixtureLink!['scorerUserId'] = 'scorer';
      if (started) card.startMatch(DateTime.now().toUtc());
      await repository.save(card);
      Future<Map<String, dynamic>> request(
        String name,
        Map<String, dynamic> params,
      ) async => {
        'actorUserId': 'scorer',
        'rinks': [
          {
            'fixtureRinkId': 'rink',
            'canScore': true,
            'snapshot': data,
            'setup': null,
          },
        ],
      };
      await t.pumpWidget(
        MaterialApp(
          home: FixtureScorecardScreen(
            fixtureId: 'fixture',
            request: request,
            repository: repository,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Open my scorecard'));
      await t.pumpAndSettle();
      if (!started) {
        expect(find.text('Update competition timing?'), findsOneWidget);
        await t.tap(find.text('Update timing'));
        await t.pumpAndSettle();
      } else {
        expect(find.text('Update competition timing?'), findsNothing);
      }
      final saved = (await repository.load()).single;
      expect(saved.id, card.id);
      expect(saved.lastJackMinutes, started ? null : 140);
      expect(saved.startedAt, card.startedAt);
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'New scorer gets current competition timing from an older shared setup',
    (t) async {
      final repository = ScorecardRepository(store: RecoveryMemoryStore());
      final current = snapshot(2)..['competitionId'] = 'competition';
      final old = snapshot(2);
      (old['rules'] as Map).remove('last_jack_before_end_minutes');
      Future<Map<String, dynamic>> request(
        String name,
        Map<String, dynamic> params,
      ) async => {
        'actorUserId': 'scorer',
        'rinks': [
          {
            'fixtureRinkId': 'rink',
            'canScore': true,
            'snapshot': current,
            'setup': {
              'id': 'setup',
              'matchId': 'match',
              'snapshot': old,
              'conditions': {
                'woods': 4,
                'durationMinutes': 150,
                'scoring': 'shots',
              },
            },
          },
        ],
      };
      await t.pumpWidget(
        MaterialApp(
          home: FixtureScorecardScreen(
            fixtureId: 'fixture',
            request: request,
            repository: repository,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Open my scorecard'));
      await t.pumpAndSettle();
      expect((await repository.load()).single.lastJackMinutes, 140);
      await t.pumpWidget(const SizedBox());
    },
  );
  test(
    'Imported rules appear once and custom notes survive, including on existing signed cards',
    () {
      final data = snapshot(2)
        ..addAll({
          'competitionName': 'Mens Pairs',
          'roundName': 'Preliminary',
          'playBy': '2026-11-29',
        });
      final rules = data['rules'] as Map<String, dynamic>;
      rules['scoring'] = 'Best of 18 ends or 2.5hrs';
      rules['rules'] =
          'Scoring: 18 ends or 2.5 hours. Re-spotted jacks, no dead ends';
      data['notes'] =
          'Mens Pairs - Preliminary 9\nPlay by: 2026-11-29\nScoring: ${rules['scoring']}\n${rules['rules']}\nBring the agreed measuring equipment';
      final card = scorecardFromFixture(data);
      // Reproduce the older saved card with both source blocks concatenated.
      card.notes =
          'Mens Pairs · Preliminary · Play by 2026-11-29\nScoring: ${rules['scoring']}\n${rules['rules']}\n${data['notes']}';
      final before = card.toJson().toString();
      final cleaned = card.displayNotes;
      expect('Best of 18 ends'.allMatches(cleaned).length, 1);
      expect('Re-spotted jacks'.allMatches(cleaned).length, 1);
      expect('Play by:'.allMatches(cleaned).length, 1);
      expect(cleaned, contains('Mens Pairs - Preliminary 9'));
      expect(cleaned, contains('Winning condition:'));
      expect(cleaned, contains('Rules: 18 ends'));
      expect(cleaned, contains('Bring the agreed measuring equipment'));
      card.fixtureLink!['competitionId'] = 'competition';
      expect(card.playerNotes, isNot(contains('Winning condition:')));
      expect(card.playerNotes, isNot(contains('Rules:')));
      expect(
        card.playerNotes,
        contains('Bring the agreed measuring equipment'),
      );
      expect(card.playingSummary, contains('Maximum 18 ends'));
      expect(card.playingSummary, contains('Match limit: 2 hr 30 min'));
      expect(
        card.playingSummary,
        contains('Last jack by 2 hr 20 min from start'),
      );
      card.fixtureLink!.remove('competitionId');
      expect(card.toJson().toString(), before);
      expect(
        (Scorecard.fromJson(card.toJson())..notes = cleaned).displayNotes,
        cleaned,
      );
      final manual = Scorecard.create()..notes = 'Personal note\nPersonal note';
      expect(manual.displayNotes, manual.notes);
    },
  );
  testWidgets(
    'Summary labels roles and ordinal dates and fits a narrow phone',
    (t) async {
      t.view.physicalSize = const Size(320, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final data = snapshot(2)
        ..addAll({
          'competitionName': 'Mens Pairs',
          'roundName': 'Preliminary',
          'playBy': '2026-11-29',
          'venue': 'Lewisham and Crystal Palace Indoor Bowling Club',
          'green': 'Main Indoor Green',
          'rink': 'R4',
          'notes': 'Mens Pairs - Preliminary 9',
        });
      final card = scorecardFromFixture(data);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScorecardMatchSummary(card: card),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Play by : 29th Nov 2026'), findsOneWidget);
      expect(
        find.textContaining('Preliminary-9', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Skip : Home Skip', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Skip : Away Skip', findRichText: true),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'Linked edit hides fixed fields and preserves them when editable settings are saved',
    (t) async {
      final card = scorecardFromFixture(snapshot(2));
      Scorecard? saved;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  saved = await Navigator.push<Scorecard>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ScorecardSetup(card: card),
                    ),
                  );
                },
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Edit'));
      await t.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Match / competition name'),
        findsNothing,
      );
      expect(find.widgetWithText(TextFormField, 'Side A name'), findsNothing);
      expect(
        find.widgetWithText(DropdownButtonFormField<String>, 'Format'),
        findsNothing,
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Woods per player'),
        '2',
      );
      await t.scrollUntilVisible(
        find.text('Save scorecard'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ScorecardSetup),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.ensureVisible(find.text('Save scorecard'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save scorecard'));
      await t.pumpAndSettle();
      expect(saved?.woods, 2);
      expect(saved?.title, card.title);
      expect(saved?.sideA, card.sideA);
      expect(saved?.playersB, card.playersB);
      expect(saved?.suggestedSignerA, card.suggestedSignerA);
    },
  );
  test(
    'Fixture scoring opens on the Club date, including British Summer Time',
    () {
      final data = snapshot(2)..['startAt'] = '2026-11-30T10:00:00Z';
      expect(
        fixtureScoringDayReached(
          data,
          nowUtc: DateTime.utc(2026, 11, 29, 23, 59),
        ),
        false,
      );
      expect(
        fixtureScoringDayReached(data, nowUtc: DateTime.utc(2026, 11, 30)),
        true,
      );
      expect(
        fixtureScoringDayReached(data, nowUtc: DateTime.utc(2026, 12, 1)),
        true,
      );
      final c = scorecardFromFixture(data);
      expect(() => c.startMatch(DateTime.utc(2026, 11, 29)), throwsStateError);
      expect(c.startedAt, isNull);
      c.startMatch(DateTime.utc(2026, 11, 30));
      expect(c.startedAt, isNotNull);
      data['startAt'] = '2027-07-02T09:00:00Z';
      expect(
        fixtureScoringDayReached(data, nowUtc: DateTime.utc(2027, 7, 1, 23, 1)),
        true,
      );
    },
  );
  testWidgets(
    'Future fixture opens a shaded preview without creating or saving any scorecard',
    (t) async {
      final store = RecoveryMemoryStore();
      final repository = ScorecardRepository(store: store);
      var prepareCalls = 0;
      final current = snapshot(2)..['startAt'] = '2026-11-30T10:00:00Z';
      Future<Map<String, dynamic>> request(
        String name,
        Map<String, dynamic> params,
      ) async {
        if (name != 'fixture_scorecard_context') {
          prepareCalls++;
          throw StateError('Preview must not save a shared setup');
        }
        return {
          'actorUserId': 'scorer',
          'rinks': [
            {
              'fixtureRinkId': 'rink',
              'canScore': true,
              'snapshot': current,
              'setup': {
                'snapshot': snapshot(2),
                'conditions': {'woods': 4},
              },
            },
          ],
        };
      }

      await t.pumpWidget(
        MaterialApp(
          home: FixtureScorecardScreen(
            fixtureId: 'fixture',
            request: request,
            repository: repository,
            clock: () => DateTime.utc(2026, 11, 4),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Preview scorecard'));
      await t.pumpAndSettle();
      expect(find.byType(FixtureScorecardPreview), findsOneWidget);
      expect(find.text('Match date : 30th Nov 2026'), findsOneWidget);
      expect(
        find.text('Scorecard available on the day of the Fixture'),
        findsOneWidget,
      );
      expect(find.text('Save scorecard'), findsNothing);
      expect(find.text('Start match timer'), findsNothing);
      expect(store.cards, isEmpty);
      expect(prepareCalls, 0);
      expect(
        t.widget<Card>(find.byType(Card).last).color,
        const Color(0xffdce8f7),
      );
    },
  );
  testWidgets(
    'Unstarted card follows the rescheduled fixture on match day while retaining its settings',
    (t) async {
      final repository = ScorecardRepository(store: RecoveryMemoryStore());
      final original = scorecardFromFixture(snapshot(2))..woods = 2;
      original.fixtureLink!['scorerUserId'] = 'scorer';
      await repository.save(original);
      final current = snapshot(2)
        ..['startAt'] = '2026-11-30T10:00:00Z'
        ..['rink'] = 'R4';
      Future<Map<String, dynamic>> request(
        String name,
        Map<String, dynamic> params,
      ) async => {
        'actorUserId': 'scorer',
        'rinks': [
          {
            'fixtureRinkId': 'rink',
            'canScore': true,
            'snapshot': current,
            'setup': null,
          },
        ],
      };
      await t.pumpWidget(
        MaterialApp(
          home: FixtureScorecardScreen(
            fixtureId: 'fixture',
            request: request,
            repository: repository,
            clock: () => DateTime.utc(2026, 11, 30),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Open my scorecard'));
      await t.pumpAndSettle();
      final saved = (await repository.load()).single;
      expect(saved.id, original.id);
      expect(saved.date, '2026-11-30');
      expect(saved.rink, 'R4');
      expect(saved.woods, 2);
      expect(saved.startedAt, isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Signature opens with the supplied player or skip name', (
    t,
  ) async {
    await t.pumpWidget(
      const MaterialApp(
        home: SignatureScreen(
          sideName: 'Home',
          score: '21 : 10',
          initialName: 'Home Skip',
        ),
      ),
    );
    expect(find.widgetWithText(TextField, 'Home Skip'), findsOneWidget);
  });
  testWidgets(
    'Later scorer reuses shared setup and resumes one own local card',
    (t) async {
      final repository = ScorecardRepository(store: RecoveryMemoryStore());
      var writes = 0;
      Future<Map<String, dynamic>> request(
        String name,
        Map<String, dynamic> params,
      ) async {
        if (name != 'fixture_scorecard_context') {
          writes++;
          throw StateError('Shared setup should not be overwritten');
        }
        return {
          'actorUserId': 'scorer',
          'rinks': [
            {
              'fixtureRinkId': 'rink',
              'canScore': true,
              'snapshot': snapshot(2),
              'setup': {
                'id': 'setup',
                'matchId': 'match',
                'snapshot': snapshot(2),
                'conditions': {'woods': 2, 'maxEnds': 21, 'scoring': 'shots'},
              },
            },
          ],
        };
      }

      await t.pumpWidget(
        MaterialApp(
          home: FixtureScorecardScreen(
            fixtureId: 'fixture',
            request: request,
            repository: repository,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Open my scorecard'));
      await t.pumpAndSettle();
      expect(find.text('Start match timer'), findsOneWidget);
      final cards = await repository.load();
      expect(cards.length, 1);
      expect(cards.single.woods, 2);
      expect(cards.single.fixtureLink?['scorerUserId'], 'scorer');
      expect(writes, 0);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.text('Open my scorecard'));
      await t.pumpAndSettle();
      expect((await repository.load()).length, 1);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'First scorer reviews conditions then opens the card outside Club authentication',
    (t) async {
      final repository = ScorecardRepository(store: RecoveryMemoryStore());
      Map<String, dynamic>? supplied;
      var prepared = 0;
      Future<Map<String, dynamic>> request(
        String name,
        Map<String, dynamic> params,
      ) async {
        if (name == 'fixture_scorecard_context')
          return {
            'actorUserId': 'scorer',
            'rinks': [
              {
                'fixtureRinkId': 'rink',
                'canScore': true,
                'snapshot': snapshot(2),
                'sourceFingerprint': 'reviewed',
                'setup': null,
              },
            ],
          };
        prepared++;
        supplied = params;
        return {
          'id': 'setup',
          'matchId': 'match',
          'snapshot': snapshot(2),
          'conditions': params['p_conditions'],
        };
      }

      await t.pumpWidget(
        ScorecardRecoveryHost(
          repository: repository,
          child: MaterialApp(
            home: FixtureScorecardScreen(
              fixtureId: 'fixture',
              request: request,
              repository: repository,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Open my scorecard'));
      await t.pumpAndSettle();
      expect(prepared, 0);
      expect(find.text('Match details'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Save scorecard'),
        400,
        scrollable: find
            .descendant(
              of: find.byType(ScorecardSetup),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.ensureVisible(find.text('Save scorecard'));
      await t.pumpAndSettle();
      await t.tap(find.text('Save scorecard'));
      await t.pumpAndSettle();
      expect(prepared, 1);
      expect(supplied?['p_source_fingerprint'], 'reviewed');
      expect(find.text('Start match timer'), findsOneWidget);
      final card = (await repository.load()).single;
      expect(card.fixtureLink?['fixtureScorecardRinkId'], 'setup');
      expect(card.suggestedSignerA, 'Home Skip');
      await t.pumpWidget(const SizedBox());
    },
  );
}
