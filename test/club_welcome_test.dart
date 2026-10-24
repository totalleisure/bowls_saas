import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bowls_saas/features/clubs/club_start_screen.dart';
import 'package:bowls_saas/features/clubs/club_welcome_screen.dart';
import 'package:bowls_saas/features/communications/member_options_menu.dart';

Widget entry({bool revisit = false}) => MaterialApp(
  home: ClubStartScreen(
    userId: 'member',
    clubId: 'club',
    clubName: 'Our Indoor Bowls Club',
    showWelcome: revisit,
    pageBuilder: (view) => Scaffold(body: Text('Opened ${view.name}')),
  ),
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'saved choice distinguishes absence, unknown, and explicit Dashboard; clearing is scoped',
    () async {
      expect(await ClubStartPreference.loadSaved('member', 'club'), isNull);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ClubStartPreference.key('member', 'club'),
        'obsolete',
      );
      expect(await ClubStartPreference.loadSaved('member', 'club'), isNull);
      await ClubStartPreference.save('member', 'club', ClubStartView.dashboard);
      expect(
        await ClubStartPreference.loadSaved('member', 'club'),
        ClubStartView.dashboard,
      );
      await ClubStartPreference.save('other', 'club', ClubStartView.list);
      await ClubStartPreference.clear('member', 'club');
      expect(await ClubStartPreference.loadSaved('member', 'club'), isNull);
      expect(
        await ClubStartPreference.loadSaved('other', 'club'),
        ClubStartView.list,
      );
    },
  );
  testWidgets(
    'welcome explains the choice and Options before any view is selected',
    (tester) async {
      await tester.pumpWidget(entry());
      await tester.pumpAndSettle();
      expect(find.text('Welcome to your Club App'), findsOneWidget);
      expect(find.textContaining('The choice is yours.'), findsOneWidget);
      expect(
        find.textContaining(
          'change your view at any stage using the Options menu',
        ),
        findsOneWidget,
      );
      for (int i = 0; i < 3; i++) {
        expect(find.byKey(ValueKey('intro-choice-$i')), findsOneWidget);
      }
      expect(
        await ClubStartPreference.loadSaved('member', 'club'),
        ClubStartView.dashboard,
      );
      final dashboard = find.byKey(const ValueKey('intro-choice-2'));
      await tester.ensureVisible(dashboard);
      await tester.tap(dashboard);
      await tester.pumpAndSettle();
      expect(find.text('Open Dashboard'), findsOneWidget);
      expect(
        await ClubStartPreference.loadSaved('member', 'club'),
        ClubStartView.dashboard,
      );
      await tester.ensureVisible(find.text('Back to welcome'));
      await tester.tap(find.text('Back to welcome'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to your Club App'), findsOneWidget);
    },
  );
  testWidgets(
    'leaving introduction without opening a view does not repeat it',
    (tester) async {
      await tester.pumpWidget(entry());
      await tester.pumpAndSettle();
      expect(find.text('Welcome to your Club App'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(entry());
      await tester.pumpAndSettle();
      expect(find.text('Opened dashboard'), findsOneWidget);
      expect(find.byType(ClubWelcomeScreen), findsNothing);
    },
  );
  testWidgets('welcome uses the active club branding and name', (tester) async {
    SharedPreferences.setMockInitialValues({
      'last_club_id': 'club',
      'last_branding_set_no': 2,
      'last_primary_colour': '#174a90',
    });
    await tester.pumpWidget(entry());
    await tester.pumpAndSettle();
    expect(find.text('Our Indoor Bowls Club'), findsOneWidget);
    expect(find.textContaining('Riverside'), findsNothing);
    final backgrounds = tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .map((d) => d.image?.image)
        .whereType<AssetImage>();
    expect(
      backgrounds.any(
        (image) =>
            image.assetName.contains('blank_bg_') &&
            image.assetName.endsWith('_2.png'),
      ),
      isTrue,
    );
    expect(
      await ClubStartPreference.loadSaved('member', 'club'),
      ClubStartView.dashboard,
    );
  });
  testWidgets(
    'header uses Club name and both emblems; photographs preserve their full proportions',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      await tester.pumpWidget(entry());
      await tester.pumpAndSettle();
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 44);
      expect(find.text('Our Indoor Bowls Club'), findsOneWidget);
      expect(find.byType(BowlMark), findsNWidgets(2));
      final photos = tester
          .widgetList<Image>(find.byType(Image))
          .where(
            (image) =>
                image.image is AssetImage &&
                (image.image as AssetImage).assetName.contains('welcome_'),
          );
      expect(photos.length, 3);
      expect(photos.every((image) => image.fit == BoxFit.contain), isTrue);
      expect(find.text('Welcome to your Club App'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'small windows provide a visible scrolling prompt that advances content',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 700));
      await tester.pumpWidget(entry());
      await tester.pumpAndSettle();
      final prompt = find.text('Scroll to see all options and buttons');
      expect(prompt, findsOneWidget);
      final before = tester
          .getTopLeft(find.byKey(const ValueKey('intro-choice-0')))
          .dy;
      await tester.tap(prompt);
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('intro-choice-0'))).dy,
        lessThan(before),
      );
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets(
    'tablet introduction puts bounded photographs beside the explanation and controls',
    (tester) async {
      for (final size in [
        const Size(768, 1024),
        const Size(1024, 768),
        const Size(1180, 820),
      ]) {
        SharedPreferences.setMockInitialValues({});
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(entry());
        await tester.pumpAndSettle();
        for (int i = 0; i < 3; i++) {
          final image = find.byKey(ValueKey('intro-image-$i'));
          final button = find.byKey(ValueKey('intro-choice-$i'));
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          final imageRect = tester.getRect(image);
          final buttonRect = tester.getRect(button);
          expect(
            imageRect.width,
            lessThanOrEqualTo(250),
            reason: '$size image $i',
          );
          expect(
            imageRect.height,
            lessThanOrEqualTo(250),
            reason: '$size image $i',
          );
          expect(
            imageRect.right,
            lessThan(buttonRect.left),
            reason: '$size image $i must be beside the text',
          );
          expect(buttonRect.bottom, lessThanOrEqualTo(size.height));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      await tester.binding.setSurfaceSize(null);
    },
  );
  for (final item in {
    'List View': ClubStartView.list,
    'Month View': ClubStartView.month,
    'Dashboard': ClubStartView.dashboard,
  }.entries) {
    testWidgets(
      'introduction is shown once; exploring ${item.key} preserves Dashboard default',
      (tester) async {
        await tester.pumpWidget(entry());
        await tester.pumpAndSettle();
        await revealDetails(tester);
        expect(find.byType(ClubWelcomeScreen), findsOneWidget);
        expect(find.text('Open List View'), findsOneWidget);
        if (item.value != ClubStartView.list) {
          await tester.ensureVisible(find.text(item.key));
          await tester.tap(find.text(item.key));
          await tester.pumpAndSettle();
          await revealDetails(tester);
        }
        await tester.ensureVisible(find.text('Open ${item.key}'));
        await tester.tap(find.text('Open ${item.key}'));
        await tester.pumpAndSettle();
        await revealDetails(tester);
        expect(find.text('Opened ${item.value.name}'), findsOneWidget);
        expect(
          await ClubStartPreference.loadSaved('member', 'club'),
          ClubStartView.dashboard,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(entry());
        await tester.pumpAndSettle();
        await revealDetails(tester);
        expect(find.text('Opened dashboard'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'explicit setting saves and re-entry bypasses introduction; revisit preserves it',
    (tester) async {
      await tester.pumpWidget(entry());
      await tester.pumpAndSettle();
      await revealDetails(tester);
      await tester.ensureVisible(find.text('Month View'));
      await tester.tap(find.text('Month View'));
      await tester.pumpAndSettle();
      await revealDetails(tester);
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await revealDetails(tester);
      expect(
        await ClubStartPreference.loadSaved('member', 'club'),
        ClubStartView.month,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(entry());
      await tester.pumpAndSettle();
      await revealDetails(tester);
      expect(find.text('Opened month'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(entry(revisit: true));
      await tester.pumpAndSettle();
      await revealDetails(tester);
      expect(find.text('Open List View'), findsOneWidget);
      expect(
        await ClubStartPreference.loadSaved('member', 'club'),
        ClubStartView.month,
      );
      await tester.ensureVisible(find.text('Month View'));
      await tester.tap(find.text('Month View'));
      await tester.pumpAndSettle();
      await revealDetails(tester);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await revealDetails(tester);
      expect(await ClubStartPreference.loadSaved('member', 'club'), isNull);
    },
  );
  testWidgets('Options opens welcome without replacing saved preference', (
    tester,
  ) async {
    await ClubStartPreference.save('member', 'club', ClubStartView.dashboard);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showMemberOptionsMenu(
                context: context,
                clubId: 'club',
                clubName: 'Club',
                userId: 'member',
                openMembershipDetails: () async {},
              ),
              child: const Text('Options'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    await revealDetails(tester);
    await tester.ensureVisible(find.text('Welcome · Your Club. Your Way.'));
    await tester.tap(find.text('Welcome · Your Club. Your Way.'));
    await tester.pumpAndSettle();
    await revealDetails(tester);
    expect(find.byType(ClubWelcomeScreen), findsOneWidget);
    expect(
      await ClubStartPreference.loadSaved('member', 'club'),
      ClubStartView.dashboard,
    );
  });
  testWidgets(
    'all panels and overview fit small phones, tablets and desktop with larger text',
    (tester) async {
      for (final width in [320.0, 375.0, 768.0, 1366.0]) {
        await tester.binding.setSurfaceSize(Size(width, 900));
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: ClubWelcomeScreen(
              userId: 'member',
              clubId: 'club',
              clubName: 'Our Indoor Bowls Club',
              onOpen: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await revealDetails(tester);
        for (final label in ['Month View', 'Dashboard', 'List View']) {
          await tester.ensureVisible(find.text(label).last);
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
          await revealDetails(tester);
          expect(find.text('Open $label'), findsOneWidget);
          expect(tester.takeException(), isNull, reason: '$width $label');
        }
        await tester.ensureVisible(find.text('Show all three views'));
        await tester.tap(find.text('Show all three views'));
        await tester.pumpAndSettle();
        await revealDetails(tester);
        expect(find.text('Explore Dashboard'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      await tester.binding.setSurfaceSize(null);
    },
  );
}

Future<void> revealDetails(WidgetTester tester) async {
  final choice = find.byKey(const ValueKey('intro-choice-0'));
  if (choice.evaluate().isNotEmpty) {
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
  }
}
