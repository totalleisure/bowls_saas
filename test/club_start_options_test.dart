import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bowls_saas/features/clubs/club_start_screen.dart';
import 'package:bowls_saas/features/clubs/club_access.dart';
import 'package:bowls_saas/features/clubs/club_dashboard_screen.dart';
import 'package:bowls_saas/features/diary/month_overview_screen.dart';
import 'package:bowls_saas/features/diary/diary_list_screen.dart';
import 'package:bowls_saas/features/communications/club_options_button.dart';
import 'package:bowls_saas/features/communications/member_options_menu.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final view in ClubMenuView.values) {
    testWidgets(
      'Menu omits the current ${view.name} view and keeps alternatives',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                appBar: AppBar(
                  actions: [
                    IconButton(
                      tooltip: 'Options',
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => showMemberOptionsMenu(
                        context: context,
                        clubId: 'club',
                        clubName: 'Club',
                        currentView: view,
                        openMembershipDetails: () async {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byTooltip('Options'));
        await tester.pumpAndSettle();
        for (final entry in {
          ClubMenuView.dashboard: 'Dashboard',
          ClubMenuView.month: 'Monthly Diary',
          ClubMenuView.list: 'Diary List',
        }.entries) {
          expect(
            find.text(entry.value),
            entry.key == view ? findsNothing : findsOneWidget,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'Complete admin menu fits a phone and Refresh Screen calls its action',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var refreshed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                actions: [
                  IconButton(
                    tooltip: 'Options',
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => showMemberOptionsMenu(
                      context: context,
                      clubId: 'club',
                      clubName: 'Club',
                      allowAdmin: true,
                      openMembershipDetails: () async {},
                      onNextMatch: () {},
                      onRefresh: () async {
                        refreshed = true;
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Options'));
      await tester.pumpAndSettle();
      final admin = find.text('Club administration');
      final welcome = find.text('Welcome · Your Club. Your Way.');
      expect(admin.hitTestable(), findsOneWidget);
      expect(welcome.hitTestable(), findsOneWidget);
      expect(tester.getBottomLeft(welcome).dy, lessThan(844));
      expect(
        tester.getTopLeft(admin).dy,
        lessThan(tester.getTopLeft(find.text('Membership Details')).dy),
      );
      expect(find.text('Options · Club'), findsNothing);
      expect(find.text('Action'), findsNothing);
      await tester.tap(find.text('Refresh Screen'));
      await tester.pumpAndSettle();
      expect(refreshed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'default and unknown values use Dashboard; choices are scoped to account and club',
    () async {
      expect(
        await ClubStartPreference.load('member', 'club'),
        ClubStartView.dashboard,
      );
      for (final view in ClubStartView.values) {
        await ClubStartPreference.save('member', 'club', view);
        expect(await ClubStartPreference.load('member', 'club'), view);
        expect(
          await ClubStartPreference.load('other', 'club'),
          ClubStartView.dashboard,
        );
        expect(
          await ClubStartPreference.load('member', 'other'),
          ClubStartView.dashboard,
        );
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        ClubStartPreference.key('member', 'club'),
        'removed-view',
      );
      expect(
        await ClubStartPreference.load('member', 'club'),
        ClubStartView.dashboard,
      );
    },
  );
  test('all starting choices construct their correct view', () {
    expect(
      clubStartPage(ClubStartView.dashboard, 'club', 'Club'),
      isA<ClubDashboardScreen>(),
    );
    expect(
      clubStartPage(ClubStartView.month, 'club', 'Club'),
      isA<MonthOverviewScreen>(),
    );
    expect(
      clubStartPage(ClubStartView.list, 'club', 'Club'),
      isA<DiaryListScreen>(),
    );
  });
  for (final view in ClubStartView.values) {
    testWidgets(
      '${view.label} is restored when re-entering the club without fixture preflight queries',
      (tester) async {
        await ClubStartPreference.save('member', 'club', view);
        Widget screen() => MaterialApp(
          home: ClubStartScreen(
            clubId: 'club',
            clubName: 'Club',
            userId: 'member',
            pageBuilder: (choice) =>
                Scaffold(body: Text('Opened ${choice.label}')),
          ),
        );
        await tester.pumpWidget(screen());
        await tester.pumpAndSettle();
        expect(find.text('Opened ${view.label}'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(screen());
        await tester.pumpAndSettle();
        expect(find.text('Opened ${view.label}'), findsOneWidget);
      },
    );
  }
  testWidgets('picker saves explicit choice and Cancel preserves it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  chooseClubStartView(context, 'club', userId: 'member'),
              child: const Text('Choose'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Monthly Diary'));
    await tester.pumpAndSettle();
    expect(
      await ClubStartPreference.load('member', 'club'),
      ClubStartView.month,
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      await ClubStartPreference.load('member', 'club'),
      ClubStartView.month,
    );
  });
  for (final role in ['guest', 'member', 'admin']) {
    testWidgets('shared Options shows only appropriate actions for $role', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ClubOptionsButton(
                  clubId: 'club',
                  clubName: 'Club',
                  accessLoader: () async => ClubAccess(
                    currentMemberId: 'member',
                    isSuperuser: false,
                    isClubAdmin: role == 'admin',
                    isSelector: false,
                    membershipRole: role,
                    hasActiveMembership: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Options'));
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Monthly Diary'), findsOneWidget);
      expect(find.text('Diary List'), findsOneWidget);
      expect(find.text('Starting screen'), findsOneWidget);
      expect(
        find.text('Volunteer Lists'),
        role == 'guest' ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('My Fixture Bookings and Competitions'),
        role == 'guest' ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('Club administration'),
        role == 'admin' ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('failed permission lookup does not expose Options actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [
              ClubOptionsButton(
                clubId: 'club',
                clubName: 'Club',
                accessLoader: () async => throw StateError('offline'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Options'));
    await tester.pumpAndSettle();
    expect(
      find.text('Could not load Options. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('Club administration'), findsNothing);
    expect(find.text('Starting screen'), findsNothing);
  });
}
