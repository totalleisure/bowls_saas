import '../scorecards/scorecard_recovery_host.dart';
import '../scorecards/scorecard_screen.dart';
import 'package:flutter/material.dart';
import '../auth/account_security_screen.dart';
import '../clubs/club_start_screen.dart';
import '../clubs/club_home_screen.dart';
import '../fixtures/fixtures_screen.dart';
import '../fixtures/member_fixture_creation_page.dart';
import '../competitions/screens/competitions_screen.dart';
import '../help/player_help_screen.dart';
import '../notifications/notifications_page.dart';
import 'member_mailing_lists_screen.dart';

enum MemberOptionsAction {
  dashboard,
  month,
  list,
  competitions,
  scorecards,
  startingScreen,
  welcome,
  membershipDetails,
  accountSecurity,
  volunteerLists,
  bookings,
  memberFixtureBooking,
  notifications,
  guide,
  admin,
  refresh,
  nextMatch,
}

enum ClubMenuView { dashboard, month, list }

Future<void> showMemberOptionsMenu({
  required BuildContext context,
  required String clubId,
  required String clubName,
  required Future<void> Function() openMembershipDetails,
  String? userId,
  bool allowVolunteerLists = true,
  bool allowAdmin = false,
  bool showAdminGuide = false,
  Future<void> Function()? onRefresh,
  VoidCallback? onNextMatch,
  ClubMenuView? currentView,
}) async {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  MaterialColor palette(MemberOptionsAction action) => switch (action) {
    MemberOptionsAction.dashboard => Colors.indigo,
    MemberOptionsAction.month => Colors.teal,
    MemberOptionsAction.list => Colors.blue,
    MemberOptionsAction.competitions => Colors.amber,
    MemberOptionsAction.scorecards => Colors.indigo,
    MemberOptionsAction.startingScreen => Colors.deepPurple,
    MemberOptionsAction.welcome => Colors.green,
    MemberOptionsAction.membershipDetails => Colors.cyan,
    MemberOptionsAction.accountSecurity => Colors.blueGrey,
    MemberOptionsAction.volunteerLists => Colors.green,
    MemberOptionsAction.bookings => Colors.teal,
    MemberOptionsAction.memberFixtureBooking => Colors.teal,
    MemberOptionsAction.notifications => Colors.orange,
    MemberOptionsAction.guide => Colors.purple,
    MemberOptionsAction.admin => Colors.deepOrange,
    MemberOptionsAction.refresh => Colors.blueGrey,
    MemberOptionsAction.nextMatch => Colors.indigo,
  };

  PopupMenuEntry<MemberOptionsAction> item(
    MemberOptionsAction action,
    IconData icon,
    String title,
  ) {
    final colour = palette(action);
    final accent = dark ? colour.shade200 : colour.shade800;
    return PopupMenuItem<MemberOptionsAction>(
      value: action,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            colour.withValues(alpha: dark ? .12 : .055),
            theme.colorScheme.surface,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: colour.withValues(alpha: dark ? .22 : .13),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: accent, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: accent, size: 16),
          ],
        ),
      ),
    );
  }

  final size = MediaQuery.sizeOf(context);
  final width = (size.width - 16).clamp(0.0, 420.0);
  final action = await showMenu<MemberOptionsAction>(
    context: context,
    position: RelativeRect.fromLTRB(
      size.width - width - 8,
      MediaQuery.paddingOf(context).top + 56,
      8,
      0,
    ),
    constraints: BoxConstraints.tightFor(width: width),
    menuPadding: const EdgeInsets.symmetric(vertical: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    items: [
      if (currentView != ClubMenuView.month)
        item(MemberOptionsAction.month, Icons.calendar_month, 'Monthly Diary'),
      if (currentView != ClubMenuView.list)
        item(
          MemberOptionsAction.list,
          Icons.view_agenda_outlined,
          'Diary List',
        ),
      if (currentView != ClubMenuView.dashboard)
        item(
          MemberOptionsAction.dashboard,
          Icons.dashboard_outlined,
          'Dashboard',
        ),
      if (allowVolunteerLists)
        item(
          MemberOptionsAction.bookings,
          Icons.event_available,
          'My Fixture Bookings and Competitions',
        ),
      if (allowAdmin)
        item(MemberOptionsAction.admin, Icons.settings, 'Club administration'),
      if (onNextMatch != null)
        item(MemberOptionsAction.nextMatch, Icons.info_outline, 'Next match'),
      if (onRefresh != null)
        item(MemberOptionsAction.refresh, Icons.refresh, 'Refresh Screen'),
      item(
        MemberOptionsAction.competitions,
        Icons.emoji_events_outlined,
        'Competitions',
      ),
      item(
        MemberOptionsAction.membershipDetails,
        Icons.badge_outlined,
        'Membership Details',
      ),
      item(
        MemberOptionsAction.accountSecurity,
        Icons.security_outlined,
        'Account and Security',
      ),
      if (allowVolunteerLists)
        item(
          MemberOptionsAction.volunteerLists,
          Icons.groups_outlined,
          'Volunteer Lists',
        ),
      item(
        MemberOptionsAction.notifications,
        Icons.notifications_outlined,
        'Notifications',
      ),
      if (allowAdmin)
        item(
          MemberOptionsAction.memberFixtureBooking,
          Icons.add_location_alt_outlined,
          'Member Fixture booking',
        ),
      item(
        MemberOptionsAction.scorecards,
        Icons.scoreboard_outlined,
        'Electronic Scorecards (offline)',
      ),
      item(MemberOptionsAction.guide, Icons.help_outline, 'User Guide'),
      item(
        MemberOptionsAction.startingScreen,
        Icons.home_outlined,
        'Starting screen',
      ),
      item(
        MemberOptionsAction.welcome,
        Icons.waving_hand_outlined,
        'Welcome · Your Club. Your Way.',
      ),
    ],
  );
  if (!context.mounted || action == null) return;
  if (action == MemberOptionsAction.refresh) {
    await onRefresh?.call();
    return;
  }
  if (action == MemberOptionsAction.nextMatch) {
    onNextMatch?.call();
    return;
  }
  if (action == MemberOptionsAction.scorecards) {
    openOfflineScorecards(context);
    return;
  }
  if (action == MemberOptionsAction.welcome) {
    await showClubWelcome(context, clubId, clubName, userId: userId);
    return;
  }
  if (action == MemberOptionsAction.startingScreen) {
    await chooseClubStartView(context, clubId, userId: userId);
    return;
  }
  if (action == MemberOptionsAction.membershipDetails) {
    await openMembershipDetails();
    return;
  }
  final view = switch (action) {
    MemberOptionsAction.dashboard => ClubStartView.dashboard,
    MemberOptionsAction.month => ClubStartView.month,
    MemberOptionsAction.list => ClubStartView.list,
    _ => null,
  };
  if (view != null) {
    // Switching view keeps Back pointing at the club chooser rather than
    // accumulating a chain of starting pages.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => clubStartPage(view, clubId, clubName),
      ),
    );
    return;
  }
  final Widget page = switch (action) {
    MemberOptionsAction.memberFixtureBooking => MemberFixtureCreationPage(
      clubId: clubId,
      clubName: clubName,
    ),
    MemberOptionsAction.competitions => CompetitionsScreen(
      clubId: clubId,
      clubName: clubName,
    ),
    MemberOptionsAction.scorecards => const ScorecardsScreen(),
    MemberOptionsAction.accountSecurity => const AccountSecurityScreen(),
    MemberOptionsAction.volunteerLists => MemberMailingListsScreen(
      clubId: clubId,
      clubName: clubName,
    ),
    MemberOptionsAction.bookings => FixturesScreen(
      clubId: clubId,
      clubName: clubName,
      memberBookingsOnly: true,
    ),
    MemberOptionsAction.notifications => const NotificationsPage(),
    MemberOptionsAction.guide => PlayerHelpScreen(
      showAdminGuide: showAdminGuide,
    ),
    MemberOptionsAction.admin => ClubHomeScreen(
      clubId: clubId,
      clubName: clubName,
    ),
    _ => throw StateError('Unsupported option'),
  };
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => page));
}
