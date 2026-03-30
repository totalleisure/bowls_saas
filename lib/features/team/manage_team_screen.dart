import '../rinks/rinks_setup_screen.dart';
import '../rinks/rink_assignments_screen.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

import '../../Core/widgets/app_badge.dart';

import 'package:bowls_saas/Services/team_sheet_pdf.dart';
import 'package:bowls_saas/Services/team_sheet_share.dart';
import 'package:bowls_saas/Services/team_sheet_service.dart';

class ManageTeamScreen extends StatefulWidget {
  final Map<String, dynamic> fixture;
  final bool readOnly;

  const ManageTeamScreen({
    super.key, 
    required this.fixture,
    this.readOnly = false,
    });

  @override
  State<ManageTeamScreen> createState() => _ManageTeamScreenState();
}

class _ManageTeamScreenState extends State<ManageTeamScreen> {

  final _client = Supabase.instance.client;
  
  bool _loading = true;
  String? _error;

  bool _isTeamFixture = false;
  bool _usesRsvpPool = false;

  String? _selectionId;
  String _status = 'draft';

  List<Map<String, dynamic>> _pool = [];        // RSVP yes/maybe
  List<Map<String, dynamic>> _selected = [];    // team_selection_members

  bool _checkingPermissions = true;

  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  bool _isSelector = false;
  bool _isFixtureCaptain = false;
  bool _isFixtureViceCaptain = false;

  bool _canEditSelection = false;
  bool _canAssignRinks = false;
  bool _canEditRinkSetup = false;
  bool _canPublish = false;
  bool _canForceAccept = false;
  bool _canAddPeople = false;

  bool get effectiveReadOnly => widget.readOnly || !_canEditSelection;

  List<Map<String, dynamic>> _clubMembers = []; // for Add Member dialog
 
