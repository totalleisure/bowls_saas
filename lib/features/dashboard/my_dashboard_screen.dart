import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

class MyDashboardScreen extends StatefulWidget {
  const MyDashboardScreen({super.key});

  @override
  State<MyDashboardScreen> createState() => _MyDashboardScreenState();
}


class _MyDashboardScreenState extends State<MyDashboardScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _myClubs = [];
  List<String> _clubIds = [];

  List<Map<String, dynamic>> _toRsvp = [];
  List<Map<String, dynamic>> _needsAcceptance = [];

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

      // 1) My clubs (ids + names)
      final clubsRows = await client
          .from('club_memberships')
          .select('club_id, clubs(name)')
          .eq('member_profile_id', myId)
          .eq('is_active', true);

      _myClubs = List<Map<String, dynamic>>.from(clubsRows);
      _clubIds = _myClubs.map((r) => r['club_id'].toString()).toList();

      // 2a) Fixtures to RSVP (team not published yet)
      // NOTE: PostgREST will likely embed team_selections as an array.

      final fixtureRows = await Supabase.instance.client
          .from('fixtures')
          .select('''
            id,
            start_at,
            is_home,
            section,
            players_per_rink,
            rinks_required,
            club:clubs(name),
            home_venue:venues(name),
            green:greens(name, orientation),
            match_format:match_formats(label, players_per_rink),
            team_selections(status)
          ''')
              .inFilter('club_id', _clubIds)
              .gte('start_at', DateTime.now().toUtc().toIso8601String())
              .order('start_at');

      final allFixtures = List<Map<String, dynamic>>.from(fixtureRows);

      // Filter in Dart: include if no selection OR selection status == draft
      _toRsvp = allFixtures.where((f) {
        final ts = f['team_selections'];
        if (ts == null) return true;
        if (ts is List && ts.isEmpty) return true;
        if (ts is List) {
          final status = ts.first?['status']?.toString();
          return status != 'published';
        }
        // if it comes back as an object (rare), handle too
        final status = (ts as Map?)?['status']?.toString();
        return status != 'published';
      }).toList();

      // 2b) Fixtures needing my acceptance (published + I'm selected + pending)
      final needsRows = await client
          .from('team_selection_members')
          .select(
            'acceptance, role, '
            'team_selections('
            '  status, '
            '  fixture:fixtures('
            '    id, start_at, is_home, section, players_per_rink, rinks_required, '
            '    club:clubs(name), '
            '    home_venue:venues(name), '
            '    green:greens(name, orientation), '
            '    match_format:match_formats(label, players_per_rink)'
            '  )'
            ')',
          )
          .eq('member_profile_id', myId)
          .eq('acceptance', 'pending');

      final rawNeeds = List<Map<String, dynamic>>.from(needsRows);

      _needsAcceptance = rawNeeds.where((r) {
        final ts = r['team_selections'] as Map<String, dynamic>?;
        return ts?['status']?.toString() == 'published';
      }).toList();

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

    // Fetch a full fixture record in the shape FixtureDetailsPage expects
    final row = await client
        .from('fixtures')
        .select(
          'id, club_id, '
          'captain_member_profile_id, vice_captain_member_profile_id, '
          'start_at, is_home, section, rinks_required, players_per_rink, orientation, '
          'venue:venues!fixtures_venue_id_fkey(name), '
          'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
          'green_areas(name, discipline, orientation_mode), '
          'captain:member_profiles!fixtures_captain_member_profile_id_fkey(display_name), '
          'vice:member_profiles!fixtures_vice_captain_member_profile_id_fkey(display_name)'
        )
        .eq('id', fixtureId)
        .single();

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => FixtureDetailsPage(fixtureId: row['id'].toString())),
    );

    // refresh when returning (acceptance may have changed, etc.)
    await _load();
  }

  Widget _fixtureTile({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My dashboard'),
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
                          MaterialPageRoute(builder: (_) => MyClubsScreen()),
                        );
                      },
                      icon: const Icon(Icons.home),
                      label: const Text('Choose club (admin area)'),
                    ),
                    const SizedBox(height: 16),

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
                        final club = fx?['club'] as Map<String, dynamic>?;

                        final clubName = (club?['name'] as String?) ?? '';
                        final when = DateTime.parse(fx?['start_at'] as String).toLocal();
                        final isHome = fx?['is_home'] == true;
                        final section = (fx?['section'] as String?) ?? '';

                        final startAt = (fx?['start_at'] as String?) ?? '';
                        final whenLabel = startAt.isNotEmpty ? formatWhenLocal(startAt) : 'Date/time not set';

                        final venue = fx?['home_venue'] as Map<String, dynamic>?;
                        final venueName = (venue?['name'] as String?) ?? '';

                        final green = fx?['green'] as Map<String, dynamic>?;
                        final greenName = (green?['name'] as String?) ?? '';
                        final orientation = (green?['orientation'] as String?) ?? '';

                        final mf = fx?['match_format'] as Map<String, dynamic>?;
                        final mfLabel = (mf?['label'] as String?) ?? '';
                        final ppr = mf?['players_per_rink'] ?? fx?['players_per_rink'];
                        final format = mfLabel.isNotEmpty ? mfLabel : _formatFromPpr(ppr);

                        final title = '${isHome ? 'Home' : 'Away'} • ${format.isNotEmpty ? format : 'Mixed'}${section.isNotEmpty ? ' • $section' : ''}';
                        final subtitleParts = <String>[
                          if (clubName.isNotEmpty) clubName,
                          if (venueName.isNotEmpty) 'Venue: $venueName',
                          if (greenName.isNotEmpty) 'Green: $greenName',
                          if (orientation.isNotEmpty) 'Orient: $orientation',
                        ];
                        final subtitle = '${subtitleParts.join('  |  ')}\n$whenLabel';

                        return _fixtureTile(
                          title: title,
                          subtitle: subtitle,
                          onTap: () => _openFixtureById((fx?['id'] ?? '').toString()),
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
                        final club = f['club'] as Map<String, dynamic>?;
                        final clubName = (club?['name'] as String?) ?? '';

                        final startAt = (f['start_at'] as String?) ?? '';
                        final whenLabel = startAt.isNotEmpty ? formatWhenLocal(startAt) : 'Date/time not set';

                        final isHome = f['is_home'] == true;
                        final section = (f['section'] as String?) ?? '';

                        final venue = f['home_venue'] as Map<String, dynamic>?;
                        final venueName = (venue?['name'] as String?) ?? '';

                        final green = f['green'] as Map<String, dynamic>?;
                        final greenName = (green?['name'] as String?) ?? '';
                        final orientation = (green?['orientation'] as String?) ?? '';

                        final mf = f['match_format'] as Map<String, dynamic>?;
                        final mfLabel = (mf?['label'] as String?) ?? '';
                        final ppr = mf?['players_per_rink'] ?? f['players_per_rink'];
                        final format = mfLabel.isNotEmpty ? mfLabel : _formatFromPpr(ppr);

                        final title = '${isHome ? 'Home' : 'Away'} • ${format.isNotEmpty ? format : 'Mixed'}${section.isNotEmpty ? ' • $section' : ''}';
                        final subtitleParts = <String>[
                          if (clubName.isNotEmpty) clubName,
                          if (venueName.isNotEmpty) 'Venue: $venueName',
                          if (greenName.isNotEmpty) 'Green: $greenName',
                          if (orientation.isNotEmpty) 'Orient: $orientation',
                        ];
                        final subtitle = '${subtitleParts.join('  |  ')}\n$whenLabel';

                        return _fixtureTile(
                          title: title,
                          subtitle: subtitle,
                          onTap: () => _openFixtureById((f['id'] ?? '').toString()),
                        );
                      }),
                  ],
                ),
    );
  }
}


