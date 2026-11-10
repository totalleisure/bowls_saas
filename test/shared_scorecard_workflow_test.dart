import 'competition_player_result_screen_test.dart' show ResultRepository;
import 'package:bowls_saas/features/competitions/screens/competition_season_screen.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/scorecards/local_scorecard_store.dart';
import 'package:bowls_saas/features/scorecards/scorecard.dart';
import 'package:bowls_saas/features/scorecards/scorecard_repository.dart';
import 'package:bowls_saas/features/scorecards/scorecard_screen.dart';
import 'package:bowls_saas/features/scorecards/shared_scorecard_api.dart';
import 'package:bowls_saas/features/scorecards/shared_scorecard_screen.dart';

class SharedMemoryStore extends LocalScorecardStore {
  List<dynamic> cards = [];
  @override
  Future<List<dynamic>> read() async => jsonDecode(jsonEncode(cards)) as List;
  @override
  Future<void> write(List<dynamic> value) async {
    cards = jsonDecode(jsonEncode(value)) as List;
  }
}

Scorecard sharedCard({bool finished = false}) {
  final now = DateTime.now().toUtc();
  final card = Scorecard.create()
    ..title = 'Shared match'
    ..sideA = 'Blue'
    ..sideB = 'Gold'
    ..maxEnds = 3
    ..fixtureLink = {
      'fixtureId': 'fixture',
      'fixtureRinkId': 'rink',
      'startAt': now.subtract(const Duration(hours: 1)).toIso8601String(),
      'sharedCardId': 'shared',
      'sharedWriterToken': 'private-device-token',
      'scorerUserId': 'owner',
      'competitionMatchId': 'match',
    };
  if (finished) {
    card.startMatch(now);
    card.startEnd(now);
    card.recordEnd(0, 3, 0);
    card.finish(now);
  }
  return card;
}

Map<String, dynamic> reviewState({String? side = 'b', bool marker = false}) {
  final card = sharedCard(finished: true);
  return {
    'actor': {
      'side': side,
      'marker': marker,
      'admin': false,
      'available': true,
      'canKeep': true,
      'userId': 'reviewer',
    },
    'snapshot': card.fixtureLink,
    'fingerprint': 'fingerprint',
    'shared': {
      'id': 'shared',
      'ownerName': 'Marker',
      'isOwner': false,
      'document': SharedScorecardApi.uploadDocument(card),
      'version': 7,
      'sequence': 3,
      'phase': 'review',
      'totalA': 3,
      'totalB': 0,
      'agreedA': true,
      'agreedB': false,
      'updatedAt': '2026-11-05T12:00:00Z',
      'sourceChanged': false,
    },
  };
}

