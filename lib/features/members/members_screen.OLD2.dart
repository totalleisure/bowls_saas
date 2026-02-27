import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'member_edit_screen.dart';

class MembersScreen extends StatefulWidget {
  final String clubId;

  const MembersScreen({super.key, required this.clubId});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  bool _isAdmin = false;
  List<Map<String, dynamic>> _rows = const [];

  final TextEditingController _emailCtrl = TextEditingController();
  String _roleToAdd = 'member';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Widget _memberTitleRow({
    required String last,
    required String first,
    required String email,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(
            last.isEmpty ? '-' : last,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: Text(
            first.isEmpty ? '-' : first,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            email.isEmpty ? '-' : email,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _rows = const [];
          _isAdmin = false;
          _loading = false;
          _error = 'Not signed in';
        });
        return;
      }

      // My member_profile_id
      final mp = await _client
          .from('member_profiles')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      final myProfileId = mp?['id']?.toString();

      // Admin?
      if (myProfileId != null) {
        final adminRow = await _client
            .from('club_memberships')
            .select('role')
            .eq('club_id', widget.clubId)
            .eq('member_profile_id', myProfileId)
            .maybeSingle();

        _isAdmin = (adminRow?['role']?.toString() == 'admin');
      } else {
        _isAdmin = false;
      }

      // Load roster with the fields we actually want to display
      final res = await _client
          .from('club_memberships')
          .select(
            'member_profile_id, role, is_active, '
            'member_profiles('
            'email_address, first_name, last_name, display_name, phone, '
            'address_line1, address_line2, town_city, county, postcode'
            ')',
          )
          .eq('club_id', widget.clubId);

      final list = (res as List).cast<Map<String, dynamic>>();

      // Sort: last_name then first_name (blank names go last)
      list.sort((a, b) {
        final ap = (a['member_profiles'] as Map?)?.cast<String, dynamic>() ?? const {};
        final bp = (b['member_profiles'] as Map?)?.cast<String, dynamic>() ?? const {};

        String norm(String? s) => (s ?? '').toLowerCase().trim();

        final al = norm(ap['last_name']?.toString());
        final bl = norm(bp['last_name']?.toString());
        final af = norm(ap['first_name']?.toString());
        final bf = norm(bp['first_name']?.toString());

        // push blanks to bottom
        if (al.isEmpty && bl.isNotEmpty) return 1;
        if (bl.isEmpty && al.isNotEmpty) return -1;

        final c1 = al.compareTo(bl);
        if (c1 != 0) return c1;
        return af.compareTo(bf);
      });

      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _updateMembership({
    required String memberProfileId,
    required String role,
    required bool isActive,
  }) async {
    await _client
        .from('club_memberships')
        .update({
          'role': role,
          'is_active': isActive,
        })
        .eq('club_id', widget.clubId)
        .eq('member_profile_id', memberProfileId);
  }

  Future<void> _openMemberEdit({
    required String memberProfileId,
    required Map<String, dynamic> memberProfile,
  }) async {
    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MemberEditScreen(
          memberProfileId: memberProfileId,
          initial: memberProfile,
        ),
      ),
    );

