import 'package:flutter/material.dart';
import '../clubs/club_access.dart';
import '../members/members_screen.dart';
import 'member_options_menu.dart';

/// Permissions are loaded when opening Options, so the diary itself does not
/// wait for unrelated member/admin checks.
class ClubOptionsButton extends StatefulWidget {
  final String clubId;
  final String clubName;
  final Future<ClubAccess> Function()? accessLoader;
  const ClubOptionsButton({
    super.key,
    required this.clubId,
    required this.clubName,
    this.accessLoader,
  });
  @override
  State<ClubOptionsButton> createState() => _ClubOptionsButtonState();
}

class _ClubOptionsButtonState extends State<ClubOptionsButton> {
  bool _loading = false;
  Future<void> _open() async {
    setState(() => _loading = true);
    try {
      final access =
          await (widget.accessLoader?.call() ??
              loadClubAccess(clubId: widget.clubId));
      if (!mounted) return;
      setState(() => _loading = false);
      await showMemberOptionsMenu(
        context: context,
        clubId: widget.clubId,
        clubName: widget.clubName,
        allowVolunteerLists: access.canWrite,
        allowAdmin: access.canWrite && access.canAdminManageFixtures,
        showAdminGuide: access.isClubAdmin,
        openMembershipDetails: () async {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => MembersScreen(clubId: widget.clubId),
            ),
          );
        },
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load Options. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Options',
    onPressed: _loading ? null : _open,
    icon: _loading
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.more_vert),
  );
}
