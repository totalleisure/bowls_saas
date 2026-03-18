import '../../core/widgets/app_badge.dart';
import '../clubs/club_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';
import 'captain_view_section.dart';
import 'set_captain_section.dart';
import '../team/team_section.dart';
import '../team/manage_team_screen.dart';
import '../rinks/rinks_setup_screen.dart';
import '../rinks/rink_assignments_screen.dart';

class FixtureDetailsPage extends StatefulWidget {
  final String fixtureId;
  const FixtureDetailsPage({super.key, required this.fixtureId});

  @override
  State<FixtureDetailsPage> createState() => _FixtureDetailsPageState();
}

class _FixtureDetailsPageState extends State<FixtureDetailsPage> {

  int _loadCount = 0;
  bool isAdmin = false;
  bool isSuper = false;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _fixture;

  // Team name editing
  final TextEditingController _teamNameCtrl = TextEditingController();
  bool _savingTeamName = false;
  bool _teamNameLocked = true;

  // Team fixtures: allow choosing a team (else free-text fixture label)
  List<Map<String, dynamic>> _teams = [];
  String? _selectedTeamId;
  bool _savingTeam = false;
  bool _isTeamFixtureUi = false;


  final _client = Supabase.instance.client;
  bool _canDelete = false;

Future<void> _loadTeamNameLocked() async {
  final client = Supabase.instance.client;

  // 1) Any RSVPs for this fixture?
  final rsvps = await client
      .from('fixture_rsvps')
      .select('id')
      .eq('fixture_id', widget.fixtureId);

  // 2) Any rink assignments for this fixture?
  final rinkAssignments = await client
      .from('fixture_rink_assignments')
      .select('id')
      .eq('fixture_id', widget.fixtureId);

  final locked =
      (rsvps as List).isNotEmpty || (rinkAssignments as List).isNotEmpty;

  if (!mounted) return;
  setState(() => _teamNameLocked = locked);
}

  Future<void> _load() async {
    _loadCount++;
    print('FixtureDetails _load() count=$_loadCount id=${widget.fixtureId}');    
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final f = await Supabase.instance.client
          .from('fixtures')
          .select(
            'id, club_id, start_at, is_home, section, rinks_required, players_per_rink, orientation, team_id, team_name, '
            'captain_member_profile_id, vice_captain_member_profile_id, '
            'team:teams!fixtures_team_id_fkey(name), '
            'venue:venues!fixtures_venue_id_fkey(name), '
            'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
            'green_areas(name, discipline, orientation_mode), '
            'captain:member_profiles!fixtures_captain_member_profile_id_fkey(display_name), '
            'vice:member_profiles!fixtures_vice_captain_member_profile_id_fkey(display_name)'
          )
          .eq('id', widget.fixtureId)
          .single();

      if (!mounted) return;
        setState(() {
          _fixture = Map<String, dynamic>.from(f);
          _teamNameCtrl.text = (_fixture?['team_name'] ?? '').toString();
          _selectedTeamId = _fixture?['team_id']?.toString();
          _isTeamFixtureUi = _selectedTeamId != null;
          _loading = false;
        });

        // run post-load checks
        await _loadCanDelete();
        await _loadTeamNameLocked();
        await _loadTeams();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }


  Future<void> _loadTeams() async {
    final clubId = _fixture?['club_id']?.toString();
    if (clubId == null) return;

    try {
      final rows = await Supabase.instance.client
          .from('teams')
          .select('id, name, is_active')
          .eq('club_id', clubId)
          .eq('is_active', true)
          .order('name');

      if (!mounted) return;
      setState(() {
        _teams = List<Map<String, dynamic>>.from(rows);
        _selectedTeamId ??= _fixture?['team_id']?.toString();
        if (_selectedTeamId == null && _teams.isNotEmpty && (_fixture?['team_id'] != null)) {
          _selectedTeamId = _teams.first['id'].toString();
        }
      });
    } catch (_) {}
  }

  String? _myRsvp; // 'yes' | 'maybe' | 'no' | null

  String _formatLabel(int p) {
    if (p == 2) return 'Pairs';
    if (p == 3) return 'Triples';
    return 'Rinks';
  }

  @override
  void initState() {
    super.initState();
    _load();
    _loadMyRsvp();
  }

  @override
  void dispose() {
    _teamNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCanDelete() async {
//    debugPrint('_loadCanDelete() called');
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _canDelete = false);
        return;
      }

      // Get my member_profile_id
      final mp = await _client
          .from('member_profiles')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      final myProfileId = mp?['id']?.toString();
      if (myProfileId == null) {
        if (mounted) setState(() => _canDelete = false);
        return;
      }
//      debugPrint('myProfileID <> null');

