import '../rinks/rinks_setup_screen.dart';
import '../rinks/rink_assignments_screen.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

class ManageTeamScreen extends StatefulWidget {
  final Map<String, dynamic> fixture;
  const ManageTeamScreen({super.key, required this.fixture});

  @override
  State<ManageTeamScreen> createState() => _ManageTeamScreenState();
}

class _ManageTeamScreenState extends State<ManageTeamScreen> {

  final _client = Supabase.instance.client;
  
  bool _loading = true;
  String? _error;

  String? _selectionId;
  String _status = 'draft';

  List<Map<String, dynamic>> _pool = [];      // RSVP yes/maybe
  List<Map<String, dynamic>> _selected = [];  // team_selection_members

  bool _canManage = false; // club admin or superuser
  List<Map<String, dynamic>> _clubMembers = []; // for Add Member dialog
 
  @override
  void initState() {
    super.initState();
    _load();
  }

  String _buildPublishedTeamMessage() {
    final fixture = widget.fixture;

    final when = DateTime.parse(fixture['start_at'] as String).toLocal();
    final isHome = fixture['is_home'] as bool;

    final venue = (fixture['venue']?['name'] as String?) ?? '';    
    final opponent = (fixture['opponent_name'] as String?) ?? ''; // if you have it; else blank
    final homeAway = isHome ? 'Home' : 'Away';

    String fmtName(Map<String, dynamic> r) {
      final mp = r['member_profiles'] as Map<String, dynamic>?;
      return (mp?['display_name'] as String?) ?? '(no name)';
    }

    final players = _selected.where((s) => s['role'] == 'player').toList();
    final reserves = _selected.where((s) => s['role'] == 'reserve').toList();

    String line(Map<String, dynamic> r, int i) {
      final name = fmtName(r);
      final acc = (r['acceptance']?.toString() ?? 'pending').toUpperCase();
      return '${i + 1}. $name ($acc)';
    }

    final sb = StringBuffer();
    sb.writeln('Team published');
    sb.writeln('${when.toString()} • $homeAway');
    if (venue.isNotEmpty) sb.writeln('Venue: $venue');
    if (!isHome && opponent.isNotEmpty) sb.writeln('Opponent: $opponent');
    sb.writeln('');

    sb.writeln('Players:');
    for (var i = 0; i < players.length; i++) {
      sb.writeln(line(players[i], i));
    }

    sb.writeln('');
    sb.writeln('Reserves:');
    if (reserves.isEmpty) {
      sb.writeln('None');
    } else {
      for (var i = 0; i < reserves.length; i++) {
        sb.writeln('R${i + 1}. ${fmtName(reserves[i])} (${(reserves[i]['acceptance']?.toString() ?? 'pending').toUpperCase()})');
      }
    }

    sb.writeln('');
    sb.writeln('Please confirm acceptance in the app.');

    return sb.toString();
  }


  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final fixtureId = widget.fixture['id'] as String;
      await _loadCanManage();

      // get or create selection
      final existing = await client
          .from('team_selections')
          .select('id, status')
          .eq('fixture_id', fixtureId)
          .maybeSingle();

      if (existing == null) {
        final created = await client
            .from('team_selections')
            .insert({'fixture_id': fixtureId})
            .select('id, status')
            .single();

        _selectionId = created['id'] as String;
        _status = created['status'].toString();
      } else {
        _selectionId = existing['id'] as String;
        _status = existing['status'].toString();
      }

      // pool: RSVPs yes/maybe
      final poolRows = await client
          .from('fixture_rsvps')
          .select('member_profile_id, status, member_profiles(display_name, phone)')
          .eq('fixture_id', fixtureId)
          .inFilter('status', ['yes', 'maybe']);

      _pool = List<Map<String, dynamic>>.from(poolRows);

      // current selected
      final selRows = await client
          .from('team_selection_members')
          .select('member_profile_id, role, acceptance, member_profiles(display_name, phone)')
          .eq('team_selection_id', _selectionId!)
          .order('created_at');

      _selected = List<Map<String, dynamic>>.from(selRows);

