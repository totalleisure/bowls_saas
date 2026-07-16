import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'mailing_list_members_screen.dart';
import 'mailing_list_message_screen.dart';

class MailingListsScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const MailingListsScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<MailingListsScreen> createState() => _MailingListsScreenState();
}

class _MailingListsScreenState extends State<MailingListsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _lists = [];
  final Map<String, int> _activeMemberCounts = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final supabase = Supabase.instance.client;

      final rows = await supabase
          .from('mailing_lists')
          .select('''
            id,
            club_id,
            name,
            description,
            system_key,
            is_active,
            allow_self_subscription,
            created_at,
            updated_at
          ''')
          .eq('club_id', widget.clubId)
          .order('is_active', ascending: false)
          .order('name', ascending: true);

      final lists = List<Map<String, dynamic>>.from(rows as List);

      final counts = <String, int>{};
      final ids = lists
          .map((row) => row['id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList();

      if (ids.isNotEmpty) {
        final memberRows = await supabase
            .from('mailing_list_members')
            .select('mailing_list_id')
            .inFilter('mailing_list_id', ids)
            .eq('is_active', true);

        for (final raw in memberRows as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          final listId = row['mailing_list_id']?.toString();

          if (listId == null || listId.isEmpty) continue;

          counts[listId] = (counts[listId] ?? 0) + 1;
        }
      }

      if (!mounted) return;

      setState(() {
        _lists = lists;
        _activeMemberCounts
          ..clear()
          ..addAll(counts);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openMembers(Map<String, dynamic> list) async {
    final listId = list['id']?.toString() ?? '';
    final listName = list['name']?.toString() ?? 'Mailing List';

    if (listId.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MailingListMembersScreen(
          clubId: widget.clubId,
          mailingListId: listId,
          mailingListName: listName,
        ),
      ),
    );

    await _load();
  }

  Future<void> _openMessage(Map<String, dynamic> list) async {
    final listId = list['id']?.toString() ?? '';
    final listName = list['name']?.toString() ?? 'Mailing List';

    if (listId.isEmpty) return;

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MailingListMessageScreen(
          clubId: widget.clubId,
          mailingListId: listId,
          mailingListName: listName,
        ),
      ),
    );
  }

  Future<void> _showListDialog({
    Map<String, dynamic>? existing,
  }) async {
    final isEditing = existing != null;

    final nameController = TextEditingController(
      text: existing?['name']?.toString() ?? '',
    );
    final descriptionController = TextEditingController(
      text: existing?['description']?.toString() ?? '',
    );

    bool isActive = existing?['is_active'] == true || !isEditing;
    bool allowSelfSubscription =
        existing?['allow_self_subscription'] == true;
    bool dialogSaving = false;
    String? dialogError;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              final name = nameController.text.trim();
              final description = descriptionController.text.trim();

              if (name.isEmpty) {
                setDialogState(() {
                  dialogError = 'Please enter a list name.';
                });
                return;
              }

              setDialogState(() {
                dialogSaving = true;
                dialogError = null;
              });

              if (mounted) {
                setState(() => _saving = true);
              }

              try {
                final values = <String, dynamic>{
                  'name': name,
                  'description': description.isEmpty ? null : description,
                  'is_active': isActive,
                  'allow_self_subscription': allowSelfSubscription,
                };

                if (isEditing) {
                  await Supabase.instance.client
                      .from('mailing_lists')
                      .update(values)
                      .eq('id', existing['id']);
                } else {
                  await Supabase.instance.client
                      .from('mailing_lists')
                      .insert({
                    'club_id': widget.clubId,
                    ...values,
                  });
                }

                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop(true);
              } catch (e) {
                if (!dialogContext.mounted) return;

                setDialogState(() {
                  dialogSaving = false;
                  dialogError = e.toString();
                });
              } finally {
                if (mounted) {
                  setState(() => _saving = false);
                }
              }
            }

            return AlertDialog(
              title: Text(
                isEditing ? 'Edit Mailing List' : 'New Mailing List',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (dialogError != null) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          dialogError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: nameController,
                      autofocus: !isEditing,
                      decoration: const InputDecoration(
                        labelText: 'List name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Active'),
                      subtitle: const Text(
                        'Inactive lists remain available for history '
                        'but cannot be used.',
                      ),
                      value: isActive,
                      onChanged: dialogSaving
                          ? null
                          : (value) {
                              setDialogState(() => isActive = value);
                            },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Members may join or leave'),
                      subtitle: const Text(
                        'Show this list in the member Volunteer Lists screen.',
                      ),
                      value: allowSelfSubscription,
                      onChanged: dialogSaving
                          ? null
                          : (value) {
                              setDialogState(() {
                                allowSelfSubscription = value;
                              });
                            },
                    ),
                    if ((existing?['system_key']?.toString() ?? '')
                        .isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'This list is linked to an app function.',
                            style: TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: dialogSaving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: dialogSaving ? null : save,
                  child: dialogSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    descriptionController.dispose();

    if (saved == true) {
      await _load();
    }
  }

  Future<void> _showActions(Map<String, dynamic> list) async {
    final listId = list['id']?.toString() ?? '';
    final isActive = list['is_active'] == true;
    final activeMemberCount = _activeMemberCounts[listId] ?? 0;
    final canSend = isActive && activeMemberCount > 0;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.people_outline),
                title: const Text('Manage Members'),
                subtitle: Text('$activeMemberCount active member(s)'),
                onTap: () => Navigator.of(context).pop('members'),
              ),
              ListTile(
                enabled: canSend,
                leading: const Icon(Icons.send_outlined),
                title: const Text('Send Message'),
                subtitle: Text(
                  !isActive
                      ? 'This list is inactive'
                      : activeMemberCount == 0
                          ? 'Add members before sending'
                          : 'Send an app message, email, or both',
                ),
                onTap: canSend
                    ? () => Navigator.of(context).pop('message')
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit List'),
                onTap: () => Navigator.of(context).pop('edit'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;

    if (action == 'members') {
      await _openMembers(list);
    } else if (action == 'message') {
      await _openMessage(list);
    } else if (action == 'edit') {
      await _showListDialog(existing: list);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.clubName} Mailing Lists'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _saving ? null : () => _showListDialog(),
        icon: const Icon(Icons.add),
        label: const Text('New List'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_lists.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No mailing lists have been created for this club.',
                        ),
                      ),
                    )
                  else
                    for (final list in _lists) ...[
                      Card(
                        child: ListTile(
                          leading: Icon(
                            list['is_active'] == true
                                ? Icons.mark_email_read_outlined
                                : Icons.mark_email_unread_outlined,
                          ),
                          title: Text(
                            list['name']?.toString() ?? 'Unnamed list',
                          ),
                          subtitle: Text(
                            [
                              if ((list['description']?.toString() ?? '')
                                  .trim()
                                  .isNotEmpty)
                                list['description'].toString().trim(),
                              '${_activeMemberCounts[list['id']?.toString()] ?? 0} active member(s)',
                              if (list['allow_self_subscription'] == true)
                                'Members may join or leave',
                              if (list['is_active'] != true) 'Inactive',
                            ].join('\n'),
                          ),
                          isThreeLine:
                              (list['description']?.toString() ?? '')
                                  .trim()
                                  .isNotEmpty,
                          trailing: IconButton(
                            tooltip: 'List options',
                            onPressed: () => _showActions(list),
                            icon: const Icon(Icons.more_vert),
                          ),
                          onTap: () => _openMembers(list),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}
