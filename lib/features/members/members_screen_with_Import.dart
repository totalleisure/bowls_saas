import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

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

  Future<bool> _confirmImportCsv({  
    required String fileName,
    required int bytes,
  }) async {
    String prettySize;
    if (bytes < 1024) {
      prettySize = '$bytes B';
    } else if (bytes < 1024 * 1024) {
      prettySize = '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      prettySize = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Import members from CSV?'),
        content: Text(
          'File: $fileName\nSize: $prettySize\n\n'
          'This will create users (if passwords are provided) or create invites (if passwords are blank).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import')),
        ],
      ),
    );

    return ok == true;
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
          .select('member_profile_id, role, is_active, member_profiles(display_name, phone, email_address, first_name, last_name)')
          .eq('club_id', widget.clubId)
          .order('created_at');

      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows);

        // Sort by last_name then first_name (case-insensitive). Blanks at bottom.
        _rows.sort((a, b) {
          final ap = (a['member_profiles'] as Map?)?.cast<String, dynamic>() ?? const {};
          final bp = (b['member_profiles'] as Map?)?.cast<String, dynamic>() ?? const {};

          final al = (ap['last_name'] ?? '').toString().toLowerCase();
          final bl = (bp['last_name'] ?? '').toString().toLowerCase();
          final af = (ap['first_name'] ?? '').toString().toLowerCase();
          final bf = (bp['first_name'] ?? '').toString().toLowerCase();

          if (al.isEmpty && bl.isNotEmpty) return 1;
          if (bl.isEmpty && al.isNotEmpty) return -1;

          final c1 = al.compareTo(bl);
          if (c1 != 0) return c1;

          if (af.isEmpty && bf.isNotEmpty) return 1;
          if (bf.isEmpty && af.isNotEmpty) return -1;

          return af.compareTo(bf);
        });

        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }
  
  Future<void> _importMembersCsv() async {
    if (!_isAdmin) return;

    try {
      final client = Supabase.instance.client;

      // Pick CSV (works on web + mobile)
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;

      // These two lines FIX your "fileName not defined" error
      final String fileName = picked.name;
      final Uint8List? bytes = picked.bytes;

      if (bytes == null) {
        throw Exception('Could not read CSV file bytes.');
      }

      // Confirm BEFORE uploading
      final confirmed = await _confirmImportCsv(
        fileName: fileName,
        bytes: bytes.length,
      );

      if (!confirmed) return;

      final storagePath =
          '${widget.clubId}/members_${DateTime.now().millisecondsSinceEpoch}.csv';

      // Upload to Storage (bucket name is case sensitive in your project)
      await client.storage.from('Imports').uploadBinary(
            storagePath,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'text/csv',
            ),
          );

      // Call Edge Function to import users
      final resp = await client.functions.invoke(
        'import_members_csv',
        body: {
          'club_id': widget.clubId,
          'storage_path': storagePath,
          'default_role': 'member',
          'invite_redirect_to': '',
          'bucket': 'Imports',
        },
      );

      if (resp.status != 200) {
        throw Exception(resp.data?.toString() ?? 'Import failed');
      }

      final data = resp.data as Map<String, dynamic>;
      final summary = (data['summary'] as Map?) ?? {};
      final report = (data['report'] as List?) ?? [];

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Import complete'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Created: ${summary['created'] ?? 0}'),
                  Text('Invited: ${summary['invited'] ?? 0}'),
                  Text('Linked: ${summary['linked'] ?? 0}'),
                  Text('Errors: ${summary['errors'] ?? 0}'),
                  const SizedBox(height: 12),
                  if ((summary['errors'] ?? 0) != 0) ...[
                    const Text('Errors:', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    for (final r in report)
                      if (r is Map && r['status'] == 'error')
                        Text('Row ${r['row']}: ${r['email'] ?? ''} — ${r['message'] ?? ''}'),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
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
          if (_isAdmin)
            IconButton(
              tooltip: 'Import members (CSV)',
              onPressed: _loading ? null : _importMembersCsv,
              icon: const Icon(Icons.upload_file),
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

                      final last = (mp?['last_name'] as String?)?.trim() ?? '';
                      final first = (mp?['first_name'] as String?)?.trim() ?? '';
                      final email = (mp?['email_address'] as String?)?.trim() ?? '';
                      final phone = (mp?['phone'] as String?)?.trim() ?? '';
                      final role = r['role'].toString();
                      final active = r['is_active'] == true;

                      final memberProfileId = r['member_profile_id'].toString();

                      if (!_isAdmin) {
                        return ListTile(
                          title: memberTitleRow(last: last, first: first, email: email),
                          subtitle: Text([
                            role,
                            if (phone.isNotEmpty) phone,
                            active ? 'active' : 'inactive',
                          ].join(' • ')),
                        );
                      }

                      return _EditableMemberRow(
                        firstName: first,
                        lastName: last,
                        email: email,
                        phone: phone,
                        initialRole: role,
                        initialActive: active,
                        onSave: (newRole, newActive) => _updateMembership(
                          memberProfileId: memberProfileId,
                          role: newRole,
                          isActive: newActive,
                        ),
                      );

                                          }),
                  ],
                ),
    );
  }
}


class _EditableMemberRow extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String initialRole;
  final bool initialActive;
  final Future<void> Function(String role, bool active) onSave;

  const _EditableMemberRow({
    required this.firstName,
    required this.lastName,
    required this.email,
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
        title: memberTitleRow(last: widget.lastName, first: widget.firstName, email: widget.email),
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




// Compact 3-column title row: Last name | First name | Email
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
