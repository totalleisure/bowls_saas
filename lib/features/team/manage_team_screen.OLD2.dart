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
  bool _loading = true;
  String? _error;
  bool _canTeamAdmin = false; // club admin or superuser

  String? _selectionId;
  String _status = 'draft';

  List<Map<String, dynamic>> _pool = [];      // RSVP yes/maybe
  List<Map<String, dynamic>> _selected = [];  // team_selection_members

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
      await _loadCanTeamAdmin(fixtureId);

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
          .select('id, member_profile_id, role, acceptance, member_profiles(display_name, phone)')
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

  Map<String, dynamic>? _selectedRowFor(String memberId) {
    final rows = _selected.where((r) => r['member_profile_id'] == memberId).toList();
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _loadCanTeamAdmin(String clubId) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _canTeamAdmin = false);
        return;
      }

      // Map auth user -> member_profile_id
      final mp = await Supabase.instance.client
          .from('member_profiles')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      final memberProfileId = mp?['id']?.toString();

      bool isAdmin = false;
      if (memberProfileId != null) {
        final cm = await Supabase.instance.client
            .from('club_memberships')
            .select('role')
            .eq('club_id', clubId)
            .eq('member_profile_id', memberProfileId)
            .maybeSingle();

        isAdmin = cm != null && cm['role'] == 'admin';
      }

      final su = await Supabase.instance.client
          .from('app_superusers')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();

      final isSuper = su != null;

      if (!mounted) return;
      setState(() => _canTeamAdmin = isAdmin || isSuper);
    } catch (_) {
      if (!mounted) return;
      setState(() => _canTeamAdmin = false);
    }
  }

  Future<void> _teamAdminSetAcceptance(String teamSelectionMemberId, String acceptance) async {
    try {
      await Supabase.instance.client.rpc('team_admin_set_acceptance', params: {
        'p_team_selection_member_id': teamSelectionMemberId,
        'p_acceptance': acceptance,
      });

      await _load(); // refresh screen data
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update acceptance failed: $e')),
      );
    }
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
                        final selectionMemberRowId = s['id'].toString();
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
                              onSelected: (v) async {
                                if (v == 'player' || v == 'reserve') {
                                  await _setRole(memberId, v);
                                  return;
                                }
                                if (!_canTeamAdmin) return;

                                if (v == 'admin_accept') {
                                  await _teamAdminSetAcceptance(selectionMemberRowId, 'accepted');
                                } else if (v == 'admin_pending') {
                                  await _teamAdminSetAcceptance(selectionMemberRowId, 'pending');
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'player', child: Text('Make player')),
                                const PopupMenuItem(value: 'reserve', child: Text('Make reserve')),
                                if (_canTeamAdmin) const PopupMenuDivider(),
                                if (_canTeamAdmin)
                                  const PopupMenuItem(
                                    value: 'admin_accept',
                                    child: Text('Team Admin Accept'),
                                  ),
                                if (_canTeamAdmin)
                                  const PopupMenuItem(
                                    value: 'admin_pending',
                                    child: Text('Team Admin Reverse to Pending'),
                                  ),
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


