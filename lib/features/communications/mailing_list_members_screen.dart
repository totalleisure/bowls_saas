import 'package:bowls_saas/core/widgets/club_member_picker_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MailingListMembersScreen extends StatefulWidget {
  final String clubId;
  final String mailingListId;
  final String mailingListName;

  const MailingListMembersScreen({
    super.key,
    required this.clubId,
    required this.mailingListId,
    required this.mailingListName,
  });

  @override
  State<MailingListMembersScreen> createState() =>
      _MailingListMembersScreenState();
}

class _MailingListMembersScreenState extends State<MailingListMembersScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _listMembers = [];
  final Set<String> _selectedMembershipIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _memberName(Map<String, dynamic> profile) {
    final displayName = (profile['display_name'] ?? '').toString().trim();
    if (displayName.isNotEmpty) return displayName;

    final firstName = (profile['first_name'] ?? '').toString().trim();
    final lastName = (profile['last_name'] ?? '').toString().trim();
    final fullName = '$firstName $lastName'.trim();

    return fullName.isEmpty ? 'Unnamed member' : fullName;
  }

  Set<String> get _currentMemberProfileIds {
    return _listMembers
        .map((row) => row['member_profile_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final rows = await Supabase.instance.client
          .from('mailing_list_members')
          .select('''
            id,
            mailing_list_id,
            member_profile_id,
            is_active,
            notes,
            added_at,
            member_profile:member_profiles!mailing_list_members_member_profile_id_fkey(
              id,
              display_name,
              first_name,
              last_name,
              email_address
            )
          ''')
          .eq('mailing_list_id', widget.mailingListId)
          .eq('is_active', true)
          .order('added_at', ascending: true);

      final members = List<Map<String, dynamic>>.from(rows as List);

      members.sort((a, b) {
        final aProfile = Map<String, dynamic>.from(
          (a['member_profile'] as Map?) ?? const <String, dynamic>{},
        );
        final bProfile = Map<String, dynamic>.from(
          (b['member_profile'] as Map?) ?? const <String, dynamic>{},
        );

        return _memberName(
          aProfile,
        ).toLowerCase().compareTo(_memberName(bProfile).toLowerCase());
      });

      if (!mounted) return;

      setState(() {
        _listMembers = members;
        _selectedMembershipIds.clear();
        _loading = false;
        _saving = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
        _saving = false;
      });
    }
  }

  Future<void> _addMembers() async {
    if (_saving) return;

    final selectedIds = await Navigator.of(context).push<List<String>?>(
      MaterialPageRoute(
        builder: (_) => ClubMemberPickerPage(
          clubId: widget.clubId,
          title: 'Add Members to ${widget.mailingListName}',
          fixtureId: null,
          useFixtureSection: false,
          allowMultiple: true,
          excludeMemberProfileIds: _currentMemberProfileIds,
        ),
      ),
    );

    if (!mounted || selectedIds == null || selectedIds.isEmpty) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final rows = selectedIds
          .where((id) => id.trim().isNotEmpty)
          .map(
            (memberProfileId) => {
              'mailing_list_id': widget.mailingListId,
              'member_profile_id': memberProfileId,
              'is_active': true,
              'removed_at': null,
            },
          )
          .toList();

      if (rows.isEmpty) {
        if (mounted) setState(() => _saving = false);
        return;
      }

      await Supabase.instance.client
          .from('mailing_list_members')
          .upsert(rows, onConflict: 'mailing_list_id,member_profile_id');

      await _load();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${rows.length} member(s) added to ${widget.mailingListName}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _removeSelected() async {
    if (_selectedMembershipIds.isEmpty || _saving) return;

    final selectedCount = _selectedMembershipIds.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove members from list?'),
        content: Text(
          'Remove $selectedCount selected member(s) from '
          '${widget.mailingListName}?\n\n'
          'Their member records and previous communication history '
          'will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await Supabase.instance.client
          .from('mailing_list_members')
          .delete()
          .inFilter('id', _selectedMembershipIds.toList());

      await _load();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$selectedCount member(s) removed from '
            '${widget.mailingListName}.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedMembershipIds.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mailingListName),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _saving ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _saving ? null : _addMembers,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Members'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${_listMembers.length} active member(s)',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (selectedCount > 0)
                        FilledButton.tonalIcon(
                          onPressed: _saving ? null : _removeSelected,
                          icon: const Icon(Icons.person_remove_alt_1),
                          label: Text('Remove ($selectedCount)'),
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _listMembers.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'There are no members on this mailing list.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.only(bottom: 96),
                            itemCount: _listMembers.length,
                            itemBuilder: (context, index) {
                              final row = _listMembers[index];
                              final membershipId = row['id']?.toString() ?? '';
                              final profile = Map<String, dynamic>.from(
                                (row['member_profile'] as Map?) ??
                                    const <String, dynamic>{},
                              );
                              final email = (profile['email_address'] ?? '')
                                  .toString()
                                  .trim();

                              return CheckboxListTile(
                                value: _selectedMembershipIds.contains(
                                  membershipId,
                                ),
                                title: Text(_memberName(profile)),
                                subtitle: Text(
                                  email.isEmpty
                                      ? 'No email address recorded'
                                      : email,
                                ),
                                secondary: Icon(
                                  email.isEmpty
                                      ? Icons.mail_outline
                                      : Icons.mark_email_read_outlined,
                                ),
                                onChanged: _saving
                                    ? null
                                    : (value) {
                                        setState(() {
                                          if (value == true) {
                                            _selectedMembershipIds.add(
                                              membershipId,
                                            );
                                          } else {
                                            _selectedMembershipIds.remove(
                                              membershipId,
                                            );
                                          }
                                        });
                                      },
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