      // sort pool by name
      _pool.sort((a, b) {
        final an = (a['member_profiles']?['display_name'] as String?) ?? '';
        final bn = (b['member_profiles']?['display_name'] as String?) ?? '';
        return an.compareTo(bn);
      });

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadCanManage() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _canManage = false);
        return;
      }

      final clubId = (widget.fixture['club_id'] ?? widget.fixture['clubId'] ?? '').toString();
      if (clubId.isEmpty) {
        if (mounted) setState(() => _canManage = false);
        return;
      }

      // superuser?
      final su = await _client
          .from('app_superusers')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();
      if (su != null) {
        if (mounted) setState(() => _canManage = true);
        return;
      }

      // map auth user -> member_profile_id
      final mp = await _client
          .from('member_profiles')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      final memberProfileId = mp?['id']?.toString();
      if (memberProfileId == null) {
        if (mounted) setState(() => _canManage = false);
        return;
      }

      // club admin?
      final cm = await _client
          .from('club_memberships')
          .select('role')
          .eq('club_id', clubId)
          .eq('member_profile_id', memberProfileId)
          .maybeSingle();

      final isAdmin = cm != null && cm['role'] == 'admin';
      if (mounted) setState(() => _canManage = isAdmin);
    } catch (_) {
      if (mounted) setState(() => _canManage = false);
    }
  }

  Future<void> _loadClubMembers() async {
    final clubId = (widget.fixture['club_id'] ?? widget.fixture['clubId'] ?? '').toString();
    if (clubId.isEmpty) return;

    final rows = await _client
        .from('club_memberships')
        .select('member_profile_id, member_profiles(first_name,last_name)')
        .eq('club_id', clubId);

    final members = <Map<String, dynamic>>[];
    for (final r in (rows as List)) {
      final mp = r['member_profiles'] as Map<String, dynamic>?;
      final first = (mp?['first_name'] ?? '').toString();
      final last = (mp?['last_name'] ?? '').toString();
      final name = ('$first $last').trim();
      members.add({
        'member_profile_id': r['member_profile_id']?.toString(),
        'display_name': name.isEmpty ? r['member_profile_id']?.toString() : name,
      });
    }
    members.sort((a,b)=> (a['display_name'] as String).compareTo(b['display_name'] as String));

    if (mounted) setState(() => _clubMembers = members);
  }

  Future<void> _loadCanAddMembers() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      _canManage = false;
      return;
    }

    // get my member_profile_id
    final mp = await _client
        .from('member_profiles')
        .select('id')
        .eq('user_id', userId)
        .maybeSingle();

    final myProfileId = mp?['id']?.toString();
    if (myProfileId == null) {
      _canManage = false;
      return;
    }

    // check club admin
    final adminRow = await _client
        .from('club_memberships')
        .select('id')
        .eq('club_id', widget.fixture['club_id'].toString())
        .eq('member_profile_id', myProfileId)
        .eq('role', 'admin')
        .maybeSingle();

    final isAdmin = adminRow != null;

    // check superuser (table must exist)
    final suRow = await _client
        .from('app_superusers')
        .select('id')
        .eq('user_id', userId)
        .maybeSingle();

    final isSuper = suRow != null;

    _canManage = isAdmin || isSuper;
  }

  Future<void> _showAddMemberDialog() async {
    if (!_canManage) return;

    await _loadClubMembers();
    if (!mounted) return;

    String? selectedMemberProfileId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add member to fixture'),
          content: SizedBox(
            width: 420,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Member'),
              items: _clubMembers
                  .where((m) => (m['member_profile_id'] ?? '') != '')
                  .map((m) => DropdownMenuItem<String>(
                        value: m['member_profile_id'] as String,
                        child: Text(m['display_name'] as String),
                      ))
                  .toList(),
              onChanged: (v) => selectedMemberProfileId = v,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add as pending')),
          ],
        );
      },
    );

    if (ok != true) return;
    if (selectedMemberProfileId == null || selectedMemberProfileId!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a member.')));
      }
      return;
    }

    if (_selectionId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Team selection not ready yet.')));
      }
      return;
    }

    try {
      await _client.rpc('team_admin_add_member', params: {
        'p_team_selection_id': _selectionId,
        'p_member_profile_id': selectedMemberProfileId,
      });
      await _loadCanManage();
      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added as pending.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Add failed: $e')));
      }
    }
  }


  Map<String, dynamic>? _selectedRowFor(String memberId) {
    final rows = _selected.where((r) => r['member_profile_id'] == memberId).toList();
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _togglePlayer(String memberId) async {
    if (_selectionId == null) return;
    final client = Supabase.instance.client;

    final existing = _selectedRowFor(memberId);
    try {
      if (existing == null) {
        await client.from('team_selection_members').insert({
          'team_selection_id': _selectionId,
          'member_profile_id': memberId,
          'role': 'player',
          'acceptance': 'pending',
        });
      } else {
        await client
            .from('team_selection_members')
            .delete()
            .eq('team_selection_id', _selectionId!)
            .eq('member_profile_id', memberId);
      }

      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update team error: $e')),
      );
    }
  }

  Future<void> _setRole(String memberId, String role) async {
    if (_selectionId == null) return;
    try {
      await Supabase.instance.client
          .from('team_selection_members')
          .update({'role': role})
          .eq('team_selection_id', _selectionId!)
          .eq('member_profile_id', memberId);

      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Set role error: $e')),
      );
    }
  }

  Future<void> _publish() async {
    if (_selectionId == null) return;
    try {
      final client = Supabase.instance.client;
      final myId = (await client.rpc('my_member_profile_id')).toString();

      await client
          .from('team_selections')
          .update({
            'status': 'published',
            'published_at': DateTime.now().toUtc().toIso8601String(),
            'published_by_member_profile_id': myId,
          })
          .eq('id', _selectionId!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Team published')),
        );
      }
      await _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Publish error: $e')),
      );
    }
  }

  Widget _poolRow(Map<String, dynamic> r) {
    final memberId = r['member_profile_id'] as String;
    final mp = r['member_profiles'] as Map<String, dynamic>?;
    final name = (mp?['display_name'] as String?) ?? '(no name)';
    final rsvp = r['status']?.toString() ?? '';

    final sel = _selectedRowFor(memberId);
    final isSelected = sel != null;
    final role = sel?['role']?.toString();

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: isSelected ? const Icon(Icons.check, size: 18) : const SizedBox(width: 18),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(isSelected ? '${role ?? ''} • RSVP: $rsvp' : 'RSVP: $rsvp'),
      onTap: () => _togglePlayer(memberId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPublished = _status == 'published';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage team'),
        actions: [
          if (_canManage)
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Add member',
              onPressed: () async {
                // 1) Not allowed -> show why
                if (!_canManage) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Only Club Admins / SuperUsers can add members.')),
                  );
                  return;
                }

                // 2) Ensure we have the data needed
                if (_selectionId == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Team selection not loaded yet. Try again in a moment.')),
                  );
                  return;
                }

                // 3) If club members list not loaded yet, load it now
                if (_clubMembers.isEmpty) {
                  setState(() => _loading = true);
                  try {
                    await _loadClubMembers(); // you should already have this method; if not, see Step 4 below
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to load club members: $e')),
                    );
                    return;
                  } finally {
                    if (mounted) setState(() => _loading = false);
                  }
                }

                // 4) Now show dialog
                await _showAddMemberDialog();
              },
            ),
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

                    ElevatedButton.icon(
                      onPressed: _selectionId == null
                          ? null
                          : () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RinksSetupScreen(
                                    fixtureId: widget.fixture['id'].toString(),
                                    isHome: widget.fixture['is_home'] == true,
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.grid_view),
                      label: const Text('Rinks setup'),
                    ),

                    ElevatedButton.icon(
                      onPressed: _selectionId == null
                          ? null
                          : () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RinkAssignmentsScreen(
                                    fixtureId: widget.fixture['id'].toString(),
                                    teamSelectionId: _selectionId!,
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.groups),
                      label: const Text('Assign rinks & positions'),
                    ),
                    const SizedBox(height: 12),
                    
                    const SizedBox(height: 12),

                    Card(
                      child: ListTile(
                        title: Text(isPublished ? 'Status: Published' : 'Status: Draft'),
                        subtitle: const Text('Tap members to add/remove as players.'),
                      ),
                    ),

                    if (!isPublished) ...[
                      ElevatedButton(
                        onPressed: _publish,
                        child: const Text('Publish team'),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final msg = _buildPublishedTeamMessage();
                                await Clipboard.setData(ClipboardData(text: msg));
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Team message copied')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                final msg = _buildPublishedTeamMessage();
                                Share.share(msg);
                              },
                              icon: const Icon(Icons.share),
                              label: const Text('Share'),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 16),
                    Text('Selected',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),

                    if (_selected.isEmpty)
                      const Text('No one selected yet.')
                    else
                      ..._selected.map((s) {
                        final memberId = s['member_profile_id'] as String;
                        final mp = s['member_profiles'] as Map<String, dynamic>?;
                        final name = (mp?['display_name'] as String?) ?? '(no name)';
                        final role = s['role']?.toString() ?? 'player';
                        final acceptance = s['acceptance']?.toString() ?? 'pending';

                        Color bgColor;
                        if (acceptance == 'accepted') {
                          bgColor = const Color(0xFFE8F5E9); // soft green
                        } else if (acceptance == 'declined') {
                          bgColor = const Color(0xFFFFEBEE); // soft red
                        } else {
                          bgColor = const Color(0xFFFFF8E1); // soft amber
                        }

                        return Card(
                          color: bgColor,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text('Role: $role • $acceptance'),
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) => _setRole(memberId, v),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'player', child: Text('Make player')),
                                PopupMenuItem(value: 'reserve', child: Text('Make reserve')),
                              ],
                            ),
                          ),
                        );
                      }
                    ),
                    const SizedBox(height: 16),
                    Text('RSVP pool (Yes/Maybe)',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ..._pool.map(_poolRow),
                  ],
                ),
    );
  }
}