      // Get this fixture's club_id (already loaded in _fixture after _load())
      final clubId = _fixture?['club_id']?.toString();
      if (clubId == null) {
        if (mounted) setState(() => _canDelete = false);
        return;
      }
//      debugPrint('clubId: $clubId');

      // Club admin?
      final adminRow = await _client
          .from('club_memberships')
          .select('id')
          .eq('club_id', clubId)
          .eq('member_profile_id', myProfileId)
          .eq('role', 'admin')
          .maybeSingle();

      final adminFlag = adminRow != null;

      if (mounted) {
        setState(() {
          isAdmin = adminFlag;          // class field
          _canDelete = adminFlag || isSuper;
        });
      }
//      debugPrint('isAdmin value 1 : $isAdmin');

// Superuser? (if you have this table)
      
      try {
        final suRow = await _client
            .from('app_superusers')
            .select('*')
            .eq('user_id', userId)
            .maybeSingle();
        isSuper = suRow != null;
        if (mounted) {
          setState(() {
            isAdmin = adminFlag;
            _canDelete = adminFlag || isSuper;
          });
        }        
      } catch (e) {
      debugPrint('Looks like theres an error: $e');
      }
//      debugPrint('isAdmin value 2 : $isAdmin');
      if (mounted) setState(() => _canDelete = isAdmin || isSuper);
    } catch (_) {
      if (mounted) setState(() => _canDelete = false);
    }

    debugPrint('isAdmin value 2 : $isAdmin');
    debugPrint('isSuper value 2 : $isSuper');
    debugPrint('_canDekete      : $_canDelete');
  }  
  
  Future<void> _confirmAndDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete fixture?'),
        content: const Text(
          'This will delete the fixture and all associated data (RSVPs, rinks, assignments, selections).\n\n'
          'You cannot delete a fixture if any player has accepted selection.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);

    try {
      await _client.rpc('delete_fixture', params: {
        'p_fixture_id': widget.fixtureId,
      });

      if (!mounted) return;
      Navigator.pop(context, true); // tell previous screen to refresh
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: $e')),
      );
    }
  }

  Future<void> _setRsvp(String status, String label) async {
    final previous = _myRsvp;

    // Update UI immediately
    setState(() => _myRsvp = status);

    try {
      final client = Supabase.instance.client;
      final fixtureId = widget.fixtureId;

      final myId = (await client.rpc('my_member_profile_id')).toString();

      await client.from('fixture_rsvps').upsert({
        'fixture_id': fixtureId,
        'member_profile_id': myId,
        'status': status,
        'responded_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'fixture_id,member_profile_id');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('RSVP set to $label')),
      );
    } catch (e) {
      // Revert highlight if DB write fails
      if (mounted) {
        setState(() => _myRsvp = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('RSVP error: $e')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _myRsvp = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('RSVP error: $e')),
        );
      }
    }

    await _loadMyRsvp();
  }

  Future<void> _loadMyRsvp() async {
    try {
      final client = Supabase.instance.client;
      final fixtureId = widget.fixtureId;
      final myId = (await client.rpc('my_member_profile_id')).toString();

      final row = await client
          .from('fixture_rsvps')
          .select('status')
          .eq('fixture_id', fixtureId)
          .eq('member_profile_id', myId)
          .maybeSingle();

      if (!mounted) return;
      setState(() => _myRsvp = row?['status'] as String?);
    } catch (_) {
      // ignore load errors for now (no highlight is fine)
    }
  }

  Widget _rsvpChoiceButton(String status, String label) {
    final isSelected = _myRsvp == status;

    return ElevatedButton(
      style: isSelected
          ? ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
      onPressed: () => _setRsvp(status, label),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Fixture details'),
          actions: [
            if (_canDelete)
              IconButton(
                tooltip: 'Delete fixture',
                icon: const Icon(Icons.delete_outline),
                onPressed: _confirmAndDelete,
              ),
          ],
        ),
      );
    }

    final fixtureLabel = (_fixture?['team_name'] ?? '').toString().trim();

    final teamRow = _fixture?['team'] as Map<String, dynamic>?;
    final teamName = (teamRow?['name'] ?? '').toString().trim();
    final isTeamFixture = _isTeamFixtureUi;

    final fixture = _fixture!;
    final startAt = fixture['start_at'] as String?;
    final when = startAt != null
        ? DateTime.parse(startAt).toLocal()
        : DateTime.now();

    final venue = (fixture['venue']?['name'] as String?) ?? '';
    final opponent = (fixture['opponent_venue']?['name'] as String?) ?? '';
    final green = (fixture['green_areas']?['name'] as String?) ?? '';

    final isHome = (fixture['is_home'] as bool?) ?? true;
    final section = (fixture['section'] as String?) ?? '';
    
    final rinks = (fixture['rinks_required'] as int?) ?? 0;
    final ppr = (fixture['players_per_rink'] as int?) ?? 4;

    final orientation = fixture['orientation'] as String?;
    final ga = fixture['green_areas'] as Map<String, dynamic>?;
    final greenDiscipline = ga?['discipline'] as String?;
    final greenOrientationMode = ga?['orientation_mode'] as String?;

    final showOrientation =
        isHome && greenDiscipline == 'outdoor' && greenOrientationMode != 'not_applicable';

    final captainName = (fixture['captain']?['display_name'] as String?) ?? '';
    final viceName = (fixture['vice']?['display_name'] as String?) ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fixture details'),
        actions: [
          if (_canDelete)
            IconButton(
              tooltip: 'Delete fixture',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmAndDelete, // make sure this method exists
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            green.isEmpty ? venue : '$venue — $green',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppBadge(text: isHome ? 'HOME' : 'AWAY'),
              if (isTeamFixture && teamName.isNotEmpty)
                AppBadge(text: 'TEAM: $teamName')
              else if (!isTeamFixture && fixtureLabel.isNotEmpty)
                AppBadge(text: 'DETAILS: $fixtureLabel'),
              if (captainName.isNotEmpty) AppBadge(text: 'CAPT: $captainName'),
              if (viceName.isNotEmpty) AppBadge(text: 'VICE: $viceName'),

              AppBadge(text: section.toUpperCase()),
              AppBadge(text: _formatLabel(ppr).toUpperCase()),
              AppBadge(text: '$rinks RINKS'),
              if (showOrientation)
                AppBadge(text: ('ORIENT: ${orientation ?? 'NOT SET'}').toUpperCase()),
            ],
          ),
          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isTeamFixture ? 'Team' : 'Fixture details',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Team fixture'),
                    subtitle: const Text('If on, this fixture uses a team and team workflows'),
                    value: isTeamFixture,
                    onChanged: _teamNameLocked
                        ? null
                        : (v) {
                            setState(() {
                              _isTeamFixtureUi = v;
                              if (v) {
                                _selectedTeamId ??= _teams.isNotEmpty ? _teams.first['id'].toString() : null;
                                _teamNameCtrl.text = '';
                              } else {
                                _selectedTeamId = null;
                              }
                            });
                          },
                  ),

                  if (isTeamFixture) ...[
                    DropdownButtonFormField<String>(
                      value: _selectedTeamId,
                      decoration: InputDecoration(
                        hintText: _teamNameLocked
                            ? 'Locked (RSVPs/assignments exist)'
                            : 'Select a team',
                        border: const OutlineInputBorder(),
                      ),
                      items: _teams.map((t) {
                        return DropdownMenuItem(
                          value: t['id'].toString(),
                          child: Text(t['name'].toString()),
                        );
                      }).toList(),
                      onChanged: _teamNameLocked
                          ? null
                          : (v) => setState(() => _selectedTeamId = v),
                    ),
                  ] else ...[
                    TextField(
                      controller: _teamNameCtrl,
                      enabled: !_teamNameLocked,
                      decoration: InputDecoration(
                        hintText: _teamNameLocked
                            ? 'Locked (RSVPs/assignments exist)'
                            : 'Enter fixture details (optional)',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: (_savingTeam || _teamNameLocked)
                          ? null
                          : () async {
                              setState(() => _savingTeam = true);
                              try {
                                if (isTeamFixture) {
                                  if (_selectedTeamId == null) {
                                    throw Exception('Please select a team.');
                                  }
                                  await Supabase.instance.client
                                      .from('fixtures')
                                      .update({
                                        'team_id': _selectedTeamId,
                                        'team_name': null,
                                      })
                                      .eq('id', widget.fixtureId);
                                } else {
                                  final lbl = _teamNameCtrl.text.trim();
                                  await Supabase.instance.client
                                      .from('fixtures')
                                      .update({
                                        'team_id': null,
                                        'team_name': lbl.isEmpty ? null : lbl,
                                      })
                                      .eq('id', widget.fixtureId);
                                }

                                await _load();
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to save: $e')),
                                );
                              } finally {
                                if (mounted) setState(() => _savingTeam = false);
                              }
                            },
                      child: _savingTeam
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: const Text('Start time'),
              subtitle: Text(startAt != null ? formatWhenLocal(startAt) : ''),
            ),
          ),

          SetCaptainSection(fixture: fixture),
          const SizedBox(height: 16),

          const SizedBox(height: 24),
          Text('Your availability', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              _rsvpChoiceButton('yes', 'Yes'),
              _rsvpChoiceButton('maybe', 'Maybe'),
              _rsvpChoiceButton('no', 'No'),
            ],
          ),

          const SizedBox(height: 24),
          TeamSection(fixture: fixture),

          const SizedBox(height: 24),
          CaptainViewSection(fixture: fixture),
        ],
      ),
    );
  }
}


