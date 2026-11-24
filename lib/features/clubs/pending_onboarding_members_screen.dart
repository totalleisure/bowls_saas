import 'club_online_scaffold.dart';
import '../members/inactive_member_invitations_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'onboarding_member_recognition.dart';

class PendingOnboardingMembersScreen extends StatefulWidget {
  const PendingOnboardingMembersScreen({super.key, required this.clubId});
  final String clubId;
  @override
  State<PendingOnboardingMembersScreen> createState() =>
      _PendingOnboardingMembersScreenState();
}

class _PendingOnboardingMembersScreenState
    extends State<PendingOnboardingMembersScreen> {
  late Future<Map<String, dynamic>> _review = _load();
  bool _linking = false;
  String? _message;
  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from(
    await Supabase.instance.client.rpc(
          'review_staging_onboarding_members',
          params: {'p_club': widget.clubId},
        )
        as Map,
  );
  Future<void> _recognise() async {
    setState(() {
      _linking = true;
      _message = null;
    });
    try {
      final count = await Supabase.instance.client.rpc(
        'recognise_staging_onboarding_members',
        params: {'p_club': widget.clubId},
      );
      if (!mounted) return;
      setState(() {
        _message =
            '$count existing members recognised. Their memberships here are inactive. No invitations were sent.';
        _review = _load();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Members could not be linked. No partial changes were saved. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _linking = false);
    }
  }

  @override
  Widget build(BuildContext context) => ClubOnlineScaffold(
    appBar: AppBar(title: const Text('Onboarding members')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _review,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(() => _review = _load()),
              child: const Text('Unable to check members. Tap to retry.'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data!;
        final secretary = data['secretary'] as Map?;
        final rows = (data['rows'] as List).cast<Map>();
        final matches = {
          for (final m in (data['matches'] as List).cast<Map>())
            m['pending_id']: Map<String, dynamic>.from(m),
        };
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Only the Secretary is active after setup. Existing people are linked as inactive members of this club, using their existing profiles. Their memberships in other clubs stay unchanged. Invitations are a separate step.',
            ),
            if (secretary != null)
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_outlined),
                title: Text('${secretary['name']}'),
                subtitle: Text(
                  'Secretary · Administrator · ${secretary['active'] == true ? 'Active' : 'Inactive'}\nAlready belongs to: ${recognisedClubs(secretary['clubs'] as List?)}',
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _linking ? null : _recognise,
              child: Text(
                _linking
                    ? 'Recognising members…'
                    : 'Recognise existing members',
              ),
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_message!),
              ),
            OutlinedButton.icon(
              icon: const Icon(Icons.mail_outline),
              label: const Text('Invite inactive members'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      InactiveMemberInvitationsScreen(clubId: widget.clubId),
                ),
              ),
            ),
            const Text(
              'Use Invite inactive members to review current invitation and sending status.',
            ),
            Text('${rows.length} imported contacts'),
            for (final row in rows)
              ListTile(
                leading: Icon(
                  matches[row['pending_id']]?['attached'] == true
                      ? Icons.link
                      : Icons.person_search_outlined,
                ),
                title: Text('${row['first_name']} ${row['last_name']}'),
                subtitle: Text(
                  '${row['email'] ?? 'No email recorded'}\n'
                  '${matches[row['pending_id']]?['attached'] == true ? (matches[row['pending_id']]?['active_here'] == true ? 'Linked · Active' : 'Linked · Inactive') : 'Not yet linked'}\n'
                  '${recognitionNote(matches[row['pending_id']] ?? {})}',
                ),
              ),
          ],
        );
      },
    ),
  );
}
