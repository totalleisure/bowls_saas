import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/competitions/screens/competition_season_screen.dart';
import 'competition_player_result_screen_test.dart' show ResultRepository;

void main() {
  for (final published in [false, true]) {
    testWidgets(
      'Entry tooltips keep accessibility parents, published=$published',
      (t) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final handle = t.ensureSemantics();
        try {
          final repo = ResultRepository();
          repo.data.competition['status'] = published ? 'published' : 'draft';
          if (!published) {
            repo.data.rounds.clear();
            repo.data.matches.clear();
          }
          repo.data.entries.first['handicap'] = 2;
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
          await t.tap(find.text('Entries'));
          await t.pumpAndSettle();
          final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: const Offset(2, 2));
          void checkTree() {
            final nodes = <SemanticsNode>[];
            void visit(SemanticsNode n) {
              nodes.add(n);
              for (final child in n.debugListChildrenInOrder(
                DebugSemanticsDumpOrder.inverseHitTest,
              )) {
                visit(child);
              }
            }

            visit(t.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
            final parents = nodes
                .map((n) => n.traversalParentIdentifier)
                .whereType<Object>()
                .toSet();
            final orphaned = nodes
                .where(
                  (n) =>
                      n.traversalChildIdentifier != null &&
                      !parents.contains(n.traversalChildIdentifier),
                )
                .toList();
            expect(
              orphaned,
              isEmpty,
              reason:
                  'A tooltip overlay must not lose its accessibility traversal parent inside a list entry.',
            );
          }

          for (final tooltip in [
            'Correct an unplayed entry without rebuilding its draw',
            published
                ? 'Handicaps are locked after creating the draw'
                : 'Set or clear a signed handicap',
            if (!published) 'Edit handicap',
            if (!published) 'Remove entry',
          ]) {
            final target = find.byTooltip(tooltip).first;
            await t.ensureVisible(target);
            await mouse.moveTo(t.getCenter(target));
            await t.pump(const Duration(milliseconds: 800));
            await t.pump(const Duration(milliseconds: 250));
            expect(find.text(tooltip), findsAtLeastNWidgets(1));
            checkTree();
          }
          await mouse.removePointer();
          await t.pumpAndSettle();
          checkTree();
          expect(
            t.getSemantics(find.text('Paid').first).getSemanticsData().label,
            contains('Paid'),
          );
          await t.pumpWidget(const SizedBox());
        } finally {
          handle.dispose();
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }
}
