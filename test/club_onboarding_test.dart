import 'dart:async';
import 'package:bowls_saas/features/clubs/club_onboarding_screen.dart';
import 'package:bowls_saas/features/clubs/club_onboarding_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ClubSetupSnapshot snapshot({bool ready = true}) => ClubSetupSnapshot(
  clubName: 'Example Bowls Club',
  homeVenues: ready ? 1 : 0,
  greens: ready ? 1 : 0,
  hoursReady: ready,
  fixtureTypes: ready ? 2 : 0,
  members: 1,
  teams: 0,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'progress is isolated by account and club and corrupt data is recoverable',
    () async {
      await const ClubOnboardingProgress(step: 7).save('secretary', 'club-a');
      expect(
        (await ClubOnboardingProgress.load('secretary', 'club-a')).step,
        7,
      );
      expect((await ClubOnboardingProgress.load('other', 'club-a')).step, 0);
      expect(
        (await ClubOnboardingProgress.load('secretary', 'club-b')).step,
        0,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ClubOnboardingProgress.key('secretary', 'club-a'),
        '{bad',
      );
      expect(
        (await ClubOnboardingProgress.load('secretary', 'club-a')).step,
        0,
      );
    },
  );

  Future<void> tap(WidgetTester t, String label) async {
    final target = find.text(label);
    if (find.byType(Scrollable).evaluate().isEmpty) {
      await t.ensureVisible(target);
    } else {
      await t.scrollUntilVisible(
        target,
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await t.tap(target);
    await t.pumpAndSettle();
  }

  testWidgets(
    'all ten steps navigate, save and finish without opening tools or sending',
    (t) async {
      final saves = <ClubOnboardingProgress>[];
      var toolsOpened = 0, reads = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ClubOnboardingScreen(
                      clubId: 'club',
                      clubName: 'Example',
                      accountId: 'secretary',
                      snapshotLoader: () async {
                        reads++;
                        return snapshot();
                      },
                      progressSaver: (p) async => saves.add(p),
                      toolBuilder: (_) {
                        toolsOpened++;
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
                child: const Text('Start setup'),
              ),
            ),
          ),
        ),
      );
      await tap(t, 'Start setup');
      expect(find.text('Step 1 of 10'), findsOneWidget);
      await tap(t, 'Let’s begin');
      for (var step = 2; step <= 9; step++) {
        expect(find.text('Step $step of 10'), findsOneWidget);
        await tap(t, 'Continue');
      }
      expect(find.text('Step 10 of 10'), findsOneWidget);
      await tap(t, 'Finish setup review');
      expect(find.text('Your club setup is complete'), findsOneWidget);
      expect(find.text('Start setup'), findsNothing);
      await tap(t, 'Go to my club');
      expect(find.text('Start setup'), findsOneWidget);
      expect(saves.last.reviewed, isTrue);
      expect(
        reads,
        3,
      ); // Open, final summary, and fresh check before completion.
      expect(toolsOpened, 0);
    },
  );

  testWidgets(
    'pause and reopen resumes the saved step; Back retains progress',
    (t) async {
      Widget page() => MaterialApp(
        home: ClubOnboardingScreen(
          clubId: 'club',
          clubName: 'Example',
          accountId: 'secretary',
          snapshotLoader: () async => snapshot(),
        ),
      );
      await t.pumpWidget(page());
      await t.pumpAndSettle();
      await tap(t, 'Let’s begin');
      await tap(t, 'Continue');
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(page());
      await t.pumpAndSettle();
      expect(find.text('Step 3 of 10'), findsOneWidget);
      await tap(t, 'Back');
      expect((await ClubOnboardingProgress.load('secretary', 'club')).step, 1);
    },
  );

  testWidgets(
    'save failure stays on the current step and gives a retry explanation',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: ClubOnboardingScreen(
            clubId: 'club',
            clubName: 'Example',
            accountId: 'secretary',
            snapshotLoader: () async => snapshot(),
            progressSaver: (_) async => throw StateError('disk unavailable'),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'Let’s begin');
      expect(find.text('Step 1 of 10'), findsOneWidget);
      expect(find.textContaining('You’re still on this step'), findsOneWidget);
    },
  );

  testWidgets('missing essentials do not present an enabled finish action', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: ClubOnboardingScreen(
          clubId: 'club',
          clubName: 'Example',
          accountId: 'secretary',
          snapshotLoader: () async => snapshot(ready: false),
          progressLoader: () async => const ClubOnboardingProgress(step: 9),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Finish setup review'),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('Still to do'), findsNWidgets(4));
    expect(find.text('4 things still to do'), findsOneWidget);
    expect(find.text('Step 3: Add your home venue'), findsOneWidget);
    final leave = find.widgetWithText(OutlinedButton, 'Save and leave setup');
    expect(t.widget<OutlinedButton>(leave).onPressed, isNotNull);
    expect(t.getRect(leave).bottom, lessThanOrEqualTo(600));
    expect(find.text('Finish and leave setup'), findsNothing);
    await tap(t, 'Step 3: Add your home venue');
    expect(find.text('Step 3 of 10'), findsOneWidget);
  });

  testWidgets(
    'a revoked permission or failed read cannot complete a cached ready summary',
    (t) async {
      var reads = 0, saved = false;
      await t.pumpWidget(
        MaterialApp(
          home: ClubOnboardingScreen(
            clubId: 'club',
            clubName: 'Example',
            accountId: 'secretary',
            snapshotLoader: () async {
              if (++reads > 1) throw StateError('access removed');
              return snapshot();
            },
            progressLoader: () async => const ClubOnboardingProgress(step: 9),
            progressSaver: (_) async {
              saved = true;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'Finish setup review');
      expect(saved, isFalse);
      expect(find.textContaining('could not be saved'), findsOneWidget);
    },
  );

  testWidgets('returning from a setup tool refreshes real saved settings', (
    t,
  ) async {
    var ready = false;
    await t.pumpWidget(
      MaterialApp(
        home: ClubOnboardingScreen(
          clubId: 'club',
          clubName: 'Example',
          accountId: 'secretary',
          snapshotLoader: () async => snapshot(ready: ready),
          progressLoader: () async => const ClubOnboardingProgress(step: 2),
          toolBuilder: (tool) => Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  ready = true;
                  Navigator.of(context).pop();
                },
                child: Text('Save ${tool.name}'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await tap(t, 'Set up your home venue');
    await tap(t, 'Save venues');
    for (var i = 0; i < 7; i++) {
      await tap(t, 'Continue');
    }
    expect(find.text('Step 10 of 10'), findsOneWidget);
    expect(find.text('In place'), findsNWidgets(4));
  });

  testWidgets(
    'narrow screen and large text remain scrollable without overflow',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: ClubOnboardingScreen(
            clubId: 'club',
            clubName: 'Example',
            accountId: 'secretary',
            snapshotLoader: () async => snapshot(),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'Let’s begin');
      expect(find.text('Step 2 of 10'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
