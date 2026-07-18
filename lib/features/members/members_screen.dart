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
  String _roleFilter = 'all';

  String? _myMemberProfileId;

  List<Map<String, dynamic>> _rows = const [];

  List<Map<String, dynamic>> get _filteredRows {
    final q = _searchText.trim().toLowerCase();

    return _rows.where((row) {
      final mp =
          (row['member_profiles'] as Map?)?.cast<String, dynamic>() ?? const {};

      final first = (mp['first_name'] ?? '').toString().toLowerCase();
      final last = (mp['last_name'] ?? '').toString().toLowerCase();
      final displayName = (mp['display_name'] ?? '').toString().toLowerCase();
      final memberProfileId = row['member_profile_id']?.toString();
      final isOwnRecord = memberProfileId == _myMemberProfileId;
      final canSearchEmail =
          _canManageMembers ||
          isOwnRecord ||
          mp['show_email_in_directory'] == true;
      final canSearchPhone =
          _canManageMembers ||
          isOwnRecord ||
          mp['show_mobile_in_directory'] == true;
      final email = canSearchEmail
          ? (mp['email_address'] ?? '').toString().toLowerCase()
          : '';
      final phone = canSearchPhone
          ? (mp['phone'] ?? '').toString().toLowerCase()
          : '';
      final role = (row['role'] ?? '').toString().toLowerCase();
      final position = (mp['preferred_position'] ?? '')
          .toString()
          .toLowerCase();

      final active = row['is_active'] == true;
      final isCoach = row['is_coach'] == true;
      final coachingAward = (row['coaching_award'] ?? '')
          .toString()
          .toLowerCase();

      final matchesSearch =
          q.isEmpty ||
          first.contains(q) ||
          last.contains(q) ||
          displayName.contains(q) ||
          email.contains(q) ||
          phone.contains(q) ||
          role.contains(q) ||
          position.contains(q) ||
          coachingAward.contains(q);

      final matchesFilter =
          _roleFilter == 'all' ||
          (_roleFilter == 'inactive' && !active) ||
          (_roleFilter == 'coach' && isCoach) ||
          role == _roleFilter;

      return matchesSearch && matchesFilter;
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

  String? _preferredPositionLabel(String? value) {
    switch ((value ?? '').toLowerCase()) {
      case 'lead':
        return 'Lead';
      case 'third':
        return 'Third';
      case 'skip':
        return 'Skip';
    }
    return null;
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

      _myMemberProfileId = myProfileId;

      await _loadUserPermissions(myProfileId);

      final res = await _client
          .from('club_memberships')
          .select(
            'member_profile_id, role, is_active, is_coach, coaching_award, '
            'member_profiles('
            'email_address, first_name, last_name, display_name, phone, home_phone, office_phone, '
            'address_line1, address_line2, town_city, county, postcode, '
            'gender, gender_self_described, sex_at_birth, preferred_position, '
            'show_mobile_in_directory, show_home_phone_in_directory, show_office_phone_in_directory, '
            'show_email_in_directory, show_address_in_directory'
            ')',
          )
          .eq('club_id', widget.clubId)
          .order('role', ascending: true);

      final list = (res as List).cast<Map<String, dynamic>>();

      // For the signed-in member, Auth is the master source for the login
      // email. Use it immediately in the displayed row so the list never shows
      // the old profile copy after a successfully confirmed email change.
      final authEmail = _client.auth.currentUser?.email?.trim() ?? '';
      if (myProfileId != null && authEmail.isNotEmpty) {
        for (final row in list) {
          if (row['member_profile_id']?.toString() != myProfileId) continue;

          final profile =
              (row['member_profiles'] as Map?)?.cast<String, dynamic>() ??
              <String, dynamic>{};
          profile['email_address'] = authEmail;
          row['member_profiles'] = profile;
          break;
        }
      }

      list.sort((a, b) {
        final aIsMe = a['member_profile_id']?.toString() == myProfileId;
        final bIsMe = b['member_profile_id']?.toString() == myProfileId;

        if (aIsMe != bIsMe) return aIsMe ? -1 : 1;

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
      await client.storage
          .from('Imports')
          .uploadBinary(
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
                    const Text(
                      'Errors:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    for (final r in report)
                      if (r is Map && r['status'] == 'error')
                        Text(
                          'Row ${r['row']}: ${r['email'] ?? ''} — ${r['message'] ?? ''}',
                        ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
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
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
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
    required bool isOwnRecord,
    required bool isCoach,
    String? coachingAward,
  }) async {
    _savedScrollOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0;

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MemberEditScreen(
          memberProfileId: memberProfileId,
          initial: memberProfile,
          clubId: widget.clubId,
          initialRole: role,
          initialActive: active,
          isOwnRecord: isOwnRecord,
          canManageMembers: _canManageMembers,
          initialIsCoach: isCoach,
          initialCoachingAward: coachingAward,
        ),
      ),
    );

    // MemberEditScreen can launch Account and Security, where the login
    // email may change outside the ordinary member-profile save action.
    // Always reload on return so the list cannot retain a stale email value.
    await _load();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      final max = _scrollController.position.maxScrollExtent;
      final target = _savedScrollOffset.clamp(0, max).toDouble();

      _scrollController.jumpTo(target);
    });
  }

  Widget _filterChip(String value, String label) {
    return FilterChip(
      label: Text(label),
      selected: _roleFilter == value,
      onSelected: (_) {
        setState(() {
          _roleFilter = value;
        });
      },
    );
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
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _filterChip('all', 'All'),
                      _filterChip('member', 'Members'),
                      _filterChip('guest', 'Guests'),
                      _filterChip('captain', 'Captains'),
                      _filterChip('selector', 'Selectors'),
                      _filterChip('admin', 'Admins'),
                      _filterChip('coach', 'Coaches'),
                      _filterChip('inactive', 'Inactive'),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${_filteredRows.length} member${_filteredRows.length == 1 ? '' : 's'}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
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

                            final mp =
                                (row['member_profiles'] as Map?)
                                    ?.cast<String, dynamic>() ??
                                const {};

                            final email = (mp['email_address'] ?? '')
                                .toString()
                                .trim();
                            final first = (mp['first_name'] ?? '')
                                .toString()
                                .trim();
                            final last = (mp['last_name'] ?? '')
                                .toString()
                                .trim();
                            final displayName = (mp['display_name'] ?? '')
                                .toString()
                                .trim();
                            final phone = (mp['phone'] ?? '').toString().trim();

                            final role = (row['role'] ?? 'member').toString();
                            final active = (row['is_active'] ?? true) as bool;

                            final isOwnRecord =
                                memberProfileId == _myMemberProfileId;
                            final showPhoneFlag =
                                mp['show_mobile_in_directory'] == true;
                            final showEmailFlag =
                                mp['show_email_in_directory'] == true;

                            final isAdminViewer = _canManageMembers;
                            final showPhone =
                                isOwnRecord || isAdminViewer || showPhoneFlag;
                            final showEmail =
                                isOwnRecord || isAdminViewer || showEmailFlag;

                            final preferredPosition =
                                (mp['preferred_position'] ?? '')
                                    .toString()
                                    .trim();

                            final preferredPositionLabel =
                                _preferredPositionLabel(preferredPosition);

                            final name = displayName.isNotEmpty
                                ? displayName
                                : [
                                    first,
                                    last,
                                  ].where((e) => e.isNotEmpty).join(' ');

                            final canOpenEdit =
                                _canManageMembers || isOwnRecord;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              color: isOwnRecord ? Colors.green.shade50 : null,
                              child: ListTile(
                                title: Text(
                                  '${name.isEmpty ? '(no name)' : name}'
                                  '${isOwnRecord ? ' — You' : ''}'
                                  '${preferredPositionLabel == null ? '' : ' (Preferred: $preferredPositionLabel)'}',
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_canManageMembers)
                                      Text(_roleLabel(role)),
                                    if (showPhone && phone.isNotEmpty)
                                      Text(phone),
                                    if (showEmail && email.isNotEmpty)
                                      Text(email),
                                    if (!active)
                                      const Text(
                                        'Inactive',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_canManageMembers &&
                                        (mp['sex_at_birth'] ?? '')
                                            .toString()
                                            .isEmpty) ...[
                                      SizedBox(
                                        height: 32,
                                        child: FilledButton(
                                          onPressed: () async {
                                            await _client
                                                .from('member_profiles')
                                                .update({
                                                  'sex_at_birth': 'male',
                                                  'gender': 'male',
                                                })
                                                .eq('id', memberProfileId);

                                            await _load();
                                          },
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                            minimumSize: const Size(36, 32),
                                          ),
                                          child: const Text('M'),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      SizedBox(
                                        height: 32,
                                        child: FilledButton(
                                          onPressed: () async {
                                            await _client
                                                .from('member_profiles')
                                                .update({
                                                  'sex_at_birth': 'female',
                                                  'gender': 'female',
                                                })
                                                .eq('id', memberProfileId);

                                            await _load();
                                          },
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                            ),
                                            minimumSize: const Size(36, 32),
                                          ),
                                          child: const Text('F'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: canOpenEdit
                                    ? () => _openMemberEdit(
                                        memberProfileId: memberProfileId,
                                        memberProfile: mp,
                                        role: role,
                                        active: active,
                                        isCoach: row['is_coach'] == true,
                                        coachingAward: row['coaching_award']
                                            ?.toString(),
                                        isOwnRecord: isOwnRecord,
                                      )
                                    : null,
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
