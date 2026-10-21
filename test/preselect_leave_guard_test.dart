import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/fixtures/widgets/preselect_leave_guard.dart';

void main() {
  Future<void> open(WidgetTester t, {bool dirty=true, bool saving=false}) async {
    await t.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(
      body: TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
        builder: (_) => PreselectLeaveGuard(hasChanges: dirty, saving: saving,
          child: const Scaffold(appBar: null, body: Text('Editor'))))),
        child: const Text('Open'))))));
    await t.tap(find.text('Open')); await t.pumpAndSettle();
  }
  testWidgets('back offers keep editing and explicit discard', (t) async {
    await open(t);
    await t.binding.handlePopRoute(); await t.pumpAndSettle();
    expect(find.text('Discard selection changes?'), findsOneWidget);
    await t.tap(find.text('Keep editing')); await t.pumpAndSettle();
    expect(find.text('Editor'), findsOneWidget);
    await t.binding.handlePopRoute(); await t.pumpAndSettle();
    await t.tap(find.text('Discard changes')); await t.pumpAndSettle();
    expect(find.text('Editor'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });
  testWidgets('clean selection leaves without warning', (t) async {
    await open(t,dirty:false);
    await t.binding.handlePopRoute(); await t.pumpAndSettle();
    expect(find.text('Editor'),findsNothing);
    expect(find.text('Discard selection changes?'),findsNothing);
  });
  testWidgets('cannot leave while saving', (t) async {
    await open(t,saving:true);
    await t.binding.handlePopRoute(); await t.pumpAndSettle();
    expect(find.text('Editor'),findsOneWidget);
    expect(find.text('Discard selection changes?'),findsNothing);
  });
}