void main() {
  testWidgets('Confirmed card opens its competition draw', (t) async {
    final state = reviewState();
    (state['actor'] as Map)['admin'] = true;
    final cloud = state['shared'] as Map;
    cloud['competitionStatus'] = 'completed';
    cloud['agreedB'] = true;
    final link = (cloud['document'] as Map)['fixtureLink'] as Map;
    link['clubId'] = 'club';
    link['competitionId'] = 'c';
    await t.pumpWidget(
      MaterialApp(
        home: SharedScorecardScreen(
          fixtureId: 'fixture',
          rinkId: 'rink',
          competitionRepository: ResultRepository(),
          repository: ScorecardRepository(store: SharedMemoryStore()),
          api: SharedScorecardApi(request: (_, _) async => state),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Status: Admin confirmed'), findsOneWidget);
    expect(find.text('Status: Submitted for Admin confirmation'), findsNothing);
    expect(find.text('Winner: Blue'), findsOneWidget);
    await t.tap(find.text('View competition draw'));
    await t.pumpAndSettle();
    final destination = t.widget<CompetitionSeasonScreen>(
      find.byType(CompetitionSeasonScreen),
    );
    expect(destination.clubId, 'club');
    expect(destination.competitionId, 'c');
    expect(
      t
          .widget<DefaultTabController>(find.byType(DefaultTabController))
          .initialIndex,
      1,
    );
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Scorer caches confirmation and stays locked after offline restart',
    (t) async {
      final repo = ScorecardRepository(store: SharedMemoryStore());
      final card = sharedCard(finished: true);
      await repo.save(card);
      final stale = Scorecard.fromJson(
        jsonDecode(jsonEncode(card.toJson())) as Map<String, dynamic>,
      );
      final state = reviewState();
      (state['shared'] as Map)['competitionStatus'] = 'completed';
      (state['shared'] as Map)['phase'] = 'submitted';
      final document = SharedScorecardApi.uploadDocument(card);
      (state['shared'] as Map)['document'] = document;
      await t.pumpWidget(
        MaterialApp(
          home: ScorecardScreen(
            card: card,
            repository: repo,
            sharedApi: SharedScorecardApi(
              request: (name, _) async {
                if (name == 'sync_shared_scorecard') {
                  throw StateError('Submitted scorecard is locked');
                }
                return state;
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Reopen to correct'), findsNothing);
      expect(find.text('Admin confirmed · Scorecard locked'), findsWidgets);
      expect(find.text('Submitted for Admin confirmation'), findsNothing);
      expect(find.text('Winner: Blue'), findsOneWidget);
      final saved = (await repo.load()).single;
      expect(saved.resultConfirmed, isTrue);
      expect(saved.saveVersion, stale.saveVersion);
      expect(saved.ends, stale.ends);
      expect(() => saved.reopen(), throwsStateError);
      await expectLater(repo.save(stale), throwsStateError);
      expect(
        SharedScorecardApi.uploadDocument(saved)['fixtureLink'],
        isNot(contains('sharedConfirmed')),
      );
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(
        MaterialApp(
          home: ScorecardScreen(
            card: saved,
            repository: repo,
            sharedApi: SharedScorecardApi(
              request: (_, _) async => throw StateError('Offline'),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining('Reopen to correct'), findsNothing);
      expect(find.text('Winner: Blue'), findsOneWidget);
      expect(find.text('Admin confirmed · Scorecard locked'), findsWidgets);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final online in [false, true]) {
    testWidgets(
      'Requested correction enters editing directly and needs online unlock: $online',
      (t) async {
        t.view.physicalSize = const Size(1100, 1500);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final repo = ScorecardRepository(store: SharedMemoryStore());
        final card = sharedCard(finished: true);
        card.fixtureLink!.remove('competitionMatchId');
        await repo.save(card);
        final state = reviewState();
        (state['actor'] as Map)['userId'] = 'owner';
        final cloud = Map<String, dynamic>.from(state['shared'] as Map);
        state['shared'] = cloud;
        cloud['document'] = SharedScorecardApi.uploadDocument(card);
        cloud['isOwner'] = true;
        cloud['phase'] = 'correction_requested';
        cloud['correctionNote'] = 'End 1 should be 4–0.';
        final api = SharedScorecardApi(
          request: (name, params) async {
            if (name == 'reopen_shared_scorecard') {
              if (!online) throw StateError('Offline');
              cloud['phase'] = 'playing';
              cloud['correctionNote'] = null;
              cloud['agreedA'] = false;
              cloud['agreedB'] = false;
              (cloud['document'] as Map)['finishedAt'] = null;
            }
            if (name == 'sync_shared_scorecard') {
              cloud['document'] = params['p_document'];
              cloud['phase'] =
                  (params['p_document'] as Map)['finishedAt'] == null
                  ? 'playing'
                  : 'review';
              cloud['totalA'] = ((params['p_document'] as Map)['ends'] as List)
                  .fold<int>(0, (sum, e) => sum + (e['a'] as int? ?? 0));
            }
            return state;
          },
        );
        await t.pumpWidget(
          MaterialApp(
            home: SharedScorecardScreen(
              fixtureId: 'fixture',
              rinkId: 'rink',
              repository: repo,
              api: api,
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(
          find.widgetWithText(FilledButton, 'Review correction request'),
        );
        await t.pumpAndSettle();
        expect(
          find.textContaining('No score changes automatically'),
          findsOneWidget,
        );
        await t.tap(find.widgetWithText(FilledButton, 'Edit requested scores'));
        await t.pumpAndSettle();
        if (!online) {
          expect((await repo.load()).single.complete, isTrue);
          expect(find.byType(ScorecardScreen), findsNothing);
          expect(
            find.textContaining('Could not start the correction'),
            findsOneWidget,
          );
        } else {
          expect(find.byType(ScorecardScreen), findsOneWidget);
          expect(find.text('Editing requested correction'), findsOneWidget);
          expect(find.textContaining('Reopen to correct'), findsNothing);
          expect((await repo.load()).single.totalA, 3);
          expect((await repo.load()).single.complete, isFalse);
          await t.ensureVisible(find.text('1').last);
          await t.tap(find.text('1').last);
          await t.pumpAndSettle();
          await t.tap(find.byIcon(Icons.add_circle_outline).first);
          await t.pumpAndSettle();
          await t.tap(find.text('Save correction'));
          await t.pumpAndSettle();
          expect((await repo.load()).single.totalA, 4);
          await t.tap(find.text('Finish corrected score'));
          await t.pumpAndSettle();
          expect(
            find.textContaining('Admin confirmation is still required'),
            findsNothing,
          );
          await t.tap(find.text('Send corrected score for agreement'));
          await t.pumpAndSettle();
          expect((await repo.load()).single.complete, isTrue);
          expect(
            (await repo.load()).single.fixtureLink!['sharedCorrectionRequest'],
            isNull,
          );
          expect(cloud['phase'], 'review');
          expect(cloud['agreedA'], false);
          expect(cloud['agreedB'], false);
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  test(
    'Writer credential stays local and pending claim cannot start offline',
    () {
      final card = sharedCard();
      final upload = SharedScorecardApi.uploadDocument(card);
      expect(
        (upload['fixtureLink'] as Map).containsKey('sharedWriterToken'),
        isFalse,
      );
      expect(card.fixtureLink!['sharedWriterToken'], 'private-device-token');
      card.fixtureLink!['sharedPendingClaim'] = true;
      expect(() => card.startMatch(DateTime.now().toUtc()), throwsStateError);
    },
  );

  testWidgets('Shared scorer fits a narrow phone with full partnership names', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 740);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repository = ScorecardRepository(store: SharedMemoryStore());
    final card = sharedCard()
      ..sideA = 'Dave Hever / Wayne Telius (Test)'
      ..sideB = 'Wayne iCloud (Test) / Ajay Cambridge';
    await repository.save(card);
    final api = SharedScorecardApi(
      request: (_, _) async => throw StateError('Offline'),
    );
    await t.pumpWidget(
      MaterialApp(
        home: ScorecardScreen(
          card: card,
          repository: repository,
          sharedApi: api,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Start match timer'));
    await t.pumpAndSettle();
    await t.tap(find.text('Jack delivered / Start end 1'));
    await t.pumpAndSettle();
    expect(find.text('Accept end 1').hitTestable(), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Shared scorer saves ends despite offline upload failures', (
    t,
  ) async {
    final repository = ScorecardRepository(store: SharedMemoryStore());
    final card = sharedCard();
    await repository.save(card);
    var uploads = 0;
    final api = SharedScorecardApi(
      request: (name, params) async {
        expect(name, 'sync_shared_scorecard');
        expect(params['p_writer_token'], 'private-device-token');
        expect(
          (params['p_document'] as Map)['fixtureLink'].containsKey(
            'sharedWriterToken',
          ),
          isFalse,
        );
        uploads++;
        throw StateError('Offline');
      },
    );
    await t.pumpWidget(
      MaterialApp(
        home: ScorecardScreen(
          card: card,
          repository: repository,
          sharedApi: api,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Start match timer'));
    await t.pumpAndSettle();
    await t.tap(find.text('Jack delivered / Start end 1'));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Add shot for Blue'));
    await t.pump();
    await t.tap(find.text('Accept end 1'));
    await t.pumpAndSettle();
    final saved = (await repository.load()).single;
    expect(saved.totalA, 1);
    expect(saved.ends.length, 2);
    expect(saved.fixtureLink!['sharedWriterToken'], 'private-device-token');
    expect(find.text('Saved on this device — waiting to sync'), findsOneWidget);
    expect(uploads, greaterThan(0));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Opponent reviews read-only, agrees own side then submits exact version',
    (t) async {
      var state = reviewState();
      final calls = <String>[];
      final api = SharedScorecardApi(
        request: (name, params) async {
          calls.add(name);
          if (name == 'agree_shared_scorecard') {
            expect(params['p_version'], 7);
            expect(params.containsKey('side'), isFalse);
            (state['shared'] as Map)['agreedB'] = true;
          }
          if (name == 'submit_shared_scorecard') {
            expect(params['p_version'], 7);
            expect(params.containsKey('scoreA'), isFalse);
            (state['shared'] as Map)['phase'] = 'submitted';
          }
          return jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
        },
      );
      await t.pumpWidget(
        MaterialApp(
          home: SharedScorecardScreen(
            fixtureId: 'fixture',
            rinkId: 'rink',
            api: api,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Start match timer'), findsNothing);
      expect(find.text('Keep the match scorecard'), findsNothing);
      final submit = find.widgetWithText(FilledButton, 'Submit agreed result');
      expect(submit, findsNothing);
      final agree = find.text('Review and agree scores');
      await t.ensureVisible(agree);
      await t.tap(agree);
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(submit).onPressed, isNotNull);
      expect(find.text('Review and agree scores'), findsNothing);
      await t.ensureVisible(submit);
      await t.tap(submit);
      await t.pumpAndSettle();
      expect(
        calls,
        containsAllInOrder([
          'shared_scorecard_state',
          'agree_shared_scorecard',
          'submit_shared_scorecard',
        ]),
      );
      expect(
        find.text('Submitted for Admin confirmation'),
        findsNothing,
      ); // Status includes prefix.
      await t.drag(find.byType(ListView), const Offset(0, 1800));
      await t.pumpAndSettle();
      expect(find.textContaining('Status: Submitted'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final both in [false, true]) {
    testWidgets('Compact footer reflects existing agreement, both=$both', (
      t,
    ) async {
      t.view.physicalSize = const Size(360, 740);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final state = reviewState();
      (state['shared'] as Map)['agreedB'] = true;
      (state['shared'] as Map)['agreedA'] = both;
      final api = SharedScorecardApi(request: (_, _) async => state);
      await t.pumpWidget(
        MaterialApp(
          home: SharedScorecardScreen(
            fixtureId: 'fixture',
            rinkId: 'rink',
            api: api,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Review and agree scores'), findsNothing);
      expect(find.textContaining('Agree final scores for'), findsNothing);
      final button = find.widgetWithText(
        FilledButton,
        both ? 'Submit agreed result' : 'Waiting for opponent’s agreement',
      );
      expect(button.hitTestable(), findsOneWidget);
      expect(
        t.widget<FilledButton>(button).onPressed,
        both ? isNotNull : isNull,
      );
      expect(
        t.getSize(find.byKey(const ValueKey('shared-next-action'))).height,
        lessThanOrEqualTo(92),
      );
      await t.drag(find.byType(ListView), const Offset(0, -600));
      await t.pumpAndSettle();
      expect(button.hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'Finish match automatically opens agreement without a sync choice',
    (t) async {
      final repository = ScorecardRepository(store: SharedMemoryStore());
      final card = sharedCard();
      final now = DateTime.now().toUtc();
      card.startMatch(now);
      card.startEnd(now);
      card.recordEnd(0, 4, 0);
      await repository.save(card);
      final state = reviewState();
      (state['actor'] as Map)['side'] = 'a';
      (state['shared'] as Map)['agreedA'] = false;
      (state['shared'] as Map)['phase'] = 'playing';
      final api = SharedScorecardApi(
        request: (name, params) async {
          if (name == 'sync_shared_scorecard') {
            final document = params['p_document'] as Map;
            (state['shared'] as Map)['document'] = document;
            (state['shared'] as Map)['phase'] = document['finishedAt'] == null
                ? 'playing'
                : 'review';
          }
          return jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
        },
      );
      await t.pumpWidget(
        MaterialApp(
          home: ScorecardScreen(
            card: card,
            repository: repository,
            sharedApi: api,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Sync and review agreement'), findsNothing);
      await t.tap(find.widgetWithText(FilledButton, 'Finish match'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Confirm final score'));
      await t.pumpAndSettle();
      expect((await repository.load()).single.complete, isTrue);
      expect(find.text('Shared match scorecard'), findsOneWidget);
      expect(
        find.text('Review and agree scores').hitTestable(),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Interrupted claim response recovers the saved device token', (
    t,
  ) async {
    t.view.physicalSize = const Size(1100, 1400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final repository = ScorecardRepository(store: SharedMemoryStore());
    final snapshot = {
      'fixtureId': 'fixture',
      'clubId': 'club',
      'fixtureRinkId': 'rink',
      'startAt': DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
      'endAt': DateTime.now()
          .toUtc()
          .add(const Duration(hours: 2))
          .toIso8601String(),
      'title': 'Shared test',
      'format': 'pairs',
      'playersPerSide': 2,
      'players': [
        {'position': 1, 'name': 'Player A'},
        {'position': 2, 'name': 'Skip A'},
        {'position': 101, 'name': 'Player B'},
        {'position': 102, 'name': 'Skip B'},
        {'position': 201, 'name': 'Marker'},
      ],
      'rules': <String, dynamic>{},
    };
    final state = <String, dynamic>{
      'actor': {
        'side': 'a',
        'canKeep': true,
        'available': true,
        'userId': 'owner',
      },
      'snapshot': snapshot,
      'fingerprint': 'fingerprint',
      'shared': null,
    };
    String? token;
    var claims = 0;
    final api = SharedScorecardApi(
      request: (name, params) async {
        if (name == 'claim_shared_scorecard') {
          claims++;
          final pending = (await repository.load()).single;
          expect(pending.fixtureLink!['sharedPendingClaim'], isTrue);
          expect(
            pending.fixtureLink!['sharedWriterToken'],
            params['p_writer_token'],
          );
          token ??= params['p_writer_token'] as String;
          expect(params['p_writer_token'], token);
          final document = Map<String, dynamic>.from(
            params['p_document'] as Map,
          );
          document['fixtureLink'] = snapshot;
          state['shared'] = {
            'id': 'shared',
            'document': document,
            'isOwner': true,
            'ownerName': 'Scorer',
            'phase': 'playing',
            'version': 1,
            'sequence': 0,
            'totalA': 0,
            'totalB': 0,
            'agreedA': false,
            'agreedB': false,
            'updatedAt': 'now',
          };
          if (claims == 1) throw StateError('Response lost after server claim');
        }
        return jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
      },
    );
    await t.pumpWidget(
      MaterialApp(
        home: SharedScorecardScreen(
          fixtureId: 'fixture',
          rinkId: 'rink',
          api: api,
          repository: repository,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Keep the match scorecard'));
    await t.pumpAndSettle();
    final save = find.text('Save scorecard');
    await t.ensureVisible(save);
    await t.tap(save);
    await t.pumpAndSettle();
    expect(claims, 1);
    await t.tap(find.byTooltip('Refresh shared card'));
    await t.pumpAndSettle();
    final resume = find.text('Continue scoring');
    await t.ensureVisible(resume);
    await t.tap(resume);
    await t.pumpAndSettle();
    expect(claims, 2);
    final card = (await repository.load()).single;
    expect(card.fixtureLink!['sharedCardId'], 'shared');
    expect(card.fixtureLink!['sharedWriterToken'], token);
    expect(card.fixtureLink!['sharedPendingClaim'], isNull);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Admin can return a pending result without editing its scores', (
    t,
  ) async {
    final state = reviewState(side: null);
    (state['actor'] as Map)['admin'] = true;
    (state['shared'] as Map).addAll(<String, Object>{
      'phase': 'submitted',
      'competitionStatus': 'result_pending',
    });
    var returned = false;
    final api = SharedScorecardApi(
      request: (name, params) async {
        if (name == 'return_shared_scorecard_for_correction') {
          expect(params['p_version'], 7);
          expect(params['p_note'], 'Check end 1');
          returned = true;
          (state['shared'] as Map).addAll(<String, Object>{
            'phase': 'correction_requested',
            'agreedA': false,
            'agreedB': false,
            'correctionNote': 'Admin: Check end 1',
          });
        }
        return jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
      },
    );
    await t.pumpWidget(
      MaterialApp(
        home: SharedScorecardScreen(
          fixtureId: 'fixture',
          rinkId: 'rink',
          api: api,
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('More match actions'));
    await t.pumpAndSettle();
    final button = find.text('Return to scorer for correction');
    await t.tap(button);
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'Check end 1');
    await t.tap(find.text('Send request'));
    await t.pumpAndSettle();
    expect(returned, isTrue);
    expect(find.text('Return to scorer for correction'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Marker reviewer cannot agree or submit for a playing side', (
    t,
  ) async {
    final api = SharedScorecardApi(
      request: (_, _) async => reviewState(side: null, marker: true),
    );
    await t.pumpWidget(
      MaterialApp(
        home: SharedScorecardScreen(
          fixtureId: 'fixture',
          rinkId: 'rink',
          api: api,
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Review and agree scores'), findsNothing);
    expect(find.text('Submit agreed result'), findsNothing);
    expect(find.text('Continue scoring'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Offline reopen cannot invalidate only local state while agreements survive',
    (t) async {
      t.view.physicalSize = const Size(1100, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final repository = ScorecardRepository(store: SharedMemoryStore());
      final card = sharedCard(finished: true);
      await repository.save(card);
      final api = SharedScorecardApi(
        request: (_, _) async => throw StateError('Offline'),
      );
      await t.pumpWidget(
        MaterialApp(
          home: ScorecardScreen(
            card: card,
            repository: repository,
            sharedApi: api,
          ),
        ),
      );
      await t.pumpAndSettle();
      final reopen = find.text('Reopen to correct scores (clears agreements)');
      await t.ensureVisible(reopen);
      await t.tap(reopen);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Reopen'));
      await t.pumpAndSettle();
      expect((await repository.load()).single.complete, isTrue);
      expect(find.textContaining('Not saved:'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );
}
