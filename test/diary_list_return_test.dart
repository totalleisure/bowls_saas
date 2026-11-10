import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bowls_saas/features/diary/diary_list_screen.dart';
import 'package:bowls_saas/features/diary/diary_list_repository.dart';
import 'package:bowls_saas/features/diary/diary_involvement.dart';
import 'diary_list_test.dart' as fixtures;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final outcome in [
    'unchanged',
    'changed',
    'deleted',
    'moved',
    'failed',
  ]) {
    testWidgets(
      'return from details keeps scroll and refreshes one fixture: $outcome',
      (t) async {
        t.view.physicalSize = const Size(1100, 1100);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        var bulkLoads = 0;
        String? opened;
        final lookups = <String>[];
        final badgeLookups = <String>[];
        final pending = Completer<Map<String, dynamic>?>();
        final rows = List.generate(
          35,
          (i) => fixtures.event(
            '$i',
            '2026-09-30T${(10 + i ~/ 60).toString().padLeft(2, '0')}:${(i % 60).toString().padLeft(2, '0')}:00Z',
          ),
        );
        await t.pumpWidget(
          MaterialApp(
            home: DiaryListScreen(
              clubId: 'club',
              clubName: 'Test Club',
              initialDate: DateTime(2026, 9, 30),
              userId: 'user',
              now: () => DateTime(2026, 9, 30),
              entriesLoader: (a, b) async {
                bulkLoads++;
                return rows;
              },
              typesLoader: () async => [],
              teamsLoader: () async => [],
              fixtureLoader: (id) {
                lookups.add(id);
                return pending.future;
              },
              fixtureInvolvementLoader: (id) async {
                badgeLookups.add(id);
                return DiaryInvolvement(
                  memberId: 'member',
                  selectionBadges: {
                    id: ['Awaiting your acceptance'],
                  },
                );
              },
              fixturePageBuilder: (id) {
                opened = id;
                return Scaffold(
                  appBar: AppBar(title: const Text('Fixture Details')),
                  body: const Text('Details page'),
                );
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        final controller = t
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .controller!;
        controller.jumpTo(650);
        await t.pumpAndSettle();
        final before = controller.offset;
        final visible = find.byType(DiaryEntryCard).hitTestable();
        final untouched = t.widget<DiaryEntryCard>(visible.at(1)).entry;
        await t.tap(visible.first);
        await t.pumpAndSettle();
        expect(opened, isNotNull);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(bulkLoads, 1);
        expect(lookups, [opened]);
        expect(controller.offset, closeTo(before, 0.1));
        expect(find.byType(LinearProgressIndicator), findsNothing);
        final original = rows.firstWhere((r) => r['id'] == opened);
        if (outcome == 'failed') {
          pending.completeError(StateError('offline'));
        } else if (outcome == 'deleted') {
          pending.complete(null);
        } else {
          pending.complete({
            ...original,
            if (outcome == 'changed') 'team_name': 'Updated fixture',
            if (outcome == 'changed') 'cancelled_at': '2026-09-30T09:00:00Z',
            if (outcome == 'moved') 'start_at': '2027-01-01T10:00:00Z',
          });
        }
        await t.pumpAndSettle();
        expect(bulkLoads, 1);
        expect(controller.offset, closeTo(before, 0.1));
        expect(
          t.widget<CustomScrollView>(find.byType(CustomScrollView)).controller,
          same(controller),
        );
        final cards = t.widgetList<DiaryEntryCard>(find.byType(DiaryEntryCard));
        expect(
          cards.firstWhere((c) => c.entry['id'] == untouched['id']).entry,
          same(untouched),
        );
        if (outcome == 'deleted' || outcome == 'moved') {
          expect(find.byKey(ValueKey('fixture:$opened')), findsNothing);
        } else if (outcome == 'failed') {
          expect(
            find.textContaining('Your list position has been kept'),
            findsOneWidget,
          );
          expect(badgeLookups, isEmpty);
        } else {
          final card = t.widget<DiaryEntryCard>(
            find.byKey(ValueKey('fixture:$opened')),
          );
          expect(
            card.entry['team_name'],
            outcome == 'changed' ? 'Updated fixture' : original['team_name'],
          );
          expect(badgeLookups, [opened]);
          if (outcome == 'unchanged') {
            expect(card.entry['_involvement'], ['Awaiting your acceptance']);
          }
        }
        expect(t.takeException(), isNull);
      },
    );
  }
  test(
    'single-fixture repository queries retain Club and member scope',
    () async {
      final requests = <Uri>[];
      final client = SupabaseClient(
        'https://example.invalid',
        'test',
        httpClient: MockClient((r) async {
          requests.add(r.url);
          if (r.url.path.endsWith('/fixtures')) {
            return http.Response(
              jsonEncode(fixtures.event('fixture', '2026-09-30T10:00:00Z')),
              200,
              request: r,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '[]',
            200,
            request: r,
            headers: {
              'content-type': 'application/json',
              'content-range': '0-0/0',
            },
          );
        }),
      );
      await DiaryListRepository(client, 'club').loadFixture('fixture');
      await DiaryInvolvementRepository(
        client,
        'club',
        memberIdLoader: () async => 'member',
      ).loadFixture('fixture');
      expect(requests[0].queryParameters['club_id'], 'eq.club');
      expect(requests[0].queryParameters['id'], 'eq.fixture');
      expect(requests[1].queryParameters['member_profile_id'], 'eq.member');
      expect(
        requests[1].queryParameters['team_selections.fixture.club_id'],
        'eq.club',
      );
      expect(
        requests[1].queryParameters['team_selections.fixture.id'],
        'eq.fixture',
      );
      await client.dispose();
    },
  );
}
