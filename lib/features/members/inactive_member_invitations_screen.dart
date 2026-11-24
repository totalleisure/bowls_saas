import '../clubs/club_online_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef InvitationCall =
    Future<dynamic> Function(String name, Map<String, dynamic> params);

class InactiveMemberInvitationsScreen extends StatefulWidget {
  const InactiveMemberInvitationsScreen({
    super.key,
    required this.clubId,
    this.call,
  });
  final String clubId;
  final InvitationCall? call;
  @override
  State<InactiveMemberInvitationsScreen> createState() =>
      _InactiveMemberInvitationsScreenState();
}

class _InactiveMemberInvitationsScreenState
    extends State<InactiveMemberInvitationsScreen> {
  bool _busy = false;
  String? _message;
  List<Map<String, dynamic>> _rows = [];
  final _selected = <String>{};
  String _targetId(Map<String, dynamic> row) =>
      '${row['membership_id'] ?? row['contact_id']}';
  Future<dynamic> _call(String name, Map<String, dynamic> params) async {
    if (widget.call != null) return widget.call!(name, params);
    if (name == 'provision_staging_club_invitations') {
      final response = await Supabase.instance.client.functions.invoke(
        'staging-onboarding-invitations',
        body: params,
      );
      if (response.status != 200) {
        throw StateError('Invitation preparation failed');
      }
      return response.data;
    }
    return Supabase.instance.client.rpc(name, params: params);
  }

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final result = await _call('preview_staging_club_invitations', {
        'p_club': widget.clubId,
      });
      if (!mounted) return;
      setState(() {
        _rows = (result as List)
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList();
        _selected.clear();
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Invitations could not be checked. Please refresh and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => ClubOnlineDialog(
        title: Text('Send ${ids.length} club invitations?'),
        content: const Text(
          'Only the selected people will receive an invitation. New users receive initial login details; existing users keep their password. Membership stays inactive until acceptance. Other club memberships are unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send test invitations'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final contacts = _rows
          .where(
            (r) => r['contact_id'] != null && _selected.contains(_targetId(r)),
          )
          .map((r) => r['contact_id'])
          .toList();
      final memberships = _rows
          .where(
            (r) =>
                r['membership_id'] != null && _selected.contains(_targetId(r)),
          )
          .map((r) => r['membership_id'])
          .toList();
      final result = Map<String, dynamic>.from(
        await _call(
              contacts.isEmpty
                  ? 'queue_staging_club_invitations'
                  : 'provision_staging_club_invitations',
              contacts.isEmpty
                  ? {
                      'p_club': widget.clubId,
                      'p_memberships': memberships,
                      'p_confirm': true,
                    }
                  : {
                      'club_id': widget.clubId,
                      'contact_ids': contacts,
                      'membership_ids': memberships,
                      'confirm': true,
                    },
            )
            as Map,
      );
      if (!mounted) return;
      setState(
        () => _message =
            '${result['queued']} invitations queued. ${(result['errors'] as List? ?? []).length} contacts need review. Memberships remain inactive until acceptance. Refresh to check sending status.',
      );
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'The send result could not be confirmed. Refresh to check status before trying again; already prepared invitations will not be duplicated.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _status(Object? value) => switch (value) {
    'sent' => 'Email service accepted for sending; awaiting member acceptance',
    'accepted' => 'Member accepted',
    'pending' => 'Queued; membership inactive',
    'processing' => 'Sending; membership inactive',
    'ready' => 'Ready to invite; membership inactive',
    _ => '$value',
  };
  @override
  Widget build(BuildContext context) => ClubOnlineScaffold(
    appBar: AppBar(
      title: const Text('Invite inactive members'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _refresh,
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh invitations',
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Invitations are optional and separate from creating the club. Select the people you want to invite. You can return here from Membership at any time.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Recognised people from other clubs are Members using their existing account and password. New people get a sign-in account and an initial password only when invited. They can change or keep that password when signing in. Everyone stays inactive in this club until they sign in to the App and accept the invitation under My clubs. Their other clubs are unchanged.',
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(_message!),
          ),
        if (!_busy && _rows.isEmpty)
          const Text('No inactive members awaiting invitations.'),
        if (_rows.any((r) => r['eligible'] == true))
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(
                    () => _selected.addAll(
                      _rows.where((r) => r['eligible'] == true).map(_targetId),
                    ),
                  ),
            child: const Text('Select all eligible test members'),
          ),
        for (final row in _rows)
          Card(
            child: Column(
              children: [
                CheckboxListTile(
                  value: _selected.contains(_targetId(row)),
                  onChanged: _busy || row['eligible'] != true
                      ? null
                      : (yes) => setState(() {
                          if (yes == true) {
                            _selected.add(_targetId(row));
                          } else {
                            _selected.remove(_targetId(row));
                          }
                        }),
                  title: Text('${row['name']}'),
                  subtitle: Text(
                    '${row['email']}\n${row['role'] ?? 'Awaiting account'} · ${_status(row['status'])}',
                  ),
                ),
                ExpansionTile(
                  title: const Text('Preview invitation'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('${row['subject']}\n\n${row['body']}'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        FilledButton(
          onPressed: _busy || _selected.isEmpty ? null : _send,
          child: Text('Review and send ${_selected.length} test invitations'),
        ),
        const SizedBox(height: 12),
        const Text(
          'Accepted for sending means the email service accepted the request; it does not confirm inbox delivery. Failed or uncertain sends must be reviewed before any resend.',
        ),
      ],
    ),
  );
}

class StagingClubInvitations extends StatefulWidget {
  const StagingClubInvitations({
    super.key,
    required this.onAccepted,
    this.call,
  });
  final Future<void> Function(String clubId) onAccepted;
  final InvitationCall? call;
  @override
  State<StagingClubInvitations> createState() => _StagingClubInvitationsState();
}

class _StagingClubInvitationsState extends State<StagingClubInvitations> {
  Future<dynamic> _call(String name, Map<String, dynamic> params) =>
      widget.call?.call(name, params) ??
      Supabase.instance.client.rpc(name, params: params);
  late Future<dynamic> _items = _call('my_staging_club_invitations', {});
  bool _busy = false;
  String? _error;
  Future<void> _accept(Map row) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => ClubOnlineDialog(
        title: Text('Join ${row['club_name']}?'),
        content: const Text(
          'Accepting activates your membership of this club. Your other club memberships and password stay unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Accept invitation'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final clubId = row['club_id']?.toString();
      if (clubId == null || clubId.isEmpty) throw StateError('Club missing');
      final accepted = await _call('accept_staging_club_invitation', {
        'p_id': row['id'],
      });
      if (accepted != true) throw StateError('Invitation was not accepted');
      await widget.onAccepted(clubId);
      if (mounted) {
        setState(() => _items = _call('my_staging_club_invitations', {}));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Invitation could not be accepted. Refresh your clubs and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _items,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return TextButton(
          onPressed: () =>
              setState(() => _items = _call('my_staging_club_invitations', {})),
          child: const Text('Check club invitations again'),
        );
      }
      final rows = snapshot.data as List? ?? [];
      if (rows.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Club invitations',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_error != null) Text(_error!),
          for (final row in rows)
            Card(
              child: ListTile(
                title: Text('${row['club_name']}'),
                subtitle: const Text(
                  'Invited · Membership inactive until you accept',
                ),
                trailing: TextButton(
                  onPressed: _busy ? null : () => _accept(row as Map),
                  child: const Text('Accept invitation'),
                ),
              ),
            ),
        ],
      );
    },
  );
}
