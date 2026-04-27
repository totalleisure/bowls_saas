import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

import '../../core/permissions/club_role_resolver.dart';
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
  bool _isAdmin = false;
  bool _canManageMembers = false;
  bool _readOnly = true;

  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  
  String? _error;
  
  String _searchText = '';

  List<Map<String, dynamic>> _rows = const [];

  List<Map<String, dynamic>> get _filteredRows {
    final q = _searchText.trim().toLowerCase();
    if (q.isEmpty) return _rows;

    return _rows.where((row) {
      final mp =
          (row['member_profiles'] as Map?)?.cast<String, dynamic>() ?? const {};

      final first = (mp['first_name'] ?? '').toString().toLowerCase();
      final last = (mp['last_name'] ?? '').toString().toLowerCase();
      final displayName = (mp['display_name'] ?? '').toString().toLowerCase();
      final email = (mp['email_address'] ?? '').toString().toLowerCase();
      final phone = (mp['phone'] ?? '').toString().toLowerCase();
      final role = (row['role'] ?? '').toString().toLowerCase();

      return first.contains(q) ||
          last.contains(q) ||
          displayName.contains(q) ||
          email.contains(q) ||
          phone.contains(q) ||
          role.contains(q);
    }).toList();
  }  

  String _roleLabel(String role) {
    switch (role) {
      case 'admin':
        return 'Admin';
      case 'selector':
        return 'Selector';
      case 'captain':
        return 'Captain';
      default:
        return 'Member';
    }
  }

  final ScrollController _scrollController = ScrollController();
  double _savedScrollOffset = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
          _canManageMembers = false;
          _readOnly = true;
          _loading = false;
          _error = 'Not signed in';
        });
        return;
      }

      final mp = await _client
          .from('member_profiles')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      final myProfileId = mp?['id']?.toString();

      await _loadUserPermissions(myProfileId);

      final res = await _client
          .from('club_memberships')
          .select(
            'member_profile_id, role, is_active, '
            'member_profiles(email_address, first_name, last_name, display_name, phone, '
            'gender, gender_self_described, sex_at_birth)'
          )
          .eq('club_id', widget.clubId)
          .order('role', ascending: true);

      final list = (res as List).cast<Map<String, dynamic>>();

      list.sort((a, b) {
        final ap =
            (a['member_profiles'] as Map?)?.cast<String, dynamic>() ?? const {};
        final bp =
            (b['member_profiles'] as Map?)?.cast<String, dynamic>() ?? const {};

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

  Future<void> _loadUserPermissions(String? myProfileId) async {
    final userId = _client.auth.currentUser?.id;

    bool isSuperuser = false;
    bool isClubAdmin = false;

    if (userId != null) {
      final superRow = await _client
          .from('app_superusers')
          .select('user_id')
          .eq('user_id', userId)
          .maybeSingle();

      isSuperuser = superRow != null;
    }

    if (myProfileId != null) {
      final membershipRow = await _client
          .from('club_memberships')
          .select('role')
          .eq('club_id', widget.clubId)
          .eq('member_profile_id', myProfileId)
          .maybeSingle();

      final role = (membershipRow?['role'] ?? '').toString();
      isClubAdmin = role == 'admin';
    }

    final canManageMembers = isSuperuser || isClubAdmin;

    if (!mounted) return;

    setState(() {
      _isSuperuser = isSuperuser;
      _isClubAdmin = isClubAdmin;
      _canManageMembers = canManageMembers;
      _isAdmin = canManageMembers;
      _readOnly = !canManageMembers;
    });
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
  
  Future<void> _openMemberEdit({
    required String memberProfileId,
    required Map<String, dynamic> memberProfile,
    required String role,
    required bool active,    
  }) async {
    _savedScrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0;

    final updated = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MemberEditScreen(
          memberProfileId: memberProfileId,
          initial: memberProfile,
          clubId: widget.clubId,
          initialRole: role,
          initialActive: active,
          canManageMembers: _canManageMembers,
        ),
      ),
    );

    if (updated == true) {
      await _load();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;

        final max = _scrollController.position.maxScrollExtent;
        final target = _savedScrollOffset.clamp(0, max).toDouble();

        _scrollController.jumpTo(target);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Members'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          if (_canManageMembers)
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
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search members',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchText.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  tooltip: 'Clear search',
                                  onPressed: () {
                                    setState(() {
                                      _searchText = '';
                                    });
                                  },
                                ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchText = value;
                          });
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${_filteredRows.length} member${_filteredRows.length == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[700],
                              ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _filteredRows.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.search_off,
                                      size: 48,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      _searchText.trim().isEmpty
                                          ? 'No members found.'
                                          : 'No members match your search.',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              key: const PageStorageKey('members-list'),
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: _filteredRows.length,
                              itemBuilder: (context, index) {
                                final row = _filteredRows[index];

                                final memberProfileId =
                                    row['member_profile_id']?.toString() ?? '';

                                final mp = (row['member_profiles'] as Map?)
                                        ?.cast<String, dynamic>() ??
                                    const {};

                                final email =
                                    (mp['email_address'] ?? '').toString().trim();
                                final first =
                                    (mp['first_name'] ?? '').toString().trim();
                                final last =
                                    (mp['last_name'] ?? '').toString().trim();
                                final displayName =
                                    (mp['display_name'] ?? '').toString().trim();
                                final phone = (mp['phone'] ?? '').toString().trim();

                                final role = (row['role'] ?? 'member').toString();
                                final active = (row['is_active'] ?? true) as bool;

                                final showPhoneFlag =
                                    (mp['show_phone_in_directory'] ?? true) as bool;
                                final showEmailFlag =
                                    (mp['show_email_in_directory'] ?? true) as bool;

                                final isAdminViewer = _canManageMembers;
                                final showPhone = isAdminViewer || showPhoneFlag;
                                final showEmail = isAdminViewer || showEmailFlag;

                                final name = displayName.isNotEmpty
                                    ? displayName
                                    : [first, last]
                                        .where((e) => e.isNotEmpty)
                                        .join(' ');

                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    title: Text(name.isEmpty ? '(no name)' : name),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (_canManageMembers) Text(_roleLabel(role)),
                                        if (showPhone && phone.isNotEmpty) Text(phone),
                                        if (showEmail && email.isNotEmpty) Text(email),
                                        if (!active)
                                          const Text(
                                            'Inactive',
                                            style: TextStyle(color: Colors.grey),
                                          ),
                                      ],
                                    ),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _openMemberEdit(
                                      memberProfileId: memberProfileId,
                                      memberProfile: mp,
                                      role: role,
                                      active: active,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}