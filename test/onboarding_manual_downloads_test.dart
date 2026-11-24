import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/clubs/onboarding_manual_downloads.dart';

void main() {
  testWidgets('both guides save distinct bundled PDF documents', (t) async {
    final saved = <String>[];
    await t.pumpWidget(MaterialApp(home: Scaffold(body: OnboardingManualDownloads(
      savePdf: (name, bytes) async {
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        expect(bytes.length, greaterThan(100000));
        saved.add(name);
        return true;
      },
    ))));
    await t.tap(find.text('Bringing your club online'));
    await t.pumpAndSettle();
    expect(find.textContaining('has been saved'), findsOneWidget);
    await t.tap(find.text('Your first Friendly Match'));
    await t.pumpAndSettle();
    expect(saved, ['Bringing-your-club-online.pdf', 'Your-first-Friendly-Match.pdf']);
  });
  testWidgets('cancel does not claim success and failed saves can be retried', (t) async {
    var attempts = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: OnboardingManualDownloads(
      savePdf: (name, bytes) async {
        attempts++;
        if (attempts == 2) throw StateError('save failed');
        return attempts > 2;
      },
    ))));
    await t.tap(find.text('Bringing your club online')); await t.pumpAndSettle();
    expect(find.textContaining('has been saved'), findsNothing);
    await t.tap(find.text('Bringing your club online')); await t.pumpAndSettle();
    expect(find.textContaining('could not be saved'), findsOneWidget);
    await t.tap(find.text('Bringing your club online')); await t.pumpAndSettle();
    expect(find.textContaining('has been saved'), findsOneWidget);
  });
}