    if (updated == true) {
      await _load(); // ensures updated email/name reflect in the list
    }
  }

  Future<void> _addByEmail() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) return;

    try {
      // Find member_profile by email_address (adjust if you use a different column)
      final mp = await _client
          .from('member_profiles')
          .select('id')
          .ilike('email_address', email)
          .maybeSingle();

      final memberProfileId = mp?['id']?.toString();
      if (memberProfileId == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No member profile found for that email')),
        );
        return;
      }

      await _client.from('club_memberships').insert({
        'club_id': widget.clubId,
        'member_profile_id': memberProfileId,
        'role': _roleToAdd,
        'is_active': true,
      });

      _emailCtrl.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member added')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_isAdmin) ...[
                      Text('Add member by email',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Member email',
                          hintText: 'e.g. member.name@example.com',
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _roleToAdd,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(value: 'member', child: Text('member')),
                          DropdownMenuItem(value: 'captain', child: Text('captain')),
                          DropdownMenuItem(value: 'selector', child: Text('selector')),
                          DropdownMenuItem(value: 'admin', child: Text('admin')),
                        ],
                        onChanged: (v) => setState(() => _roleToAdd = v ?? 'member'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _addByEmail,
                        child: const Text('Add member'),
                      ),
                      const Divider(height: 32),
                    ],

                    // Optional header row (small)
                    DefaultTextStyle(
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall!
                          .copyWith(color: Theme.of(context).hintColor),
                      child: _memberTitleRow(last: 'Last', first: 'First', email: 'Email'),
                    ),
                    const SizedBox(height: 8),

                    ..._rows.map((r) {
                      final mp = (r['member_profiles'] as Map?)?.cast<String, dynamic>() ?? const {};
                      final memberProfileId = r['member_profile_id'].toString();

                      final last = (mp['last_name'] ?? '').toString().trim();
                      final first = (mp['first_name'] ?? '').toString().trim();
                      final email = (mp['email_address'] ?? '').toString().trim();

                      final role = (r['role'] ?? 'member').toString();
                      final active = r['is_active'] == true;

                      if (!_isAdmin) {
                        return ListTile(
                          dense: true,
                          visualDensity: const VisualDensity(vertical: -3),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          title: _memberTitleRow(last: last, first: first, email: email),
                          subtitle: Text('role: $role • ${active ? 'active' : 'inactive'}'),
                          onTap: () => _openMemberEdit(
                            memberProfileId: memberProfileId,
                            memberProfile: mp,
                          ),
                        );
                      }

                      return _EditableMemberRow(
                        lastName: last,
                        firstName: first,
                        email: email,
                        initialRole: role,
                        initialActive: active,
                        onEdit: () => _openMemberEdit(
                          memberProfileId: memberProfileId,
                          memberProfile: mp,
                        ),
                        onSave: (newRole, newActive) async {
                          try {
                            await _updateMembership(
                              memberProfileId: memberProfileId,
                              role: newRole,
                              isActive: newActive,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Updated')),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Update failed: $e')),
                            );
                            rethrow;
                          }
                        },
                      );
                    }),
                  ],
                ),
    );
  }
}

class _EditableMemberRow extends StatefulWidget {
  final String lastName;
  final String firstName;
  final String email;

  final String initialRole;
  final bool initialActive;

  final Future<void> Function(String role, bool active) onSave;
  final VoidCallback onEdit;

  const _EditableMemberRow({
    required this.lastName,
    required this.firstName,
    required this.email,
    required this.initialRole,
    required this.initialActive,
    required this.onSave,
    required this.onEdit,
  });

  @override
  State<_EditableMemberRow> createState() => _EditableMemberRowState();
}

class _EditableMemberRowState extends State<_EditableMemberRow> {
  late String _role;
  late bool _active;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
    _active = widget.initialActive;
  }

  Widget _titleRow() {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(
            widget.lastName.isEmpty ? '-' : widget.lastName,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 120,
          child: Text(
            widget.firstName.isEmpty ? '-' : widget.firstName,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.email.isEmpty ? '-' : widget.email,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: widget.onEdit,
        dense: true,
        visualDensity: const VisualDensity(vertical: -3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        title: _titleRow(),
        trailing: _saving
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  DropdownButton<String>(
                    value: _role,
                    underline: const SizedBox.shrink(),
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: 'member', child: Text('member')),
                      DropdownMenuItem(value: 'captain', child: Text('captain')),
                      DropdownMenuItem(value: 'selector', child: Text('selector')),
                      DropdownMenuItem(value: 'admin', child: Text('admin')),
                    ],
                    onChanged: (v) async {
                      if (v == null || v == _role) return;

                      final oldRole = _role;
                      setState(() {
                        _role = v;
                        _saving = true;
                      });

                      try {
                        await widget.onSave(_role, _active);
                      } catch (_) {
                        if (mounted) setState(() => _role = oldRole);
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
                  ),
                  Switch(
                    value: _active,
                    onChanged: (v) async {
                      if (v == _active) return;

                      final oldActive = _active;
                      setState(() {
                        _active = v;
                        _saving = true;
                      });

                      try {
                        await widget.onSave(_role, _active);
                      } catch (_) {
                        if (mounted) setState(() => _active = oldActive);
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Edit details',
                    onPressed: widget.onEdit,
                  ),
                ],
              ),
      ),
    );
  }
}