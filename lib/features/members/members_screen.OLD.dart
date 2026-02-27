import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

class MembersScreen extends StatefulWidget {
  final String clubId;
  const MembersScreen({super.key, required this.clubId});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}


class _MembersScreenState extends State<MembersScreen> {
  bool _loading = true;
  String? _error;

  bool _isAdmin = false;

  List<Map<String, dynamic>> _rows = [];

  final _emailCtrl = TextEditingController();
  String _role = 'member';

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
      final client = Supabase.instance.client;

      // Admin check (direct membership lookup, reliable)
      final myId = (await client.rpc('my_member_profile_id')).toString();
      final cm = await client
          .from('club_memberships')
          .select('role, is_active')
          .eq('club_id', widget.clubId)
          .eq('member_profile_id', myId)
          .maybeSingle();

      _isAdmin = cm != null && cm['is_active'] == true && cm['role'] == 'admin';

      final rows = await client
          .from('club_memberships')
          .select('member_profile_id, role, is_active, member_profiles(display_name, phone)')
          .eq('club_id', widget.clubId)
          .order('created_at');

      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _addByEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;

    try {
      await Supabase.instance.client.rpc(
        'add_member_to_club_by_email',
        params: {'p_club_id': widget.clubId, 'p_email': email, 'p_role': _role},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $email as $_role')),
        );
      }
      _emailCtrl.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Add member failed: $e')),
        );
      }
    }
  }

  Future<void> _updateMembership({
    required String memberProfileId,
    required String role,
    required bool isActive,
  }) async {
    try {
      await Supabase.instance.client.rpc(
        'admin_update_membership',
        params: {
          'p_club_id': widget.clubId,
          'p_member_profile_id': memberProfileId,
          'p_role': role,
          'p_is_active': isActive,
        },
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Member updated')),
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
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
                          helperText: 'They must already have a login (Auth user) in the system',
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(value: 'member', child: Text('member')),
                          DropdownMenuItem(value: 'captain', child: Text('captain')),
                          DropdownMenuItem(value: 'selector', child: Text('selector')),
                          DropdownMenuItem(value: 'admin', child: Text('admin')),
                        ],
                        onChanged: (v) => setState(() => _role = v ?? 'member'),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _addByEmail,
                        child: const Text('Add member'),
                      ),
                      const Divider(height: 32),
                    ],
                    Text('Club roster',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ..._rows.map((r) {
                      final mp = r['member_profiles'] as Map<String, dynamic>?;
                      final name = (mp?['display_name'] as String?) ?? '(no name)';
                      final phone = (mp?['phone'] as String?) ?? '';
                      final role = r['role'].toString();
                      final active = r['is_active'] == true;

                      final memberProfileId = r['member_profile_id'].toString();

                      if (!_isAdmin) {
                        return ListTile(
                          title: Text(name),
                          subtitle: Text([
                            role,
                            if (phone.isNotEmpty) phone,
                            active ? 'active' : 'inactive',
                          ].join(' • ')),
                        );
                      }

                      return _EditableMemberRow(
                        name: name,
                        phone: phone,
                        initialRole: role,
                        initialActive: active,
                        onSave: (newRole, newActive) => _updateMembership(
                          memberProfileId: memberProfileId,
                          role: newRole,
                          isActive: newActive,
                        ),
                      );

                      // Admin view: role dropdown + active toggle + save
                      String pendingRole = role;
                      bool pendingActive = active;

                      return StatefulBuilder(
                        builder: (context, setRowState) {
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                dense: true,
                                title: Text(name),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (phone.isNotEmpty) Text(phone),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: pendingRole,
                                            decoration: const InputDecoration(
                                              labelText: 'Role',
                                              isDense: true,
                                            ),
                                            items: const [
                                              DropdownMenuItem(value: 'member', child: Text('member')),
                                              DropdownMenuItem(value: 'captain', child: Text('captain')),
                                              DropdownMenuItem(value: 'selector', child: Text('selector')),
                                              DropdownMenuItem(value: 'admin', child: Text('admin')),
                                            ],
                                            onChanged: (v) => setRowState(() {
                                              pendingRole = v ?? pendingRole;
                                            }),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          children: [
                                            const Text('Active', style: TextStyle(fontSize: 12)),
                                            Switch(
                                              value: pendingActive,
                                              onChanged: (v) => setRowState(() {
                                                pendingActive = v;
                                              }),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.save),
                                  tooltip: 'Save',
                                  onPressed: () => _updateMembership(
                                    memberProfileId: memberProfileId,
                                    role: pendingRole,
                                    isActive: pendingActive,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }),
                  ],
                ),
    );
  }
}


class _EditableMemberRow extends StatefulWidget {
  final String name;
  final String phone;
  final String initialRole;
  final bool initialActive;
  final Future<void> Function(String role, bool active) onSave;

  const _EditableMemberRow({
    required this.name,
    required this.phone,
    required this.initialRole,
    required this.initialActive,
    required this.onSave,
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
        dense: true,
        title: Text(widget.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.phone.isNotEmpty) Text(widget.phone),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _role,
                    decoration: const InputDecoration(labelText: 'Role', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'member', child: Text('member')),
                      DropdownMenuItem(value: 'captain', child: Text('captain')),
                      DropdownMenuItem(value: 'selector', child: Text('selector')),
                      DropdownMenuItem(value: 'admin', child: Text('admin')),
                    ],
                    onChanged: _saving ? null : (v) => setState(() => _role = v ?? _role),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    const Text('Active', style: TextStyle(fontSize: 12)),
                    Switch(
                      value: _active,
                      onChanged: _saving ? null : (v) => setState(() => _active = v),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        trailing: _saving
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : IconButton(
                icon: const Icon(Icons.save),
                tooltip: 'Save',
                onPressed: () async {
                  setState(() => _saving = true);
                  await widget.onSave(_role, _active);
                  if (mounted) setState(() => _saving = false);
                },
              ),
      ),
    );
  }
}


