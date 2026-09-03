import 'package:bowls_saas/features/team/selected_member_interaction_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Make reserve cannot also return the member to the pool', (
    tester,
  ) async {
    var madeReserve = 0;
    var returnedToPool = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectedMemberInteractionCard(
            color: Colors.white,
            title: const Text('Wayne Symmetry'),
            subtitle: const Text('Team 2 / Skip'),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'reserve') madeReserve++;
                if (value == 'return_to_pool') returnedToPool++;
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'reserve', child: Text('Make reserve')),
                PopupMenuItem(
                  value: 'return_to_pool',
                  child: Text('Return to pool'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(selectedMemberInteractionTileKey));
    await tester.pump();
    expect(returnedToPool, 0);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make reserve').last);
    await tester.pumpAndSettle();

    expect(madeReserve, 1);
    expect(returnedToPool, 0);
  });
}
