import '../fixtures/fixture_details_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';
import 'club_home_screen.dart';
import '../fixtures/fixtures_screen.dart';
import '../members/members_screen.dart';
import '../config/venues_screen.dart';
import '../config/green_areas_screen.dart';
import '../config/match_formats_screen.dart';

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
  bool _loading = true;
  String? _error;

  String _formatWhenLong12h(String isoUtc) {
    final dt = DateTime.parse(isoUtc).toLocal();
    var s = DateFormat("EEEE d MMMM yyyy, h:mm a").format(dt); // Saturday 21 February 2026, 7:30 PM
    s = s.replaceAll('AM', 'a.m.').replaceAll('PM', 'p.m.');
    return s;
  }
  
  String _fixtureTitle(Map<String, dynamic> f) {
    final isHome = f['is_home'] == true;

    final venueId = f['venue_id']?.toString();
    final opponentVenueId = f['opponent_venue_id']?.toString();
    final greenAreaId = f['green_area_id']?.toString();

    final homeVenueName = venueId == null ? '' : (_venueNameById[venueId] ?? '');
    final opponentName = opponentVenueId == null ? '' : (_venueNameById[opponentVenueId] ?? '');
    final greenName = greenAreaId == null ? '' : (_greenNameById[greenAreaId] ?? '');

    if (isHome) {
      // Home: Venue — Green vs Opponent
      final left = [
        homeVenueName,
        if (greenName.isNotEmpty) greenName,
      ].where((s) => s.isNotEmpty).join(' — ');

      final right = opponentName.isNotEmpty ? ' vs $opponentName' : '';
      return '$left$right'.trim();
    }

    // Away: Opponent club name
    return opponentName.isNotEmpty ? opponentName : 'Away fixture';
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
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final myId = (await client.rpc('my_member_profile_id')).toString();

      // Lookup maps (ids -> names) so dashboard can show venue/green/opponent names
      final venuesRows = await client
          .from('venues')
          .select('id, name')
          .eq('club_id', widget.clubId);

      _venueNameById = {
        for (final v in List<Map<String, dynamic>>.from(venuesRows))
          v['id'].toString(): (v['name'] ?? '').toString(),
      };

      final greensRows = await client
          .from('green_areas')
          .select('id, name')
          .eq('club_id', widget.clubId);

      _greenNameById = {
        for (final g in List<Map<String, dynamic>>.from(greensRows))
          g['id'].toString(): (g['name'] ?? '').toString(),
      };

      // Fixtures to RSVP (unpublished for this club)
      final fixturesRows = await client
          .from('fixtures')
          .select(
            'id, club_id, start_at, is_home, section, rinks_required, players_per_rink, team_name, '
            'venue_id, green_area_id, opponent_venue_id, '
            'ts:team_selections(status)'
          )
          .eq('club_id', widget.clubId)
          .gte('start_at', DateTime.now().toUtc().toIso8601String())
          .order('start_at', ascending: true);

      final allFixtures = List<Map<String, dynamic>>.from(fixturesRows);

      _toRsvp = allFixtures.where((f) {
        final ts = f['ts'];
        if (ts == null) return true;
        if (ts is List && ts.isEmpty) return true;
        if (ts is List) {
          final status = ts.first?['status']?.toString();
          return status != 'published';
        }
        final status = (ts as Map?)?['status']?.toString();
        return status != 'published';
      }).toList();

      // Needs my acceptance (published team + pending) for this club only
      final needsRows = await client
          .from('team_selection_members')
          .select(
            'acceptance, role, team_selections(status, fixture:fixtures('
            'id, club_id, start_at, is_home, section, rinks_required, players_per_rink, team_name, '
            'venue_id, green_area_id, opponent_venue_id'
            '))'
          )
          .eq('member_profile_id', myId)
          .eq('acceptance', 'pending');

      final rawNeeds = List<Map<String, dynamic>>.from(needsRows);

      _needsAcceptance = rawNeeds.where((r) {
        final ts = r['team_selections'] as Map<String, dynamic>?;
        if (ts?['status']?.toString() != 'published') return false;
        final fx = ts?['fixture'] as Map<String, dynamic>?;
        return fx?['club_id']?.toString() == widget.clubId;
      }).toList();

      // 2c) Accepted & upcoming (strict: published + I'm selected + accepted)
      final acceptedRows = await client
          .from('team_selection_members')
          .select(
            'team_selections!inner('
            '  status, '
            '  fixture:fixtures!inner('
            '    id, club_id, start_at, is_home, section, rinks_required, players_per_rink, team_name, '
            '    venue_id, green_area_id, opponent_venue_id'
            '  )'
            ')',
          )
          .eq('member_profile_id', myId)
          .eq('acceptance', 'accepted')
          .eq('team_selections.status', 'published')
          .eq('team_selections.fixture.club_id', widget.clubId);

      final nowUtcIso = DateTime.now().toUtc().toIso8601String();

      final tmp = <Map<String, dynamic>>[];
      for (final r in List<Map<String, dynamic>>.from(acceptedRows)) {
        final ts = r['team_selections'] as Map<String, dynamic>?;
        final fx = ts?['fixture'] as Map<String, dynamic>?;
        if (fx == null) continue;

        // future only
        final startAt = fx['start_at']?.toString() ?? '';
        if (startAt.compareTo(nowUtcIso) < 0) continue;

        tmp.add(fx);
      }

      // sort ascending by start_at
      tmp.sort((a, b) => (a['start_at'] as String).compareTo(b['start_at'] as String));

      _upcomingAccepted = tmp;

      setState(() => _loading = false);
    } catch (e) {
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

Widget _fixtureTile(
  Map<String, dynamic> f, {
  Color? cardColor,
  required VoidCallback onTap,
}) {
  final startAt = (f['start_at'] ?? '').toString();
  final whenLabel =
      startAt.isNotEmpty ? _formatWhenLong12h(startAt) : 'Date/time not set';

  final isHome = f['is_home'] == true;
  final section = (f['section'] ?? '').toString();

  final venueId = f['venue_id']?.toString();
  final opponentVenueId = f['opponent_venue_id']?.toString();
  final greenId = f['green_area_id']?.toString();

  final venueName = venueId == null ? '' : (_venueNameById[venueId] ?? '');
  final opponentName =
      opponentVenueId == null ? '' : (_venueNameById[opponentVenueId] ?? '');
  final greenName = greenId == null ? '' : (_greenNameById[greenId] ?? '');

  // Title rule:
  // Home: Venue — Green vs Opponent
  // Away: Opponent name
  final titleText = isHome
      ? [
          venueName,
          if (greenName.isNotEmpty) greenName,
        ].where((s) => s.isNotEmpty).join(' — ') +
          (opponentName.isNotEmpty ? ' vs $opponentName' : '')
      : (opponentName.isNotEmpty ? opponentName : 'Away fixture');

  final subtitleText = [
    whenLabel,
    if (section.isNotEmpty) section.toUpperCase(),
  ].join(' • ');

  return Card(
    color: cardColor,
    margin: const EdgeInsets.symmetric(vertical: 4),
    child: ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(titleText, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitleText, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.clubName),
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

                        final title = _fixtureTitle(fx);
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
                        final title = _fixtureTitle(f);
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

                    const SizedBox(height: 16),
                    Text('Accepted & published (upcoming)',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),

                    if (_upcomingAccepted.isEmpty)
                      const Text('No upcoming accepted fixtures.')
                    else
                      ..._upcomingAccepted.map((f) {
                        final title = _fixtureTitle(f);
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


