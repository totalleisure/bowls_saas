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

  @override
  void initState() {
    super.initState();
    _load();
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

      // Find my member_profile_id
      final mp = await _client
          .from('member_profiles')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      final myProfileId = mp?['id']?.toString();

      // Check if I'm admin for this club
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

      // Load club memberships + member profile fields (including address fields you added)
      final res = await _client
          .from('club_memberships')
          .select(
            'member_profile_id, role, is_active, '
            'member_profiles(email_address, first_name, last_name, display_name, phone)',
          )
          .eq('club_id', widget.clubId)
          .order('role', ascending: true);

      final list = (res as List).cast<Map<String, dynamic>>();

      list.sort((a, b) {
        final ap = (a['member_profiles'] as Map?)?.cast<String, dynamic>() ?? const {};
        final bp = (b['member_profiles'] as Map?)?.cast<String, dynamic>() ?? const {};

        final al = (ap['last_name'] ?? '').toString().toLowerCase();
        final bl = (bp['last_name'] ?? '').toString().toLowerCase();
        final af = (ap['first_name'] ?? '').toString().toLowerCase();
        final bf = (bp['first_name'] ?? '').toString().toLowerCase();

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
    try {
      await _client
          .from('club_memberships')
          .update({
            'role': role,
            'is_active': isActive,
          })
          .eq('club_id', widget.clubId)
          .eq('member_profile_id', memberProfileId);

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
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('PATCHED ROW: ${Widget.email}'),
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
              ? Center(child: Text(_error!))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length,
                  itemBuilder: (context, index) {
                    final row = _rows[index];

                    final memberProfileId =
                        row['member_profile_id']?.toString() ?? '';

                    final mp = (row['member_profiles'] as Map?)?.cast<String, dynamic>() ?? const {};

                    final email = (mp['email_address'] ?? '').toString().trim();
                    final first = (mp['first_name'] ?? '').toString().trim();
                    final last  = (mp['last_name'] ?? '').toString().trim();

                    final displayEmail = email.isNotEmpty
                        ? email
                        : (mp['display_name'] ?? '').toString().trim();
                        
                    final role = (row['role'] ?? 'member').toString();
                    final active = (row['is_active'] ?? true) as bool;

                    // Non-admin: compact read-only row
                    if (!_isAdmin) {
                      return ListTile(
                        dense: true,
                        visualDensity: const VisualDensity(vertical: -3),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                        title: Row(
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
                        ),
                        subtitle: Text('role: $role • ${active ? 'active' : 'inactive'}'),
                      );
                    }

                    // Admin: editable row (auto-save)
                    return _EditableMemberRow(
                      firstName: first,
                      lastName: last,
                      email: displayEmail,
                      initialRole: role,
                      initialActive: active,
                      onEdit: () => _openMemberEdit(
                        memberProfileId: memberProfileId,
                        memberProfile: mp,
                      ),
                      onSave: (newRole, newActive) => _updateMembership(
                        memberProfileId: memberProfileId,
                        role: newRole,
                        isActive: newActive,
                      ),
                    );
                  },
                ),
    );
  }
}

class _EditableMemberRow extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String email;
  final String initialRole;
  final bool initialActive;
  final Future<void> Function(String role, bool active) onSave;
  final VoidCallback onEdit;

  const _EditableMemberRow({
    required this.firstName,
    required this.lastName,
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

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        onTap: widget.onEdit,
        dense: true,
        visualDensity: const VisualDensity(vertical: -3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        title: Row(
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
                displayEmail.isEmpty ? '-' : displayEmail,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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

Widget memberTitleRow({
  required String last,
  required String first,
  required String email,
}) {
  return Row(
    children: [
      SizedBox(
        width: 140,
        child: Text(
          Widget.last.isEmpty ? '-' : Widget.last,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 8),
      SizedBox(
        width: 120,
        child: Text(
          Widget.first.isEmpty ? '-' : Widget.first,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          Widget.email.isEmpty ? '-' : Widget.email,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}