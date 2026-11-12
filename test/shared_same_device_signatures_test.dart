import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/scorecards/shared_scorecard_screen.dart';
import 'package:bowls_saas/features/scorecards/shared_scorecard_api.dart';
import 'package:bowls_saas/features/scorecards/scorecard_repository.dart';
import 'shared_scorecard_workflow_test.dart'
    show reviewState, SharedMemoryStore, sharedCard;

void main() {
  test(
    'Signature cache preserves upload sequence and skips unsynced local corrections',
    () async {
      final repo = ScorecardRepository(store: SharedMemoryStore());
      final card = sharedCard(finished: true);
      await repo.save(card);
      final doc = jsonDecode(jsonEncode(card.toJson())) as Map<String, dynamic>;
      doc['signatureA'] = {
        'name': 'Home',
        'revision': card.revision,
        'strokes': [],
      };
      doc['signatureB'] = {
        'name': 'Away',
        'revision': card.revision,
        'strokes': [],
      };
      final shared = <String, dynamic>{
        'id': 'shared',
        'signedOnOneDevice': true,
        'sequence': card.saveVersion,
        'document': doc,
      };
      await repo.rememberSignatures(shared);
      var saved = (await repo.load()).single;
      expect(saved.signatureA?['name'], 'Home');
      expect(saved.saveVersion, card.saveVersion);
      saved.reopen();
      await repo.save(saved);
      await repo.rememberSignatures(shared);
      saved = (await repo.load()).single;
      expect(saved.signatureA, isNull);
      expect(saved.signatureB, isNull);
    },
  );

  testWidgets(
    'Both signatures supplement account agreement without submitting the result',
    (t) async {
      final state = reviewState(side: 'a');
      final cloud = state['shared'] as Map;
      cloud['isOwner'] = true;
      final calls = <String>[];
      Map<String, dynamic>? submitted;
      await t.pumpWidget(
        MaterialApp(
          home: SharedScorecardScreen(
            fixtureId: 'fixture',
            rinkId: 'rink',
            repository: ScorecardRepository(store: SharedMemoryStore()),
            api: SharedScorecardApi(
              request: (name, params) async {
                calls.add(name);
                if (name == 'sign_shared_scorecard_on_device') {
                  submitted = params;
                  cloud['agreedB'] = true;
                  cloud['signedOnOneDevice'] = true;
                  cloud['version'] = 8;
                  (cloud['document'] as Map)['signatureA'] = {
                    ...params['p_signature_a'] as Map,
                    'revision': 4,
                  };
                  (cloud['document'] as Map)['signatureB'] = {
                    ...params['p_signature_b'] as Map,
                    'revision': 4,
                  };
                }
                return jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('shared-sign-on-device')));
      await t.pumpAndSettle();
      await t.tap(find.text('Continue to signatures'));
      await t.pumpAndSettle();
      for (final name in ['Home Skip', 'Away Skip']) {
        await t.enterText(find.byType(TextField), name);
        await t.drag(
          find.byKey(const ValueKey('scorecard-signature-pad')),
          const Offset(90, 25),
        );
        await t.ensureVisible(find.text('Accept and save signature'));
        await t.tap(find.text('Accept and save signature'));
        await t.pumpAndSettle();
      }
      expect(submitted?['p_version'], 7);
      expect((submitted?['p_signature_a'] as Map)['name'], 'Home Skip');
      expect((submitted?['p_signature_b'] as Map)['name'], 'Away Skip');
      expect(find.text('Submit agreed result'), findsOneWidget);
      expect(calls.where((x) => x == 'submit_shared_scorecard'), isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );

  for (final owner in [true, false]) {
    testWidgets(
      'Cancel signing does not record either agreement; owner=$owner',
      (t) async {
        final state = reviewState();
        (state['shared'] as Map)['isOwner'] = owner;
        var signingCalls = 0;
        await t.pumpWidget(
          MaterialApp(
            home: SharedScorecardScreen(
              fixtureId: 'fixture',
              rinkId: 'rink',
              repository: ScorecardRepository(store: SharedMemoryStore()),
              api: SharedScorecardApi(
                request: (name, _) async {
                  if (name == 'sign_shared_scorecard_on_device') signingCalls++;
                  return state;
                },
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Review and agree scores'), findsOneWidget);
        if (owner) {
          await t.tap(find.byKey(const ValueKey('shared-sign-on-device')));
          await t.pumpAndSettle();
          await t.tap(find.text('Cancel'));
          await t.pumpAndSettle();
        } else {
          expect(
            find.byKey(const ValueKey('shared-sign-on-device')),
            findsNothing,
          );
        }
        expect(signingCalls, 0);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
