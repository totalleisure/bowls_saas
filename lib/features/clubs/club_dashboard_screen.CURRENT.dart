import '../fixtures/fixture_details_page.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';
import 'club_home_screen.dart';
import '../fixtures/fixtures_screen.dart';
import '../config/members_screen.dart';
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

  List<Map<String, dynamic>> _toRsvp = [];
  List<Map<String, dynamic>> _needsAcceptance = [];
  List<Map<String, dynamic>> _upcomingAccepted = [];

  // Lookup maps (id -> display data)
  Map<String, String> _venueNameById = {};
  Map<String, Map<String, String>> _greenById = {};

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

      // Lookup tables for display (avoids fragile nested FK selects)
      final venuesRows = await client
          .from('venues')
          .select('id, name')
          .eq('club_id', widget.clubId);
      final venueNameById = <String, String>{
        for (final v in List<Map<String, dynamic>>.from(venuesRows))
          v['id'].toString(): (v['name'] ?? '').toString(),
      };

      final greensRows = await client
          .from('green_areas')
          .select('id, name, orientation_mode')
          .eq('club_id', widget.clubId);
      final greenById = <String, Map<String, String>>{
        for (final g in List<Map<String, dynamic>>.from(greensRows))
          g['id'].toString(): {
            'name': (g['name'] ?? '').toString(),
            'orientation_mode': (g['orientation_mode'] ?? '').toString(),
          },
      };


      // Fixtures to RSVP (unpublished for this club)
      final fixturesRows = await client
          .from('fixtures')
          .select('id, start_at, is_home, section, club_id, players_per_rink, venue_id, opponent_venue_id, green_area_id, ts:team_selections(status)')
          .eq('club_id', widget.clubId)
          .gte('start_at', DateTime.now().toUtc().toIso8601String())
          .order('start_at');

      final allFixtures = List<Map<String, dynamic>>.from(fixturesRows);

      // Ensure we can display opponent venue names for AWAY fixtures.
      // Our initial venues lookup is club-scoped; opponent venues belong to other clubs.
      final neededVenueIds = <String>{};
      for (final f in allFixtures) {
        final hv = f['venue_id']?.toString();
        final ov = f['opponent_venue_id']?.toString();
        if (hv != null && hv.isNotEmpty) neededVenueIds.add(hv);
        if (ov != null && ov.isNotEmpty) neededVenueIds.add(ov);
      }
      final missingVenueIds =
          neededVenueIds.where((id) => !_venueNameById.containsKey(id)).toList();

      if (missingVenueIds.isNotEmpty) {
        final extraVenuesRows = await client
            .from('venues')
            .select('id, name')
            .inFilter('id', missingVenueIds);

        for (final v in List<Map<String, dynamic>>.from(extraVenuesRows)) {
          _venueNameById[v['id'].toString()] = (v['name'] ?? '').toString();
        }
      }
      

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
            'acceptance, role, team_selections(status, fixture:fixtures(id, club_id, start_at, is_home, section, players_per_rink, venue_id, opponent_venue_id, green_area_id))',
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
            '  fixture:fixtures!inner(id, club_id, start_at, is_home, section, players_per_rink, venue_id, opponent_venue_id, green_area_id)'
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
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FixtureDetailsPage(fixtureId: fixtureId),
      ),
    );

    await _load();
  }

  
  Widget _fixtureTile(Map<String, dynamic> f, {Color? cardColor, required VoidCallback onTap}) {
    final startAt = (f['start_at'] ?? '').toString();
    final whenLabel = startAt.isNotEmpty ? formatWhenLocal(startAt) : 'Date/time not set';

    final isHome = f['is_home'] == true;
    final section = (f['section'] ?? '').toString();

    // Home club name is the current club
    final clubName = widget.clubName;

    final venueId = (isHome ? f['venue_id'] : f['opponent_venue_id'])?.toString();
    final venueName = venueId == null ? '' : (_venueNameById[venueId] ?? '');

    final greenId = f['green_area_id']?.toString();
    final greenName = greenId == null ? '' : (_greenById[greenId]?['name'] ?? '');
    final orientation = greenId == null ? '' : (_greenById[greenId]?['orientation_mode'] ?? '');
    final pprRaw = f['players_per_rink']?.toString();
    final computedFormat = _formatFromPpr(pprRaw);

    final title = [
      isHome ? 'HOME' : 'AWAY',
      if (computedFormat.isNotEmpty) computedFormat,
      if (section.isNotEmpty) section,
    ].join(' • ');

    final details = [
      if (clubName.isNotEmpty) clubName,
      if (venueName.isNotEmpty) 'Venue: $venueName',
      if (greenName.isNotEmpty) 'Green: $greenName',
      if (orientation.isNotEmpty) 'Orient: $orientation',
    ].join('  |  ');

    return Card(
      color: cardColor,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(whenLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (details.isNotEmpty)
              Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  String _formatFromPpr(dynamic ppr) {
    final v = int.tryParse((ppr ?? '').toString());
    switch (v) {
      case 2:
        return 'Pairs';
      case 3:
        return 'Triples';
      case 4:
        return 'Fours';
      default:
        return 'Mixed';
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

                        final when = DateTime.parse(fx?['start_at'] as String).toLocal();
                        final isHome = fx?['is_home'] == true;
                        final section = (fx?['section'] as String?) ?? '';

                        final title = '${isHome ? 'HOME' : 'AWAY'} • $section';
                        final subtitle = when.toString();

                        return _tile(
                          title,
                          subtitle,
                          () => _openFixtureById(fx?['id'] as String),
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
                        return _fixtureTile(
                          f,
                          onTap: () => _openFixtureById((f['id'] ?? '').toString()),
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
                        final when = DateTime.parse(f['start_at'] as String).toLocal();
                        final isHome = f['is_home'] == true;
                        final section = (f['section'] as String?) ?? '';

                        final title = '${isHome ? 'HOME' : 'AWAY'} • $section';
                        final subtitle = when.toString();

                        return Card(
                          color: const Color(0xFFE8F5E9), // soft green
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            title: Text(title),
                            subtitle: Text(subtitle),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openFixtureById(f['id'] as String),
                          ),
                        );
                      }),


                  ],
                ),
    );
  }
}