  String? _currentMemberProfileId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadUserPermissions();
    await _load();
  }

  Future<String?> _myMemberProfileId() async {
    try {
      final id = await _client.rpc('my_member_profile_id');
      return id?.toString();
    } catch (_) {
      return null;
    }
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
      final teamId = widget.fixture['team_id']?.toString(); // null for non-team fixtures

      debugPrint('ManageTeam: fixtureId=${widget.fixture['id']} teamId=$teamId requiresRsvp=${widget.fixture['requires_rsvp']}');

      final requiresRsvp = widget.fixture['requires_rsvp'] == true;  
      final clubId = widget.fixture['club_id']?.toString();

      _isTeamFixture = teamId != null;
      _usesRsvpPool = !_isTeamFixture && requiresRsvp;

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

      if (fixtureId == null || clubId == null) {
        throw Exception('Fixture missing id/club_id');
      }

      debugPrint('MANAGE_TEAM fixtureId=$fixtureId clubId=$clubId teamId=$teamId requiresRsvp=$requiresRsvp');
      
      // 1) Load candidates (pool)
      List<Map<String, dynamic>> candidates = [];

      if (teamId != null) {
        // 1) Team fixture -> pick from team pool
        final rows = await client
            .from('team_members')
            .select('member_profile_id, member_profiles(id, display_name, phone)')
            .eq('team_id', teamId)
            .eq('is_active', true);

        candidates = List<Map<String, dynamic>>.from(rows);
        debugPrint('MANAGE_TEAM branch: team_members');
      } else if (requiresRsvp) {
        // 2) RSVP fixture -> only members who said yes/maybe
        final rows = await client
            .from('fixture_rsvps')
            .select('member_profile_id, status, member_profiles(id, display_name, phone)')
            .eq('fixture_id', fixtureId)
            .inFilter('status', ['yes', 'maybe']);

        final roleByMemberId = <String, String>{};

        if (_selectionId != null) {
          final roleRows = await client
              .from('team_selection_members')
              .select('member_profile_id, role')
              .eq('team_selection_id', _selectionId!);

          for (final r in (roleRows as List)) {
            final memberId = r['member_profile_id']?.toString() ?? '';
            final role = (r['role'] ?? 'player').toString().toLowerCase().trim();
            if (memberId.isNotEmpty) {
              roleByMemberId[memberId] = role;
            }
          }
        }

        candidates = List<Map<String, dynamic>>.from(rows).map((r) {
          final memberId = r['member_profile_id']?.toString() ?? '';
          return {
            ...r,
            'role': roleByMemberId[memberId] ?? 'player',
            'rsvp_status': r['status'],
          };
        }).toList();

        debugPrint('MANAGE_TEAM branch: fixture_rsvps yes/maybe');
        debugPrint('MANAGE_TEAM roleByMemberId=$roleByMemberId');
      } else {
        // 3) Non-team, no-RSVP fixture -> all active club members
        final rows = await client
            .from('club_memberships')
            .select('member_profile_id, member_profiles(id, display_name, phone)')
            .eq('club_id', clubId)
            .eq('is_active', true);

        candidates = List<Map<String, dynamic>>.from(rows);
        debugPrint('MANAGE_TEAM branch: club_memberships');
      }

      // 2) Load RSVP overlay (optional)
      final Map<String, String> rsvpByProfileId = {};

      if (teamId != null && teamId.isNotEmpty) {
        final rsvpRows = await client
            .from('fixture_rsvps')
            .select('member_profile_id, status')
            .eq('fixture_id', fixtureId);

        for (final r in rsvpRows) {
          final id = r['member_profile_id']?.toString();
          final st = r['status']?.toString();
          if (id != null && st != null) {
            rsvpByProfileId[id] = st;
          }
        }
      }

      // 3) Attach RSVP status to candidates for UI badges/filters
      for (final c in candidates) {
        final mpId = c['member_profile_id']?.toString();

        // If the candidate row already came from fixture_rsvps, keep that status.
        // Otherwise fall back to the overlay map.
        c['rsvp_status'] =
            c['status']?.toString() ??
            (mpId == null ? null : rsvpByProfileId[mpId]);
      }

      _pool = candidates;

      // current selected
      final selRows = await client
          .from('team_selection_members')
          .select(
            'member_profile_id, role, acceptance, responded_at, acceptance_by, is_selected, '
            'member_profiles!team_selection_members_member_profile_id_fkey(display_name, phone), '
            'accepted_by_profile:member_profiles!team_selection_members_acceptance_by_fkey(display_name)'
          )
          .eq('team_selection_id', _selectionId!)
          .eq('is_selected', true)
          .order('created_at');

      _selected = List<Map<String, dynamic>>.from(selRows);

      debugPrint('MANAGE_TEAM _selected=$_selected');

      for (final s in _selected) {
        debugPrint(
          'MANAGE_TEAM selected member=${s['member_profile_id']} role=${s['role']} is_selected=${s['is_selected']}',
        );
      }      

      // sort pool by name
      int availabilityRank(Map<String, dynamic> r) {
        final s =
            r['rsvp_status']?.toString().toLowerCase() ??
            r['status']?.toString().toLowerCase() ??
            '';

        switch (s) {
          case 'yes':
            return 0; // Available
          case 'maybe':
            return 1; // Maybe
          case '':
            return 2; // No response yet
          case 'no':
            return 3; // Not available
          default:
            return 2;
        }
      }

      _pool.sort((a, b) {
        final ar = availabilityRank(a);
        final br = availabilityRank(b);

        if (ar != br) {
          return ar.compareTo(br);
        }

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

  Future<void> _acceptOnBehalf(String memberId) async {
    if (widget.readOnly || !_canForceAccept) return;
    if (_selectionId == null) return;

    try {
      final actingMemberId = await _myMemberProfileId();
      if (actingMemberId == null || actingMemberId.isEmpty) {
        throw Exception('Could not determine logged-in member profile.');
      }

      await _client
          .from('team_selection_members')
          .update({
            'acceptance': 'accepted',
            'responded_at': DateTime.now().toUtc().toIso8601String(),
            'acceptance_by': actingMemberId,
          })
          .eq('team_selection_id', _selectionId!)
          .eq('member_profile_id', memberId);

      await _load();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Player marked as accepted')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Accept error: $e')),
      );
    }
  }

  Future<void> _loadUserPermissions() async {
    if (mounted) {
      setState(() => _checkingPermissions = true);
    }

    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _isSuperuser = false;
          _isClubAdmin = false;
          _isSelector = false;
          _isFixtureCaptain = false;
          _isFixtureViceCaptain = false;
          _canEditSelection = false;
          _canAssignRinks = false;
          _canEditRinkSetup = false;
          _canPublish = false;
          _canForceAccept = false;
          _canAddPeople = false;
        });
        return;
      }

      final clubId =
          (widget.fixture['club_id'] ?? widget.fixture['clubId'] ?? '').toString();

      final fixtureCaptainId =
          (widget.fixture['captain_member_profile_id'] ?? '').toString();
      final fixtureViceCaptainId =
          (widget.fixture['vice_captain_member_profile_id'] ?? '').toString();

      bool isSuperuser = false;
      bool isClubAdmin = false;
      bool isSelector = false;
      bool isFixtureCaptain = false;
      bool isFixtureViceCaptain = false;

      String? myMemberProfileId;

      final su = await _client
          .from('app_superusers')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();

      isSuperuser = su != null;

      final mp = await _client
          .from('member_profiles')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      myMemberProfileId = mp?['id']?.toString();
      _currentMemberProfileId = myMemberProfileId;

      if (clubId.isNotEmpty && myMemberProfileId != null) {
        final cm = await _client
            .from('club_memberships')
            .select('role, is_active')
            .eq('club_id', clubId)
            .eq('member_profile_id', myMemberProfileId)
            .maybeSingle();

        final isActive = cm?['is_active'] == true;
        final role = (cm?['role'] ?? '').toString().toLowerCase();

        isClubAdmin = isActive && role == 'admin';
        isSelector = isActive && role == 'selector';
      }

      if (myMemberProfileId != null && myMemberProfileId.isNotEmpty) {
        isFixtureCaptain =
            fixtureCaptainId.isNotEmpty && fixtureCaptainId == myMemberProfileId;
        isFixtureViceCaptain =
            fixtureViceCaptainId.isNotEmpty &&
            fixtureViceCaptainId == myMemberProfileId;
      }

      final canEditSelection = isSuperuser ||
          isClubAdmin ||
          isSelector ||
          isFixtureCaptain ||
          isFixtureViceCaptain;

      final canAssignRinks = canEditSelection;

      final canEditRinkSetup = isSuperuser || isClubAdmin || isSelector;

      final canPublish = canEditSelection;
      final canForceAccept = canEditSelection;

      // Keep Add People stricter for now if that is your intention.
      final canAddPeople = isSuperuser || isClubAdmin;

      debugPrint('--- MANAGE_TEAM permissions ---');
      debugPrint('_isSuperuser=$isSuperuser');
      debugPrint('_isClubAdmin=$isClubAdmin');
      debugPrint('_isSelector=$isSelector');
      debugPrint('_isFixtureCaptain=$isFixtureCaptain');
      debugPrint('_isFixtureViceCaptain=$isFixtureViceCaptain');
      debugPrint('_canEditSelection=$canEditSelection');
      debugPrint('_canAssignRinks=$canAssignRinks');
      debugPrint('_canEditRinkSetup=$canEditRinkSetup');
      debugPrint('_canPublish=$canPublish');
      debugPrint('_canForceAccept=$canForceAccept');
      debugPrint('_canAddPeople=$canAddPeople');

      if (!mounted) return;
      setState(() {
        _isSuperuser = isSuperuser;
        _isClubAdmin = isClubAdmin;
        _isSelector = isSelector;
        _isFixtureCaptain = isFixtureCaptain;
        _isFixtureViceCaptain = isFixtureViceCaptain;

        _canEditSelection = canEditSelection;
        _canAssignRinks = canAssignRinks;
        _canEditRinkSetup = canEditRinkSetup;
        _canPublish = canPublish;
        _canForceAccept = canForceAccept;
        _canAddPeople = canAddPeople;
      });
    } catch (e) {
      debugPrint('MANAGE_TEAM _loadUserPermissions error: $e');

      if (!mounted) return;
      setState(() {
        _isSuperuser = false;
        _isClubAdmin = false;
        _isSelector = false;
        _isFixtureCaptain = false;
        _isFixtureViceCaptain = false;
        _canEditSelection = false;
        _canAssignRinks = false;
        _canEditRinkSetup = false;
        _canPublish = false;
        _canForceAccept = false;
        _canAddPeople = false;
      });
    } finally {
      if (mounted) {
        setState(() => _checkingPermissions = false);
      }
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
      final first = (mp?['first_name'] ?? '').toString().trim();
      final last = (mp?['last_name'] ?? '').toString().trim();
      final name = ('$first $last').trim();

      members.add({
        'member_profile_id': r['member_profile_id']?.toString(),
        'first_name': first,
        'last_name': last,
        'display_name': name.isEmpty
            ? (r['member_profile_id']?.toString() ?? '')
            : name,
      });
    }

    members.sort((a, b) {
      final lastA = (a['last_name'] ?? '').toString().toLowerCase();
      final lastB = (b['last_name'] ?? '').toString().toLowerCase();
      final lastCmp = lastA.compareTo(lastB);
      if (lastCmp != 0) return lastCmp;

      final firstA = (a['first_name'] ?? '').toString().toLowerCase();
      final firstB = (b['first_name'] ?? '').toString().toLowerCase();
      final firstCmp = firstA.compareTo(firstB);
      if (firstCmp != 0) return firstCmp;

      final nameA = (a['display_name'] ?? '').toString().toLowerCase();
      final nameB = (b['display_name'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });

    if (mounted) {
      setState(() => _clubMembers = members);
    }
  }

  Future<void> _showAddMemberDialog() async {
    if (!_canAddPeople) return;

    await _loadClubMembers();
    if (!mounted) return;

    final fixtureId = widget.fixture['id']?.toString();
    final teamId = widget.fixture['team_id']?.toString();
    final requiresRsvp = widget.fixture['requires_rsvp'] == true;

    if (fixtureId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fixture not loaded correctly.')),
        );
      }
      return;
    }

    // For now, no add-members flow for non-team, no-RSVP fixtures
    if (!_isTeamFixture && !requiresRsvp) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All active club members are already eligible for this fixture.')),
        );
      }
      return;
    }

    // Build the eligible list for the dialog
    final List<Map<String, dynamic>> eligibleMembers = [];
    final Set<String> existingIds = {};

    if (_isTeamFixture) {
      if (teamId == null || teamId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Team fixture has no team assigned.')),
          );
        }
        return;
      }

      // Exclude members already in team_members for this team
      final existingRows = await _client
          .from('team_members')
          .select('member_profile_id')
          .eq('team_id', teamId);

      existingIds.addAll(
        List<Map<String, dynamic>>.from(existingRows)
            .map((r) => r['member_profile_id']?.toString())
            .whereType<String>(),
      );

      for (final m in _clubMembers) {
        final mpId = m['member_profile_id']?.toString();
        if (mpId == null || mpId.isEmpty) continue;
        if (existingIds.contains(mpId)) continue;
        eligibleMembers.add(m);
      }
    } else {
      // RSVP fixture: exclude members already in fixture_rsvps
      final existingRows = await _client
          .from('fixture_rsvps')
          .select('member_profile_id')
          .eq('fixture_id', fixtureId);

      existingIds.addAll(
        List<Map<String, dynamic>>.from(existingRows)
            .map((r) => r['member_profile_id']?.toString())
            .whereType<String>(),
      );

      for (final m in _clubMembers) {
        final mpId = m['member_profile_id']?.toString();
        if (mpId == null || mpId.isEmpty) continue;
        if (existingIds.contains(mpId)) continue;
        eligibleMembers.add(m);
      }
    }

    // remove duplicates (safety)
    final seen = <String>{};
    eligibleMembers.removeWhere((m) {
      final id = m['member_profile_id']?.toString() ?? '';
      if (id.isEmpty) return true;
      if (seen.contains(id)) return true;
      seen.add(id);
      return false;
    });

    // DEBUG
    debugPrint('ADD_MEMBERS existing RSVP ids=$existingIds');
    debugPrint(
      'ADD_MEMBERS eligible ids=${eligibleMembers.map((m) => m['member_profile_id']).toList()}',
    );

    if (eligibleMembers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No additional members available.')),
        );
      }
      return;
    }

    final selectedIds = <String>{};

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return AlertDialog(
              title: Text(
                _isTeamFixture ? 'Add players to team pool' : 'Add players to RSVP pool',
              ),
              content: SizedBox(
                width: 420,
                height: 420,
                child: ListView(
                  children: eligibleMembers.map((m) {
                    final mpId = m['member_profile_id']?.toString() ?? '';
                    final name = (m['display_name'] ?? '(no name)').toString();
                    final checked = selectedIds.contains(mpId);

                    return CheckboxListTile(
                      value: checked,
                      dense: true,
                      title: Text(name),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) {
                        setLocalState(() {
                          if (v == true) {
                            selectedIds.add(mpId);
                          } else {
                            selectedIds.remove(mpId);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    selectedIds.isEmpty
                        ? 'Add selected'
                        : 'Add selected (${selectedIds.length})',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;
    if (selectedIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select at least one member.')),
        );
      }
      return;
    }

    try {

      List<Map<String, dynamic>> inserted = [];
      
      debugPrint(
        'ADD_MEMBERS branch=${_isTeamFixture ? "team_members" : "fixture_rsvps"} '
        'selectedIds=$selectedIds',
      );

      if (_isTeamFixture) {
        final payload = selectedIds
            .map((id) => {
                  'team_id': teamId,
                  'member_profile_id': id,
                  'is_active': true,
                })
            .toList();

        inserted = List<Map<String, dynamic>>.from(
          await _client
              .from('team_members')
              .insert(payload)
              .select(),
        );

        debugPrint('ADD_MEMBERS TEAM inserted=$inserted');

      } else {
        final payload = selectedIds
            .map((id) => {
                  'fixture_id': fixtureId,
                  'member_profile_id': id,
                  'status': 'maybe',
                })
            .toList();

        debugPrint('ADD_MEMBERS RSVP payload=$payload');

        inserted = List<Map<String, dynamic>>.from(
          await _client
              .from('fixture_rsvps')
              .insert(payload)
              .select('id, fixture_id, member_profile_id, status'),
        );

        debugPrint('ADD_MEMBERS RSVP inserted=$inserted');

      }

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Inserted rows: ${inserted.length}')),
        );
      }
/*       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isTeamFixture
                  ? 'Members added to team pool.'
                  : 'Members added to RSVP pool as maybe.',
            ),
          ),
        );
      } */
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Add failed: $e')),
        );
      }
    }
  }

  Future<void> _shareTeamSheet() async {
    try {
      if (_selectionId == null) throw Exception('Team selection not ready');

      final client = Supabase.instance.client;
      final svc = TeamSheetService(client);

      final fixtureId = widget.fixture['id'] as String;

      // Pull these from widget.fixture if they exist there, or wherever you store them
      final clubName = (widget.fixture['club_name'] ?? 'Club').toString();
      final opponentName = (widget.fixture['opponent_name'] ?? 'Opponent').toString();
      final startAt = DateTime.parse(widget.fixture['start_at'].toString());
      final isHome = widget.fixture['is_home'] == true;
      final section = (widget.fixture['section'] ?? '').toString();

      final data = await svc.loadTeamSheetData(
        fixtureId: fixtureId,
        teamSelectionId: _selectionId!,
        clubName: clubName,
        opponentName: opponentName,
        startAt: startAt,
        isHome: isHome,
        section: section,
        primaryColor: 0xFF0B3D91,
        secondaryColor: 0xFFFFD200,
        dress: 'Greys/Whites or Blacks',
        notes: null,
      );

      final pdfBytes = await buildTeamSheetPdf(data);

      await shareTeamSheetPdf(
        pdfBytes,
        message: '${data.clubName} v ${data.opponentName} — ${data.startAt}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    }
  }

  Map<String, dynamic>? _selectedRowFor(String memberId) {
    final rows = _selected.where((r) => r['member_profile_id'] == memberId).toList();
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> _togglePlayer(String memberId) async {
    if (widget.readOnly || !_canEditSelection) return;
    if (_selectionId == null) return;

    final client = Supabase.instance.client;

    try {
      final existingAny = await client
          .from('team_selection_members')
          .select('member_profile_id, role, acceptance, is_selected')
          .eq('team_selection_id', _selectionId!)
          .eq('member_profile_id', memberId)
          .maybeSingle();

      if (existingAny == null) {
        await client.from('team_selection_members').insert({
          'team_selection_id': _selectionId,
          'member_profile_id': memberId,
          'role': 'player',
          'acceptance': 'pending',
          'is_selected': true,
        });
      } else {
        final currentlySelected = existingAny['is_selected'] == true;

        if (currentlySelected) {
          await client
              .from('team_selection_members')
              .update({'is_selected': false})
              .eq('team_selection_id', _selectionId!)
              .eq('member_profile_id', memberId);
        } else {
          await client
              .from('team_selection_members')
              .update({'is_selected': true})
              .eq('team_selection_id', _selectionId!)
              .eq('member_profile_id', memberId);
        }
      }

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update team error: $e')),
      );
    }
  }

  Future<void> _setRole(String memberId, String role) async {
    if (widget.readOnly || !_canEditSelection) return;
    if (_selectionId == null) return;

    try {
      final existing = await Supabase.instance.client
          .from('team_selection_members')
          .select('role')
          .eq('team_selection_id', _selectionId!)
          .eq('member_profile_id', memberId)
          .maybeSingle();

      final oldRole = (existing?['role'] ?? '').toString().toLowerCase().trim();
      final newRole = role.toLowerCase().trim();

      debugPrint('SETROLE memberId=$memberId');
      debugPrint('SETROLE existing=$existing');
      debugPrint('SETROLE oldRole=$oldRole newRole=$newRole');
      debugPrint('SETROLE selectionId=$_selectionId');

      await Supabase.instance.client
          .from('team_selection_members')
          .update({'role': role})
          .eq('team_selection_id', _selectionId!)
          .eq('member_profile_id', memberId);

      if (oldRole == 'reserve' && newRole == 'player') {
        debugPrint('SETROLE reserve->player trigger fired for $memberId');

        final fixture = widget.fixture;
        final profileRow = await Supabase.instance.client
            .from('member_profiles')
            .select('display_name, first_name, last_name')
            .eq('id', memberId)
            .maybeSingle();

        final playerProfile =
            profileRow == null ? null : Map<String, dynamic>.from(profileRow);

        final playerName =
            playerProfile?['display_name']?.toString().trim().isNotEmpty == true
                ? playerProfile!['display_name'].toString().trim()
                : [
                    playerProfile?['first_name']?.toString().trim() ?? '',
                    playerProfile?['last_name']?.toString().trim() ?? '',
                  ].where((s) => s.isNotEmpty).join(' ');

        final isHome = fixture['is_home'] == true;
        final startAtText = fixture['start_at']?.toString();

        final fixtureLabel =
            (fixture['team_name']?.toString().trim().isNotEmpty ?? false)
                ? fixture['team_name'].toString().trim()
                : 'Fixture';

        final venueName =
            (fixture['venue_name']?.toString().trim().isNotEmpty ?? false)
                ? fixture['venue_name'].toString().trim()
                : ((fixture['opponent_name']?.toString().trim().isNotEmpty ?? false)
                    ? fixture['opponent_name'].toString().trim()
                    : '');

        await Supabase.instance.client.from('notification_queue').insert({
          'event_type': 'reserve_promoted',
          'member_profile_id': _currentMemberProfileId,
          'target_member_profile_id': memberId,
          'fixture_id': fixture['id'],
          'team_selection_id': _selectionId,
          'payload': {
            'player_name': playerName,
            'fixture_label': fixtureLabel,
            'fixture_date': startAtText,
            'home_away': isHome ? 'Home' : 'Away',
            'venue_name': venueName,
            'old_role': 'reserve',
            'new_role': 'player',
          },
          'status': 'pending',
        });
      }

      await _load();
    } catch (e, st) {
      debugPrint('SETROLE error: $e');
      debugPrint('SETROLE stack: $st');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Set role error: $e')),
      );
    }
  }

  Future<void> _publish() async {
    if (widget.readOnly || !_canEditSelection) return;
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

  Future<void> _removeSelected(String memberProfileId) async {
    if (widget.readOnly || !_canEditSelection) return;
    if (_selectionId == null) return;

    final selectedRow = _selected.firstWhere(
      (r) => r['member_profile_id']?.toString() == memberProfileId,
      orElse: () => <String, dynamic>{},
    );

    final acceptance =
        (selectedRow['acceptance'] ?? '').toString().trim().toLowerCase();

    if (acceptance == 'accepted') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Remove accepted player?'),
          content: const Text(
            'This player has already accepted selection. Remove them from the selected team?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    try {
      await Supabase.instance.client
          .from('team_selection_members')
          .update({'is_selected': false})
          .eq('team_selection_id', _selectionId!)
          .eq('member_profile_id', memberProfileId);

      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  Widget _poolRow(Map<String, dynamic> r) {
    final memberId = r['member_profile_id'] as String;
    final mp = r['member_profiles'] as Map<String, dynamic>?;
    final name = (mp?['display_name'] as String?) ?? '(no name)';
    final rsvp =
        r['rsvp_status']?.toString().toLowerCase() ??
        r['status']?.toString().toLowerCase() ??
        '';

    final sel = _selectedRowFor(memberId);
    final isSelected = sel != null;

    final availabilityText =
        rsvp == 'yes'
            ? 'Available'
            : rsvp == 'no'
                ? 'Not available'
                : rsvp == 'maybe'
                    ? 'Maybe'
                    : 'No response yet';

    Color? tileColor;
    if (rsvp == 'yes') {
      tileColor = const Color(0xFFE8F5E9); // soft green
    } else if (rsvp == 'no') {
      tileColor = const Color(0xFFFFEBEE); // soft red
    } else if (rsvp == 'maybe') {
      tileColor = const Color(0xFFFFF8E1); // soft amber
    }

    return Card(
      color: tileColor,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: isSelected
            ? const Icon(Icons.check, size: 18)
            : const SizedBox(width: 18),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Text(availabilityText),
            const SizedBox(width: 8),

            if (rsvp == 'yes')
              const Icon(Icons.check_circle, size: 14, color: Colors.green),

            if (rsvp == 'no')
              const Icon(Icons.cancel, size: 14, color: Colors.red),

            if (rsvp == 'maybe')
              const Icon(Icons.help, size: 14, color: Colors.orange),
          ],
        ),
        onTap: _canEditSelection ? () => _togglePlayer(memberId) : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPublished = _status == 'published';

    final isHome = widget.fixture['is_home'] == true;
    final isTeam = widget.fixture['team_id'] != null;

    final pageTitle =
        '${isHome ? 'Home' : 'Away'} '
        '${isTeam ? 'Team' : 'RSVP'} Management';

    final selectedIds = _selected
        .map((r) => r['member_profile_id']?.toString())
        .whereType<String>()
        .toSet();

    final visiblePool = _pool.where((r) {
      final id = r['member_profile_id']?.toString();
      return id != null && !selectedIds.contains(id);
    }).toList();

    final rinksRequired =
        int.tryParse(widget.fixture['rinks_required']?.toString() ?? '') ?? 0;
    final playersPerRink =
        int.tryParse(widget.fixture['players_per_rink']?.toString() ?? '') ?? 0;
    final requiredPlayers = rinksRequired * playersPerRink;

    final selectedCount = _selected.where((s) => (s['role'] ?? 'player') == 'player').length;

    final reservesCount = _selected.where((s) => (s['role'] ?? 'player') == 'reserve').length;
    
    return Scaffold(
        appBar: AppBar(
          title: Text(pageTitle),
        actions: [
          if (_canAddPeople)
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Add Player(s)',
              onPressed: () async {
                if (_selectionId == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Team selection not loaded yet. Try again in a moment.'),
                    ),
                  );
                  return;
                }

                if (_clubMembers.isEmpty) {
                  setState(() => _loading = true);
                  try {
                    await _loadClubMembers();
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

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ElevatedButton.icon(
                              onPressed: (_selectionId == null || !_canEditRinkSetup)
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
                              label: const Text('Rinks Setup'),
                            ),

                            const SizedBox(height: 8),

                            ElevatedButton.icon(
                              onPressed: _selectionId == null
                                  ? null
                                  : () async {
                                      final changed = await Navigator.push<bool>(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => RinkAssignmentsScreen(
                                            fixtureId: widget.fixture['id'].toString(),
                                            teamSelectionId: _selectionId!,
                                            readOnly: !_canAssignRinks,
                                          ),
                                        ),
                                      );

                                      debugPrint('MANAGE_TEAM returned from Rinks changed=$changed');

                                      if (changed == true) {
                                        await _load();
                                      }
                                    },
                              icon: const Icon(Icons.groups),
                              label: Text(
                                _canAssignRinks
                                    ? 'Assign Rinks & Positions'
                                    : 'View Rinks & Positions',
                              ),    
                            ),

                            const SizedBox(height: 8),

                            if (!isPublished)
                              ElevatedButton(
                                onPressed: _canPublish ? _publish : null,
                                child: const Text('Publish Team'),
                              )
                            else
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
                                  const SizedBox(width: 8),
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
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        title: Text(
                          requiredPlayers > 0
                              ? 'Players: $selectedCount / $requiredPlayers'
                              : 'Players: $selectedCount',
                        ),
                        subtitle: Text('Reserves: $reservesCount'),
                      ),
                    ),
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
                        final phone = (mp?['phone'] as String?) ?? '';                        

                        final acceptedByProfile = s['accepted_by_profile'] as Map<String, dynamic>?;
                        final acceptedByName =
                            (acceptedByProfile?['display_name'] as String?)?.trim() ?? '';
                        final playerOwnId = s['member_profile_id']?.toString();
                        final acceptanceById = s['acceptance_by']?.toString();

                        final acceptedOnBehalf =
                            acceptance == 'accepted' &&
                            acceptedByName.isNotEmpty &&
                            (acceptanceById?.isNotEmpty ?? false) &&
                            acceptanceById != playerOwnId;

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
                            onTap: _canEditSelection ? () async { await _removeSelected(memberId); } : null,
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (role == 'reserve')
                                  AppBadge(text: 'RESERVE')
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  acceptance == 'accepted'
                                      ? 'Accepted'
                                      : acceptance == 'declined'
                                          ? 'Declined'
                                          : 'Awaiting response',
                                ),
                                if (acceptedOnBehalf)
                                  Text(
                                    'Accepted by $acceptedByName',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                if (phone.isNotEmpty)
                                  Text(
                                    phone,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                      trailing: !_canEditSelection && !_canForceAccept
                          ? null
                          : PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'player' || v == 'reserve') {
                                  if (_canEditSelection) {
                                    await _setRole(memberId, v);
                                  }
                                } else if (v == 'accept') {
                                  if (_canForceAccept) {
                                    await _acceptOnBehalf(memberId);
                                  }
                                }
                              },
                              itemBuilder: (_) => [
                                if (_canEditSelection)
                                  const PopupMenuItem(value: 'player', child: Text('Make player')),
                                if (_canEditSelection)
                                  const PopupMenuItem(value: 'reserve', child: Text('Make reserve')),
                                if (_canForceAccept)
                                  const PopupMenuItem(value: 'accept', child: Text('Accept')),
                              ],
                            ),
                          ),
                        );
                      }
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isTeamFixture
                          ? 'Team pool'
                          : (widget.fixture['requires_rsvp'] == true
                              ? 'RSVP pool (Yes/Maybe)'
                              : 'Club members'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (visiblePool.isEmpty)
                      const Text('No eligible members found.')
                    else
                      ...visiblePool.map(_poolRow),
                    ],
                ),
    );
  }
}
