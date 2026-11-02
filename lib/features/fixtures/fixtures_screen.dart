import '../competitions/personal_competition_matches.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';
import '../../core/utils/hex_color.dart';
import '../../core/widgets/app_badge.dart';

import '../../data/repositories/fixtures_repository.dart';

import 'create_fixture_page.dart';
import 'fixture_details_page.dart';
import 'fixture_display.dart';
import '../clubs/club_access.dart';
import '../diary/diary_list_repository.dart';
import '../competitions/competition_repository.dart';
import '../competitions/widgets/competition_arrangement_card.dart';
import '../competitions/screens/competition_arrangement_screen.dart';

const _fixtureListColumns =
    'id, start_at, is_home, section, rinks_required, players_per_rink, orientation, '
    'requires_rsvp, team_id, team_name, competition_type_id, '
    'captain_member_profile_id, vice_captain_member_profile_id, '
    'cancelled_at, '
    'competition_type:competition_types!fixtures_competition_type_id_fkey('
    'id, name, is_internal, selection_mode, uses_rinks, '
    'colour_scheme:fixture_colour_schemes('
    'id, name, background_hex, foreground_hex'
    ')'
    '), '
    'team:teams(name), '
    'venue:venues!fixtures_venue_id_fkey(name), '
    'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
    'fixture_rinks(format), '
    'green_areas(name, discipline, orientation_mode)';

class FixturesScreen extends StatefulWidget {
  final String clubId;
  final String clubName;
  final bool memberBookingsOnly;
  final Widget Function(String)? fixturePageBuilder;

