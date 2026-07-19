import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MemberMailingListsScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const MemberMailingListsScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<MemberMailingListsScreen> createState() =>
      _MemberMailingListsScreenState();
}

class _MemberMailingListsScreenState extends State<MemberMailingListsScreen> {
  bool _loading = true;
  String? _savingListId;
  String? _error;
  List<Map<String, dynamic>> _lists = [];

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
      final result = await Supabase.instance.client.rpc(
        'my_self_subscribable_mailing_lists',
        params: {'p_club_id': widget.clubId},
      );

      if (!mounted) return;

      setState(() {
        _lists = List<Map<String, dynamic>>.from(result as List);
        _loading = false;
        _savingListId = null;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
        _savingListId = null;
      });
    }
  }

  Future<void> _setMembership(Map<String, dynamic> list, bool join) async {
    final listId = list['mailing_list_id']?.toString() ?? '';
    if (listId.isEmpty || _savingListId != null) return;

    setState(() {
      _savingListId = listId;
      _error = null;
    });

    try {
      await Supabase.instance.client.rpc(
        'set_my_mailing_list_membership',
        params: {'p_mailing_list_id': listId, 'p_join': join},
      );

      if (!mounted) return;

      setState(() {
        final index = _lists.indexWhere(
          (row) => row['mailing_list_id']?.toString() == listId,
        );
        if (index >= 0) {
          _lists[index] = {..._lists[index], 'is_joined': join};
        }
        _savingListId = null;
      });

      final listName = list['name']?.toString() ?? 'the list';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            join ? 'You have joined $listName.' : 'You have left $listName.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _savingListId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Volunteer Lists'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _savingListId != null ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.clubName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Choose the club mailing and volunteer lists you '
                            'wish to join. You can leave a list at any time.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Card(
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
                  ],
                  const SizedBox(height: 12),
                  if (_lists.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'There are currently no lists that members may '
                          'join themselves.',
                        ),
                      ),
                    )
                  else
                    for (final list in _lists) ...[
                      Card(
                        child: SwitchListTile(
                          secondary: const Icon(Icons.groups_outlined),
                          title: Text(
                            list['name']?.toString() ?? 'Unnamed list',
                          ),
                          subtitle: Text(
                            (list['description']?.toString() ?? '').trim(),
                          ),
                          value: list['is_joined'] == true,
                          onChanged: _savingListId == null
                              ? (value) => _setMembership(list, value)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            ),
    );
  }
}
