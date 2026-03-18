import '../../core/widgets/app_badge.dart';
import '../../data/repositories/fixtures_repository.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';
import 'create_fixture_page.dart';
import 'fixture_details_page.dart';
import 'fixture_display.dart';

class FixturesScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const FixturesScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends State<FixturesScreen> {
  bool _loading = true;
  bool _showPast = false;
  String? _error;
  String _myClubName = '';

  Color _clubBlue = const Color(0xFF0D47A1);
  Color _clubYellow = const Color(0xFFFFEB3B);

  List<Map<String, dynamic>> _fixtures = [];

  late final FixturesRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = FixturesRepository(Supabase.instance.client);
    _load();
  }

/*   Future<void> _loadFixtures() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _repo.getFixturesForClub(widget.clubId);

      setState(() {
        _fixtures = data;
        _loading = false;
        _myClubName = myClubName;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  } */

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final nowIso = DateTime.now().toUtc().toIso8601String();

      // 1) Load my club name
      final clubRow = await client
          .from('clubs')
          .select('name')
          .eq('id', widget.clubId)
          .single();

      final myClubName = (clubRow['name'] ?? '').toString();
      final primaryHex = (clubRow['primary_color_hex'] ?? '#2A58A8').toString();
      final secondaryHex = (clubRow['secondary_color_hex'] ?? '#FFFFD600').toString();

      Color colorFromHex(String hex) {
        final h = hex.replaceAll('#', '').trim();
        final full = h.length == 6 ? 'FF$h' : h; // add alpha if missing
        return Color(int.parse(full, radix: 16));
      }

      _clubBlue = colorFromHex(primaryHex);
      _clubYellow = colorFromHex(secondaryHex);

      final homeBg = _clubYellow.withOpacity(0.2);
      final homeFg = _clubBlue;      

      // 2) Build fixtures query (keep your pattern)
      var q = client
          .from('fixtures')
          .select(
            'id, start_at, is_home, section, rinks_required, players_per_rink, orientation, '
            'requires_rsvp, team_id, '
            'captain_member_profile_id, vice_captain_member_profile_id, '
            'team:teams(name), '
            'venue:venues!fixtures_venue_id_fkey(name), '
            'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
            'green_areas(name, discipline, orientation_mode)',
          )
          .eq('club_id', widget.clubId);

      if (!_showPast) {
        q = q.gte('start_at', nowIso);
      }

      final rows = await q.order('start_at');
      final fixtures = List<Map<String, dynamic>>.from(rows);

      if (fixtures.isNotEmpty) {
        debugPrint('Sample fixture row: ${fixtures.first}');
      }   

      // Debug (safe)
      if (fixtures.isNotEmpty) {
        debugPrint('First fixture row: ${fixtures.first}');
      } else {
        debugPrint('No fixtures returned');
      }

      if (!mounted) return;

      // 3) Update state *together* so UI rebuilds correctly
      setState(() {
        _myClubName = myClubName;
        _fixtures = fixtures;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _createFixture() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateFixturePage(
          clubId: widget.clubId,
          clubName: widget.clubName,
        ),
      ),
    );

//    debugPrint('fixtures_screen: create flow returned changed=$changed');

    if (!context.mounted) return;

    if (created == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fixtures'),
        actions: <Widget>[
          IconButton(
            icon: Icon(_showPast ? Icons.visibility_off : Icons.visibility),
            tooltip: _showPast ? 'Hide past fixtures' : 'Show past fixtures',
            onPressed: () {
              setState(() => _showPast = !_showPast);
              _load();
            },
          ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _createFixture,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _buildGroupedFixtureList(),
    );
  }

  Widget _buildGroupedFixtureList() {
    if (_fixtures.isEmpty) {
      return const Center(child: Text('No fixtures yet. Tap + to create one.'));
    }

    final Map<String, List<Map<String, dynamic>>> groups = {};

    for (final f in _fixtures) {
      final when = DateTime.parse(f['start_at'] as String).toLocal();
      final key =
          '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';

      groups.putIfAbsent(key, () => []).add(f);
    }

    final keys = groups.keys.toList()..sort();

    return ListView.builder(
      itemCount: keys.length,
      itemBuilder: (_, idx) {
        final dateKey = keys[idx];
        final fixtures = groups[dateKey]!;
        final parts = dateKey.split('-'); // yyyy-mm-dd
        final headerDate = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                _friendlyDate(headerDate),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...fixtures.map(_fixtureTile).toList(),
          ],
        );
      },
    );
  }

  String _friendlyDate(DateTime d) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Widget _fixtureTile(Map<String, dynamic> f) {

    final when = DateTime.parse(f['start_at'] as String).toLocal();
    final whenText = formatWhenLocal(f['start_at'] as String);
    final isHome = f['is_home'] as bool;
    final venue = (f['venue']?['name'] as String?) ?? '';
    final opponent = (f['opponent_venue']?['name'] as String?) ?? '';
    final section = f['section'] as String;
    final rinks = f['rinks_required'] as int;
    final ppr = f['players_per_rink'] as int;
    final orientation = f['orientation'] as String?;
    final ga = f['green_areas'] as Map<String, dynamic>?;
    final greenName = (ga?['name'] as String?) ?? '';
    final discipline = ga?['discipline'] as String?;
    final orientationMode = ga?['orientation_mode'] as String?;

    final showOrientation =
        isHome && discipline == 'outdoor' && orientationMode != 'not_applicable';

    String formatLabel(int p) {
      if (p == 2) return 'Pairs';
      if (p == 3) return 'Triples';
      return 'Rinks';
    }

    return ListTile(
      tileColor: isHome ? _clubYellow.withOpacity(0.20) : null,
      title: Row(
        children: [
          Expanded(
            child: Text(
              fixtureTitleUnified(f, myClubName: _myClubName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: isHome ? TextStyle(color: _clubBlue) : null,
            ),
          ),

          const SizedBox(width: 8),
          AppBadge(text: isHome ? 'HOME' : 'AWAY'),
        ],
      ),

      subtitle: Text(
        '$whenText • $section • ${formatLabel(ppr)} • $rinks rinks'
        '${showOrientation ? ' • orient: ${orientation ?? 'not set'}' : ''}',
        style: isHome ? TextStyle(color: _clubBlue) : null,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => FixtureDetailsPage(fixtureId: f['id'].toString()),
          ),
        );

        if (!context.mounted) return;

        if (changed == true) {
          await _load();
        }
      },
    );
  }

}


