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

class FixturesScreen extends StatefulWidget {
  final String clubId;
  final String clubName;
  final bool memberBookingsOnly;

  const FixturesScreen({
    super.key,
    required this.clubId,
    required this.clubName,
    this.memberBookingsOnly = false,
  });

  @override
  State<FixturesScreen> createState() => _FixturesScreenState();
}

class _FixturesScreenState extends State<FixturesScreen> {
  
  bool _loading = true;
  bool _showPast = false;
  String? _error;
  String _myClubName = '';

  final _client = Supabase.instance.client;

  Color _clubBlue = const Color(0xFF0D47A1);
  Color _clubYellow = const Color(0xFFFFEB3B);

  String? _currentMemberId;

  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  bool _isSelector = false;
  bool _isFixtureCreator = false;
  bool _loadingPermissions = true;

  bool get _canSeeAllMemberFixtures =>
      _isSuperuser || _isClubAdmin || _isSelector;
      
  List<Map<String, dynamic>> _fixtures = [];

  late final FixturesRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = FixturesRepository(Supabase.instance.client);
    _load();
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
      final secondaryHex = (clubRow['secondary_color_hex'] ?? '#FFFFD600').toString();

      _clubBlue = colorFromHex(primaryHex);
      _clubYellow = colorFromHex(secondaryHex);

      var q = client
          .from('fixtures')
          .select(
            'id, start_at, is_home, section, rinks_required, players_per_rink, orientation, '
            'requires_rsvp, team_id, team_name, competition_type_id, '
            'captain_member_profile_id, vice_captain_member_profile_id, '
            'competition_type:competition_types!fixtures_competition_type_id_fkey('
              'id, name, is_internal, selection_mode, uses_rinks, '
              'colour_scheme:fixture_colour_schemes('
                'id, name, background_hex, foreground_hex'
              ')'
            '), '
            'team:teams(name), '
            'venue:venues!fixtures_venue_id_fkey(name), '
            'opponent_venue:venues!fixtures_opponent_venue_id_fkey(name), '
            'green_areas(name, discipline, orientation_mode)'
          )
          .eq('club_id', widget.clubId);

      if (widget.memberBookingsOnly &&
          !_canSeeAllMemberFixtures &&
          _currentMemberId != null) {
        q = q.eq('captain_member_profile_id', _currentMemberId!);
      }

      if (!_showPast) {
        q = q.gte('start_at', nowIso);
      }

      final rows = await q.order('start_at');
      final fixtures = List<Map<String, dynamic>>.from(rows);

      if (fixtures.isNotEmpty) {
        debugPrint('First fixture row: ${fixtures.first}');
      } else {
        debugPrint('No fixtures returned');
      }

      if (!mounted) return;

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
        automaticallyImplyLeading: true, // 👈 helps, but not enough alone
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Text(widget.memberBookingsOnly ? 'Member Fixtures' : 'Fixtures'),
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
    final section = f['section'] as String;    final competitionType = f['competition_type'] as Map<String, dynamic>?;
    final competitionTypeName =
        (competitionType?['name'] ?? '').toString().trim();
    final competitionColourScheme =
        competitionType?['colour_scheme'] as Map<String, dynamic>?;

    final fixtureTypeBg = competitionColourScheme != null
        ? colorFromHex(
            competitionColourScheme['background_hex']?.toString(),
            fallback: Colors.grey.shade200,
          )
        : null;

    final fixtureTypeFg = competitionColourScheme != null
        ? colorFromHex(
            competitionColourScheme['foreground_hex']?.toString(),
            fallback: Colors.black87,
          )
        : null;

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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: fixtureTypeBg ?? (isHome ? _clubYellow.withOpacity(0.20) : null),
      child: ListTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                fixtureTitleUnified(f, myClubName: _myClubName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: fixtureTypeFg ?? (isHome ? _clubBlue : null),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AppBadge(text: isHome ? 'HOME' : 'AWAY'),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (competitionTypeName.isNotEmpty) ...[
              Text(
                competitionTypeName,
                style: TextStyle(
                  color: fixtureTypeFg ?? (isHome ? _clubBlue : null),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              '$whenText • $section • ${formatLabel(ppr)} • $rinks rinks'
              '${showOrientation ? ' • orient: ${orientation ?? 'not set'}' : ''}',
              style: TextStyle(
                color: fixtureTypeFg?.withOpacity(0.85) ?? (isHome ? _clubBlue : null),
              ),
            ),
          ],
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: fixtureTypeFg ?? (isHome ? _clubBlue : null),
        ),
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
      ),
    );
  }
}
