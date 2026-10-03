import 'package:flutter/material.dart';
import '../auth/account_security_screen.dart';
import '../clubs/club_start_screen.dart';
import '../clubs/club_home_screen.dart';
import '../fixtures/fixtures_screen.dart';
import '../help/player_help_screen.dart';
import '../notifications/notifications_page.dart';
import 'member_mailing_lists_screen.dart';

enum MemberOptionsAction {
  dashboard,
  month,
  list,
  startingScreen,
  membershipDetails,
  accountSecurity,
  volunteerLists,
  bookings,
  notifications,
  guide,
  admin,
}

Future<void> showMemberOptionsMenu({
  required BuildContext context,
  required String clubId,
  required String clubName,
  required Future<void> Function() openMembershipDetails,
  bool allowVolunteerLists = true,
  bool allowAdmin = false,
  bool showAdminGuide = false,
}) async {
  final action = await showModalBottomSheet<MemberOptionsAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final dark = theme.brightness == Brightness.dark;
      MaterialColor palette(MemberOptionsAction action) => switch (action) {
        MemberOptionsAction.dashboard => Colors.indigo,
        MemberOptionsAction.month => Colors.teal,
        MemberOptionsAction.list => Colors.blue,
        MemberOptionsAction.startingScreen => Colors.deepPurple,
        MemberOptionsAction.membershipDetails => Colors.cyan,
        MemberOptionsAction.accountSecurity => Colors.blueGrey,
        MemberOptionsAction.volunteerLists => Colors.green,
        MemberOptionsAction.bookings => Colors.teal,
        MemberOptionsAction.notifications => Colors.orange,
        MemberOptionsAction.guide => Colors.purple,
        MemberOptionsAction.admin => Colors.deepOrange,
      };
      Widget item(
        MemberOptionsAction action,
        IconData icon,
        String title, [
        String? subtitle,
      ]) {
        final colour = palette(action);
        final accent = dark ? colour.shade200 : colour.shade800;
        final background = Color.alphaBlend(
          colour.withValues(alpha: dark ? .12 : .055),
          theme.colorScheme.surface,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 2,
              ),
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: dark ? .22 : .13),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 23),
              ),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: subtitle == null ? null : Text(subtitle),
              trailing: Icon(Icons.chevron_right, color: accent, size: 20),
              onTap: () => Navigator.of(sheetContext).pop(action),
            ),
          ),
        );
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .8,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    Icon(
                      Icons.tune,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Options · $clubName',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              item(
                MemberOptionsAction.dashboard,
                Icons.dashboard_outlined,
                'Dashboard',
              ),
              item(
                MemberOptionsAction.month,
                Icons.calendar_month,
                'Monthly Diary',
              ),
              item(
                MemberOptionsAction.list,
                Icons.view_agenda_outlined,
                'Diary List',
              ),
              item(
                MemberOptionsAction.startingScreen,
                Icons.home_outlined,
                'Starting screen',
                'Choose which view opens when you enter this club',
              ),
              const Divider(height: 12, indent: 16, endIndent: 16),
              item(
                MemberOptionsAction.membershipDetails,
                Icons.badge_outlined,
                'Membership Details',
                'View and update your personal membership information',
              ),
              item(
                MemberOptionsAction.accountSecurity,
                Icons.security_outlined,
                'Account and Security',
                'Change your login email or request a password reset',
              ),
              if (allowVolunteerLists)
                item(
                  MemberOptionsAction.volunteerLists,
                  Icons.groups_outlined,
                  'Volunteer Lists',
                  'Join or leave club mailing and volunteer lists',
                ),
              if (allowVolunteerLists)
                item(
                  MemberOptionsAction.bookings,
                  Icons.event_available,
                  'My fixture bookings',
                ),
              item(
                MemberOptionsAction.notifications,
                Icons.notifications_outlined,
                'Notifications',
              ),
              item(MemberOptionsAction.guide, Icons.help_outline, 'User Guide'),
              if (allowAdmin)
                item(
                  MemberOptionsAction.admin,
                  Icons.settings,
                  'Club administration',
                ),
            ],
          ),
        ),
      );
    },
  );
  if (!context.mounted || action == null) return;
  if (action == MemberOptionsAction.startingScreen) {
    await chooseClubStartView(context, clubId);
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
