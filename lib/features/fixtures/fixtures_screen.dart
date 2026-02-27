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
  List<Map<String, dynamic>> _fixtures = [];

  late final FixturesRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = FixturesRepository(Supabase.instance.client);
    _load();
  }

  Future<void> _loadFixtures() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _repo.getFixturesForClub(widget.clubId);

      setState(() {
        _fixtures = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
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
      final nowIso = DateTime.now().toUtc().toIso8601String();

      var q = client
          .from('fixtures')
          .select(
            'id, start_at, is_home, section, rinks_required, players_per_rink, orientation, '
            'captain_member_profile_id, vice_captain_member_profile_id, '
            'venue:venues!fixtures_venue_id_fkey(name), '
            'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
            'green_areas(name, discipline, orientation_mode)'
          )
          .eq('club_id', widget.clubId);

      if (!_showPast) {
        q = q.gte('start_at', nowIso);
      }

      final rows = await q.order('start_at');

      _fixtures = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
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

    if (created == true) {
      _load();
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
      title: Row(
        children: [
          Expanded(
            child: Text(
              isHome
                  ? '$venue — $greenName vs $opponent'
                  : 'at $opponent',
            ),
          ),

          const SizedBox(width: 8),
          AppBadge(text: isHome ? 'HOME' : 'AWAY'),
        ],
      ),

      subtitle: Text(
        '$whenText'
        ' • $section • ${formatLabel(ppr)} • $rinks rinks'
        '${showOrientation ? ' • orient: ${orientation ?? 'not set'}' : ''}',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FixtureDetailsPage(fixtureId: f['id'].toString()),
          ),
        );
      },
    );
  }

}


