import '../fixtures/fixture_details_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:async';

import '../../core/utils/date_format.dart';
import 'club_home_screen.dart';
import '../fixtures/fixtures_screen.dart';
import '../members/members_screen_with_Import.dart';
import '../config/venues_screen.dart';
import '../config/green_areas_screen.dart';
import '../config/match_formats_screen.dart';
import '../fixtures/fixture_display.dart';
import '../notifications/notifications_page.dart';
import '../../Core/permissions/club_role_resolver.dart';
import '../../Core/permissions/dashboard_permissions.dart';
import '../../Core/permissions/fixture_permissions.dart';
import '../../Core/permissions/fixture_role_resolver.dart';
import '../../Core/permissions/permission_models.dart';

class ClubDashboardScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const ClubDashboardScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<ClubDashboardScreen> createState() => _ClubDashboardScreenState();
}

class _ClubDashboardScreenState extends State<ClubDashboardScreen> {
  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  bool _isSelector = false;
  bool _isFixtureCreator = false; // keep false for now unless you already have this
  String? _currentMemberId;

  bool _loadingPermissions = true;  
  
  bool _loading = true;

  int _unreadNotificationCount = 0; 

  Timer? _notificationTimer;

  String? _error;
  String _myClubName = '';
  String _formatWhenLong12h(String isoUtc) {
    final dt = DateTime.parse(isoUtc).toLocal();
    var s = DateFormat("EEEE d MMMM yyyy, h:mm a").format(dt); // Saturday 21 February 2026, 7:30 PM
    s = s.replaceAll('AM', 'a.m.').replaceAll('PM', 'p.m.');
    return s;
  }
  
  Map<String, String> _myAvailabilityByFixtureId = {};

  String _fixtureTitle(Map<String, dynamic> f) {
    String safe(String? s) => (s ?? '').trim();

    final isHome = f['is_home'] == true;
    final isTeamFixture = f['team_id'] != null;

    final teamName = safe(f['team_name']?.toString());

    final opponentVenueId = safe(f['opponent_venue_id']?.toString());
    final opponentClubName = safe(_venueNameById[opponentVenueId]);

    final greenId = safe(f['green_area_id']?.toString());
    final greenName = safe(_greenNameById[greenId]);

    if (isHome) {
      if (isTeamFixture && teamName.isNotEmpty) {
        return '$teamName on ${greenName.isNotEmpty ? greenName : "Home"} vs '
            '${opponentClubName.isNotEmpty ? opponentClubName : "Opponent"}';
      }
      return '${greenName.isNotEmpty ? greenName : "Home"} vs '
          '${opponentClubName.isNotEmpty ? opponentClubName : "Opponent"}';
    } else {
      if (isTeamFixture && teamName.isNotEmpty) {
        return '$teamName playing at ${opponentClubName.isNotEmpty ? opponentClubName : "Opponent club"}';
      }
      return 'Playing at ${opponentClubName.isNotEmpty ? opponentClubName : "Opponent club"}';
    }
  }

  String _fixtureSubtitle(Map<String, dynamic> f) {
    final startAt = (f['start_at'] ?? '').toString();
    final whenText = startAt.isEmpty ? 'Date/time not set' : _formatWhenLong12h(startAt);

    final section = (f['section'] ?? '').toString();
    final parts = <String>[
      whenText,
      if (section.isNotEmpty) section.toUpperCase(),
    ];

    return parts.join(' • ');
  }

  List<Map<String, dynamic>> _toRsvp = [];
  List<Map<String, dynamic>> _awaitingSelection = [];
  List<Map<String, dynamic>> _needsAcceptance = [];
  List<Map<String, dynamic>> _upcomingAccepted = [];

  // Lookup maps (id -> display data)
  // Map<String, Map<String, String>> _greenById = {};
  // Map<String, Map<String, String>> _formatById = {};
  Map<String, String> _venueNameById = {};
  Map<String, String> _greenNameById = {};
  
  @override
  void initState() {
    super.initState();

    _initDashboard();

    _notificationTimer =
        Timer.periodic(const Duration(seconds: 20), (_) {
      _loadUnreadNotificationCount();
    });
  }

