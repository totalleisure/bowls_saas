import 'auth_navigation_test.dart' as nav;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Windows retains restored and idle sessions without Hello prompts', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final h = nav.Harness()..current = nav.session();
    addTearDown(h.changes.close);
    final calls = <MethodCall>[];
    const channel = MethodChannel('bowls/saved_login');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return false;
    });
    addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await t.pumpWidget(h.build());
    await t.pumpAndSettle();
    expect(find.text('Member home'), findsOneWidget);
    await t.tap(find.text('Open fixture'));
    await t.pumpAndSettle();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await t.pump(const Duration(minutes: 6));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(find.text('Private fixture'), findsOneWidget);
    expect(calls, isEmpty);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