  const FixturesScreen({
    super.key,
    required this.clubId,
    required this.clubName,
    this.memberBookingsOnly = false,
    this.fixturePageBuilder,
  });

  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends State<FixturesScreen> {
  final _scroll = ScrollController();
  bool _loading = true;
  bool _showPast = false;
  String? _error;
  String _myClubName = '';

  final _client = Supabase.instance.client;

  Color _clubBlue = const Color(0xFF0D47A1);
  Color _clubYellow = const Color(0xFFFFEB3B);

  String? _currentMemberId;
  Set<String> _involvedFixtureIds = {};

  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  bool _isSelector = false;
  bool _isFixtureCreator = false;
  bool _loadingPermissions = true;
  bool _canWrite = false;

  List<Map<String, dynamic>> _fixtures = [];
  List<({CompetitionData data, CompetitionRow match})> _competitionsToArrange =
      [];

  late final FixturesRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = FixturesRepository(Supabase.instance.client);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refreshFixture(String id) async {
    try {
      var query = _client
          .from('fixtures')
          .select(_fixtureListColumns)
          .eq('club_id', widget.clubId)
          .eq('id', id);
      if (!_showPast) {
        query = query.gte('start_at', DateTime.now().toUtc().toIso8601String());
      }
      final row = await query.maybeSingle();
      if (widget.memberBookingsOnly && row != null && !_isInvolved(row)) return;
      if (!mounted) return;
      final index = _fixtures.indexWhere((f) => f['id'].toString() == id);
      if (index < 0) return;
      final offset = _scroll.hasClients ? _scroll.offset : null;
      setState(() {
        if (row == null) {
          _fixtures.removeAt(index);
        } else {
          _fixtures[index] = Map<String, dynamic>.from(row);
        }
        _fixtures.sort((a, b) {
          final order = DateTime.parse(
            a['start_at'].toString(),
          ).compareTo(DateTime.parse(b['start_at'].toString()));
          return order != 0
              ? order
              : a['id'].toString().compareTo(b['id'].toString());
        });
      });
      if (offset != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _scroll.hasClients) {
            _scroll.jumpTo(
              offset.clamp(
                _scroll.position.minScrollExtent,
                _scroll.position.maxScrollExtent,
              ),
            );
          }
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This fixture could not be refreshed. Your list position has been kept. Use Refresh to try again.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadUserPermissions() async {
    final access = await loadClubAccess(clubId: widget.clubId, client: _client);

    _currentMemberId = access.currentMemberId;
    _isSuperuser = access.isSuperuser;
    _isClubAdmin = access.isClubAdmin;
    _isSelector = access.isSelector;
    _isFixtureCreator = access.canWrite && access.canCreateFixtures;
    _canWrite = access.canWrite;

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
      await _loadUserPermissions();

      final client = Supabase.instance.client;
      final nowIso = DateTime.now().toUtc().toIso8601String();

      final clubRow = await client
          .from('clubs')
          .select('name, primary_color_hex, secondary_color_hex')
          .eq('id', widget.clubId)
          .single();

      final myClubName = (clubRow['name'] ?? '').toString();
      final primaryHex = (clubRow['primary_color_hex'] ?? '#2A58A8').toString();
      final secondaryHex = (clubRow['secondary_color_hex'] ?? '#FFFFD600')
          .toString();

      _clubBlue = colorFromHex(primaryHex);
      _clubYellow = colorFromHex(secondaryHex);

      var q = client
          .from('fixtures')
          .select(_fixtureListColumns)
          .eq('club_id', widget.clubId);

      if (widget.memberBookingsOnly && _currentMemberId != null) {
        final selections = await loadDiaryPages(
          (offset) => client
              .from('team_selection_members')
              .select(
                'id,team_selections!inner(fixture_id,status,fixture:fixtures!inner(club_id))',
              )
              .eq('member_profile_id', _currentMemberId!)
              .eq('is_selected', true)
              .inFilter('acceptance', ['accepted', 'pending'])
              .eq('team_selections.status', 'published')
              .eq('team_selections.fixture.club_id', widget.clubId)
              .order('id')
              .range(offset, offset + 499)
              .count(CountOption.exact),
        );
        _involvedFixtureIds = selections
            .map((r) => (r['team_selections'] as Map)['fixture_id'].toString())
            .toSet();
      }

      if (!_showPast) {
        q = q.gte('start_at', nowIso);
      }

      final arrangements = <({CompetitionData data, CompetitionRow match})>[];
      if (widget.memberBookingsOnly && _currentMemberId != null) {
        arrangements.addAll(
          (await loadPersonalCompetitionMatches(
            CompetitionRepository(client),
            widget.clubId,
            _currentMemberId!,
          )).where((item) => competitionNeedsArrangement(item.match)),
        );
      }
      final rows = await q.order('start_at');
      final fixtures = List<Map<String, dynamic>>.from(
        rows,
      ).where((row) => !widget.memberBookingsOnly || _isInvolved(row)).toList();

      if (fixtures.isNotEmpty) {
        debugPrint('First fixture row: ${fixtures.first}');
      } else {
        debugPrint('No fixtures returned');
      }

      if (!mounted) return;

      setState(() {
        _myClubName = myClubName;
        _fixtures = fixtures;
        _competitionsToArrange = arrangements;
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
    if (!_canWrite) return;

    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CreateFixturePage(clubId: widget.clubId, clubName: widget.clubName),
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
        automaticallyImplyLeading: true, // 👈 helps, but not enough alone
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Text(
          widget.memberBookingsOnly
              ? 'My Fixture Bookings and Competitions'
              : 'Fixtures',
        ),
        actions: <Widget>[
          IconButton(
            icon: Icon(_showPast ? Icons.visibility_off : Icons.visibility),
            tooltip: _showPast ? 'Hide past fixtures' : 'Show past fixtures',
            onPressed: () {
              setState(() => _showPast = !_showPast);
              _load();
            },
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),

      floatingActionButton: _canWrite
          ? FloatingActionButton(
              onPressed: _createFixture,
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : _buildGroupedFixtureList(),
    );
  }

  Widget _buildGroupedFixtureList() {
    if (_fixtures.isEmpty && !widget.memberBookingsOnly) {
      return Center(
        child: Text(
          _canWrite ? 'No fixtures yet. Tap + to create one.' : 'No fixtures.',
        ),
      );
    }

    final Map<String, List<Map<String, dynamic>>> groups = {};

    for (final f in _fixtures) {
      final when = parseClubTime(f['start_at'].toString());
      final key =
          '${when.year}-${when.month.toString().padLeft(2, '0')}-${when.day.toString().padLeft(2, '0')}';

      groups.putIfAbsent(key, () => []).add(f);
    }

    final keys = groups.keys.toList()..sort();

    return ListView.builder(
      key: PageStorageKey(
        'fixtures-${widget.clubId}-${widget.memberBookingsOnly}',
      ),
      controller: _scroll,
      itemCount: keys.length + (widget.memberBookingsOnly ? 1 : 0),
      itemBuilder: (_, index) {
        if (widget.memberBookingsOnly && index == 0) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Competitions to be Arranged',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_competitionsToArrange.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No competition matches awaiting arrangement.'),
                  ),
                for (final item in _competitionsToArrange)
                  CompetitionArrangementCard(
                    data: item.data,
                    match: item.match,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CompetitionArrangementScreen(
                            data: item.data,
                            match: item.match,
                          ),
                        ),
                      );
                      if (mounted) await _load();
                    },
                  ),
                const SizedBox(height: 20),
                Text(
                  "My Fixtures I'm Involved with",
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                if (_fixtures.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No fixtures.'),
                  ),
              ],
            ),
          );
        }
        final idx = index - (widget.memberBookingsOnly ? 1 : 0);
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

  bool _isInvolved(Map<String, dynamic> row) =>
      _currentMemberId != null &&
      (row['captain_member_profile_id'] == _currentMemberId ||
          row['vice_captain_member_profile_id'] == _currentMemberId ||
          _involvedFixtureIds.contains(row['id']));

  String _friendlyDate(DateTime d) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]} ${d.year}';
  }

  Widget _fixtureTile(Map<String, dynamic> f) {
    return UnifiedFixtureCard(
      key: ValueKey('fixture:${f['id']}'),
      fixture: f,
      myClubName: _myClubName,
      onTap: () async {
        final changed = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                widget.fixturePageBuilder?.call(f['id'].toString()) ??
                FixtureDetailsPage(fixtureId: f['id'].toString()),
          ),
        );

        if (!context.mounted) return;

        if (changed == true) {
          await _refreshFixture(f['id'].toString());
        }
      },
    );
  }
}