  @override
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _initDashboard() async {
    try {
      await _loadUserPermissions();
      await _load();
      await _loadUnreadNotificationCount();
    } catch (e, st) {
      debugPrint('Dashboard init failed: $e');
      debugPrintStack(stackTrace: st);

      if (mounted) {
        setState(() {
          _loadingPermissions = false;
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _loadUserPermissions() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw Exception('No logged-in user');
    }

    final myProfileId = (await supabase.rpc('my_member_profile_id')).toString();

    // 1) Global superuser
    final superuserRow = await supabase
        .from('app_superusers')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();

    _isSuperuser = superuserRow != null;

    // 2) Club membership for this club, using member_profile_id
    final membership = await supabase
        .from('club_memberships')
        .select('id, club_id, member_profile_id, role')
        .eq('member_profile_id', myProfileId)
        .eq('club_id', widget.clubId)
        .maybeSingle();

    debugPrint('AUTH user.id       = ${user.id}');
    debugPrint('PROFILE myProfileId = $myProfileId');
    debugPrint('MEMBERSHIP row      = $membership');

    if (membership != null) {
      _currentMemberId = myProfileId;

      final role = (membership['role'] ?? '').toString().trim().toLowerCase();

      debugPrint('MEMBERSHIP role raw = ${membership['role']}');
      debugPrint('MEMBERSHIP role norm= $role');

      _isClubAdmin = role == 'admin';
      _isSelector = role == 'selector';

      _isFixtureCreator = _isSuperuser || _isClubAdmin || _isSelector;
    } else {
      _currentMemberId = myProfileId;
      _isClubAdmin = false;
      _isSelector = false;
      _isFixtureCreator = _isSuperuser;
    }

    debugPrint(
      'Dashboard perms: super=$_isSuperuser '
      'admin=$_isClubAdmin '
      'selector=$_isSelector '
      'fixtureCreator=$_isFixtureCreator '
      'memberId=$_currentMemberId',
    );

    if (mounted) {
      setState(() {
        _loadingPermissions = false;
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final myId = (await client.rpc('my_member_profile_id')).toString();

      final myTeamRows = await client
          .from('team_members')
          .select('team_id')
          .eq('member_profile_id', myId)
          .eq('is_active', true);

      final myTeamIds = List<Map<String, dynamic>>.from(myTeamRows)
          .map((r) => r['team_id']?.toString())
          .whereType<String>()
          .toSet();
          
      final myAvailabilityRows = await client
          .from('fixture_rsvps')
          .select('fixture_id, status')
          .eq('member_profile_id', myId);

      final myAvailabilityByFixtureId = <String, String>{};
      for (final r in List<Map<String, dynamic>>.from(myAvailabilityRows)) {
        final fixtureId = r['fixture_id']?.toString();
        final status = r['status']?.toString();
        if (fixtureId != null && status != null) {
          myAvailabilityByFixtureId[fixtureId] = status;
        }
      }      

      // 1) Load my club name
      final clubRow = await client
          .from('clubs')
          .select('name, primary_color_hex, secondary_color_hex')
          .eq('id', widget.clubId)
          .single();

      final myClubName = (clubRow['name'] ?? '').toString();
      final primaryHex = (clubRow['primary_color_hex'] ?? '#2A58A8').toString();
      final secondaryHex = (clubRow['secondary_color_hex'] ?? '#D5A73D').toString();

      Color colorFromHex(String hex) {
        final h = hex.replaceAll('#', '').trim();
        final full = h.length == 6 ? 'FF$h' : h; // add alpha if missing
        return Color(int.parse(full, radix: 16));
      }

      final clubBlue = colorFromHex(primaryHex);
      final clubYellow = colorFromHex(secondaryHex);

      final homeBg = clubYellow.withOpacity(0.2);
      final homeFg = clubBlue;      

      // Lookup maps (ids -> names) so dashboard can show venue/green/opponent names
      final venuesRows = await client
          .from('venues')
          .select('id, name')
          .eq('club_id', widget.clubId);

      final venueNameById = {
        for (final v in List<Map<String, dynamic>>.from(venuesRows))
          v['id'].toString(): (v['name'] ?? '').toString(),
      };

      final greensRows = await client
          .from('green_areas')
          .select('id, name')
          .eq('club_id', widget.clubId);

      final greenNameById = {
        for (final g in List<Map<String, dynamic>>.from(greensRows))
          g['id'].toString(): (g['name'] ?? '').toString(),
      };

      // Fixtures (future only)
      final fixturesRows = await client
          .from('fixtures')
          .select(
            'id, club_id, start_at, is_home, section, rinks_required, players_per_rink, '
            'requires_rsvp, team_id, team_name, '
            'venue_id, opponent_venue_id, green_area_id, '
            'venue:venues!fixtures_venue_id_fkey(name), '
            'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
            'team:teams(name), '
            'green_areas(name, discipline, orientation_mode), '
            'ts:team_selections(status)'
          )
          .eq('club_id', widget.clubId)
          .gte('start_at', DateTime.now().toUtc().toIso8601String())
          .order('start_at', ascending: true);
          
      final allFixtures = List<Map<String, dynamic>>.from(fixturesRows);

      debugPrint('DASH sample: ${allFixtures.isNotEmpty ? allFixtures.first : "none"}');

      bool isPublished(Map<String, dynamic> f) {
        final ts = f['ts'];
        if (ts == null) return false;
        if (ts is List && ts.isEmpty) return false;

        if (ts is List) {
          final status = ts.first?['status']?.toString();
          return status == 'published';
        }

        final status = (ts as Map?)?['status']?.toString();
        return status == 'published';
      }

      final toRsvp = allFixtures.where((f) {
        final requiresRsvp = f['requires_rsvp'] == true;
        if (!requiresRsvp) return false;
        return !isPublished(f);
      }).toList();

      final awaitingSelection = allFixtures.where((f) {
        final requiresRsvp = f['requires_rsvp'] == true;
        if (requiresRsvp) return false;

        if (isPublished(f)) return false;

        final teamId = f['team_id']?.toString();

        // Team fixture: only show if I belong to that team
        if (teamId != null && teamId.isNotEmpty) {
          return myTeamIds.contains(teamId);
        }

        // Non-team, no-RSVP fixture: keep visible
        return true;
      }).toList();

      // Needs my acceptance (published team + pending) for this club only
      final needsRows = await client
        .from('team_selection_members')
        .select(
          'acceptance, role, team_selections(status, fixture:fixtures('
          'id, club_id, start_at, is_home, section, rinks_required, players_per_rink, '
          'requires_rsvp, team_id, team_name, venue_id, opponent_venue_id, green_area_id, '
          'venue:venues!fixtures_venue_id_fkey(name), '
          'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
          'team:teams(name), '
          'green_areas(name, discipline, orientation_mode)'
          '))'
        )
        .eq('member_profile_id', myId)
        .eq('acceptance', 'pending');

      final rawNeeds = List<Map<String, dynamic>>.from(needsRows);

      final needsAcceptance = rawNeeds.where((r) {
        final ts = r['team_selections'] as Map<String, dynamic>?;
        if (ts?['status']?.toString() != 'published') return false;
        final fx = ts?['fixture'] as Map<String, dynamic>?;
        return fx?['club_id']?.toString() == widget.clubId;
      }).toList();

      // Accepted & upcoming (published + I'm selected + accepted)
      final acceptedRows = await client
        .from('team_selection_members')
        .select(
          'team_selections!inner('
          '  status, '
          '  fixture:fixtures!inner('
          '    id, club_id, start_at, is_home, section, rinks_required, players_per_rink, '
          '    requires_rsvp, team_id, team_name, venue_id, opponent_venue_id, green_area_id, '
          '    venue:venues!fixtures_venue_id_fkey(name), '
          '    opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
          '    team:teams(name), '
          '    green_areas(name, discipline, orientation_mode)'
          '  )'
          ')'
        )
        .eq('member_profile_id', myId)
        .eq('acceptance', 'accepted')
        .eq('team_selections.status', 'published')
        .eq('team_selections.fixture.club_id', widget.clubId);

      final nowUtcIso = DateTime.now().toUtc().toIso8601String();

      final upcomingAccepted = <Map<String, dynamic>>[];
      for (final r in List<Map<String, dynamic>>.from(acceptedRows)) {
        final ts = r['team_selections'] as Map<String, dynamic>?;
        final fx = ts?['fixture'] as Map<String, dynamic>?;
        if (fx == null) continue;

        // future only
        final startAt = fx['start_at']?.toString() ?? '';
        if (startAt.compareTo(nowUtcIso) < 0) continue;

        upcomingAccepted.add(fx);
      }

      // sort ascending by start_at
      upcomingAccepted.sort(
        (a, b) => (a['start_at'] as String).compareTo(b['start_at'] as String),
      );

      debugPrint(
        'DASH counts: '
        'needs=${needsAcceptance.length}, '
        'rsvp=${toRsvp.length}, '
        'awaiting=${awaitingSelection.length}, '
        'accepted=${upcomingAccepted.length}',
      );

      if (!mounted) return;

      setState(() {
        _myClubName = myClubName;

        _venueNameById = venueNameById;
        _greenNameById = greenNameById;

        _toRsvp = toRsvp;
        _awaitingSelection = awaitingSelection;
        _needsAcceptance = needsAcceptance;
        _upcomingAccepted = upcomingAccepted;

        _myAvailabilityByFixtureId = myAvailabilityByFixtureId;

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

  Future<void> _openFixtureById(String fixtureId) async {
    final client = Supabase.instance.client;

    final row = await client
        .from('fixtures')
        .select(
          'id, club_id, captain_member_profile_id, vice_captain_member_profile_id, start_at, is_home, section, rinks_required, players_per_rink, orientation, '
          'venue:venues!fixtures_venue_id_fkey(name), '
          'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
          'green_areas(name, discipline, orientation_mode)',
        )
        .eq('id', fixtureId)
        .single();

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FixtureDetailsPage(fixtureId: row['id'].toString()),
      )
    );

    await _load();
  }

  Future<void> _setTeamAvailability(String fixtureId, String status) async {
    try {
      final client = Supabase.instance.client;
      final myId = (await client.rpc('my_member_profile_id')).toString();

      await client.from('fixture_rsvps').upsert(
        {
          'fixture_id': fixtureId,
          'member_profile_id': myId,
          'status': status,
        },
        onConflict: 'fixture_id,member_profile_id',
      );

      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save availability: $e')),
      );
    }
  }

  Future<void> _loadUnreadNotificationCount() async {
    try {
      final client = Supabase.instance.client;
      final myId = (await client.rpc('my_member_profile_id')).toString();

      final rows = await client
          .from('app_notifications')
          .select('id')
          .eq('member_profile_id', myId)
          .eq('is_read', false);

      if (!mounted) return;

      setState(() {
        _unreadNotificationCount = rows.length;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _unreadNotificationCount = 0;
      });
    }
  }
  
  Widget _tile(String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingPermissions) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final canAccessAdmin =
        _isSuperuser || _isClubAdmin || _isSelector || _isFixtureCreator;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clubName),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const NotificationsPage(),
                ),
              );
              await _loadUnreadNotificationCount();
            },
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications),
                if (_unreadNotificationCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 18,
                        minHeight: 18,
                      ),
                      child: Text(
                        _unreadNotificationCount > 99
                            ? '99+'
                            : '$_unreadNotificationCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
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
                    if (canAccessAdmin) ...[
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ClubHomeScreen(
                                clubId: widget.clubId,
                                clubName: widget.clubName,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.settings),
                        label: const Text('Go to admin'),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text('Needs your acceptance',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_needsAcceptance.isEmpty)
                      const Text('Nothing waiting for you.')
                    else
                      ..._needsAcceptance.map((r) {
                        final ts = r['team_selections'] as Map<String, dynamic>?;
                        final fx = ts?['fixture'] as Map<String, dynamic>?;

                        if (fx == null) return const SizedBox.shrink();

                        final title = fixtureTitleUnified(fx, myClubName: _myClubName);
                        final subtitle = _fixtureSubtitle(fx);

                        return Card(
                          color: const Color(0xFFFFF8E1), // soft amber
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openFixtureById(fx['id']?.toString() ?? ''),
                          ),
                        );
                      }),

                    const SizedBox(height: 16),
                    Text('Fixtures to RSVP',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (_toRsvp.isEmpty)
                      const Text('No upcoming fixtures to RSVP.')
                    else
                      ..._toRsvp.map((f) {
                        final title = fixtureTitleUnified(f, myClubName: _myClubName);
                        final subtitle = _fixtureSubtitle(f);

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openFixtureById(f['id']?.toString() ?? ''),
                          ),
                        );
                      }),

                  const SizedBox(height: 12),
                  Text('Awaiting team selection', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),

                  if (_awaitingSelection.isEmpty)
                    const Text('No upcoming fixtures awaiting team selection.')
                  else
                    ..._awaitingSelection.map((f) {
                      final title = fixtureTitleUnified(f, myClubName: _myClubName);
                      final subtitle = _fixtureSubtitle(f);
                      final fixtureId = f['id']?.toString() ?? '';
                      final myStatus = _myAvailabilityByFixtureId[fixtureId];

                      final availabilityLabel =
                          myStatus == 'yes'
                              ? 'Available'
                              : myStatus == 'no'
                                  ? 'Not available'
                                  : 'No response yet';

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () => _openFixtureById(fixtureId),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                availabilityLabel,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton(
                                    onPressed: () => _setTeamAvailability(fixtureId, 'yes'),
                                    child: const Text('Available'),
                                  ),
                                  OutlinedButton(
                                    onPressed: () => _setTeamAvailability(fixtureId, 'no'),
                                    child: const Text('Not available'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 16),
                    Text('Accepted & published (upcoming)',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),

                    if (_upcomingAccepted.isEmpty)
                      const Text('No upcoming accepted fixtures.')
                    else
                      ..._upcomingAccepted.map((f) {
                        final title = fixtureTitleUnified(f, myClubName: _myClubName);
                        final subtitle = _fixtureSubtitle(f);

                        return Card(
                          color: const Color(0xFFE8F5E9), // soft green
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openFixtureById(f['id']?.toString() ?? ''),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }
}


