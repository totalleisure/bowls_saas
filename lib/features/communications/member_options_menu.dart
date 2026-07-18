import 'package:flutter/material.dart';

import '../auth/account_security_screen.dart';
import 'member_mailing_lists_screen.dart';

enum MemberOptionsAction {
  membershipDetails,
  accountSecurity,
  volunteerLists,
}

Future<void> showMemberOptionsMenu({
  required BuildContext context,
  required String clubId,
  required String clubName,
  required Future<void> Function() openMembershipDetails,
}) async {
  final action = await showModalBottomSheet<MemberOptionsAction>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Membership Details'),
              subtitle: const Text(
                'View and update your personal membership information',
              ),
              onTap: () => Navigator.of(sheetContext).pop(
                MemberOptionsAction.membershipDetails,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.security_outlined),
              title: const Text('Account and Security'),
              subtitle: const Text(
                'Change your login email or request a password reset',
              ),
              onTap: () => Navigator.of(sheetContext).pop(
                MemberOptionsAction.accountSecurity,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Volunteer Lists'),
              subtitle: const Text(
                'Join or leave club mailing and volunteer lists',
              ),
              onTap: () => Navigator.of(sheetContext).pop(
                MemberOptionsAction.volunteerLists,
              ),
            ),
          ],
        ),
      );
    },
  );

  if (!context.mounted || action == null) return;

  switch (action) {
    case MemberOptionsAction.membershipDetails:
      await openMembershipDetails();
      break;
    case MemberOptionsAction.accountSecurity:
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AccountSecurityScreen()),
      );
      break;
    case MemberOptionsAction.volunteerLists:
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MemberMailingListsScreen(
            clubId: clubId,
            clubName: clubName,
          ),
        ),
      );
      break;
  }
}
