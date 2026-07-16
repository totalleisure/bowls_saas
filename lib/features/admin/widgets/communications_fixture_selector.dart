import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../fixtures/fixture_display.dart';

class CommunicationsFixtureSelector extends StatefulWidget {
  const CommunicationsFixtureSelector({
    super.key,
    required this.clubId,
    required this.selectedFixtureId,
    required this.onSelected,
  });

  final String clubId;
  final String? selectedFixtureId;
  final ValueChanged<Map<String, dynamic>> onSelected;

  @override
  State<CommunicationsFixtureSelector> createState() =>
      _CommunicationsFixtureSelectorState();
}

class _CommunicationsFixtureSelectorState
    extends State<CommunicationsFixtureSelector> {
  bool _loading = true;
  bool _showPast = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _loadFixtures();
  }

  Future<void> _loadFixtures() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await Supabase.instance.client
          .from('team_selections')
          .select('''
            id,
            status,
            created_at,
            fixtures!inner(
              id,
              start_at,
              is_home,
              section,
              team_id,
              team_name,
              club_id,
              clubs(name),
              team:teams!fixtures_team_id_fkey(name),
              competition_type:competition_types!fixtures_competition_type_id_fkey(
                name,
                selection_mode,
                is_internal,
                uses_rinks,
                colour_scheme:fixture_colour_schemes!competition_types_colour_scheme_id_fkey(
                  background_hex,
                  foreground_hex
                )
              ),
              venue:venues!fixtures_venue_id_fkey(name),
              opponent_venue:venues!fixtures_opponent_venue_id_fkey(name)
            )
          ''')
          .eq('fixtures.club_id', widget.clubId)
          .order('created_at', ascending: false)
          .limit(200);

      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });

      if (widget.selectedFixtureId == null && _rows.isNotEmpty) {
        final first = _recentPublished().isNotEmpty
            ? _recentPublished().first
            : _upcomingRows().isNotEmpty
            ? _upcomingRows().first
            : _rows.first;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onSelected(first);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Map<String, dynamic>? _fixtureMap(Map<String, dynamic> row) {
    final fixture = row['fixtures'];
    if (fixture is Map<String, dynamic>) return fixture;
    if (fixture is Map) return Map<String, dynamic>.from(fixture);
    return null;
  }

  DateTime? _startAt(Map<String, dynamic> row) {
    final iso = _fixtureMap(row)?['start_at']?.toString();
    if (iso == null || iso.isEmpty) return null;
    return DateTime.tryParse(iso)?.toLocal();
  }

  List<Map<String, dynamic>> _recentPublished() {
    return _rows
        .where((row) => row['status']?.toString() == 'published')
        .take(3)
        .toList();
  }

  List<Map<String, dynamic>> _upcomingRows() {
    final recentIds = _recentPublished()
        .map((row) => _fixtureMap(row)?['id']?.toString())
        .whereType<String>()
        .toSet();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final rows = _rows.where((row) {
      final fixtureId = _fixtureMap(row)?['id']?.toString();
      if (fixtureId != null && recentIds.contains(fixtureId)) return false;
      final start = _startAt(row);
      if (start == null) return false;
      return !start.isBefore(today);
    }).toList();

    rows.sort((a, b) {
      final aa = _startAt(a) ?? DateTime(2100);
      final bb = _startAt(b) ?? DateTime(2100);
      return aa.compareTo(bb);
    });
    return rows;
  }

  List<Map<String, dynamic>> _pastRows() {
    final recentIds = _recentPublished()
        .map((row) => _fixtureMap(row)?['id']?.toString())
        .whereType<String>()
        .toSet();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final rows = _rows.where((row) {
      final fixtureId = _fixtureMap(row)?['id']?.toString();
      if (fixtureId != null && recentIds.contains(fixtureId)) return false;
      final start = _startAt(row);
      if (start == null) return false;
      return start.isBefore(today);
    }).toList();

    rows.sort((a, b) {
      final aa = _startAt(a) ?? DateTime(1900);
      final bb = _startAt(b) ?? DateTime(1900);
      return bb.compareTo(aa);
    });
    return rows;
  }

  Color _colourFromHex(String? hex, Color fallback) {
    final value = hex?.replaceAll('#', '').trim();
    if (value == null || value.isEmpty) return fallback;
    final padded = value.length == 6 ? 'FF$value' : value;
    final parsed = int.tryParse(padded, radix: 16);
    if (parsed == null) return fallback;
    return Color(parsed);
  }

  Color _fixtureBg(Map<String, dynamic> row, BuildContext context) {
    final fixture = _fixtureMap(row);
    final type = fixture?['competition_type'];
    final scheme = type is Map ? type['colour_scheme'] : null;
    final hex = scheme is Map ? scheme['background_hex']?.toString() : null;
    return _colourFromHex(
      hex,
      Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }

  Color _fixtureFg(Map<String, dynamic> row, BuildContext context) {
    final fixture = _fixtureMap(row);
    final type = fixture?['competition_type'];
    final scheme = type is Map ? type['colour_scheme'] : null;
    final hex = scheme is Map ? scheme['foreground_hex']?.toString() : null;
    return _colourFromHex(hex, Theme.of(context).colorScheme.onSurface);
  }

  String _clubName(Map<String, dynamic> fixture) {
    final clubs = fixture['clubs'];
    if (clubs is Map) return clubs['name']?.toString() ?? '';
    return '';
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
    );
  }

  Widget _fixtureCard(Map<String, dynamic> row) {
    final fixture = _fixtureMap(row);
    if (fixture == null) return const SizedBox.shrink();

    final fixtureId = fixture['id']?.toString();
    final selected = fixtureId != null && fixtureId == widget.selectedFixtureId;
    final bg = _fixtureBg(row, context);
    final status = row['status']?.toString() ?? '';
    final title = fixtureTitleUnified(fixture, myClubName: _clubName(fixture));
    final subtitle = fixtureSubtitleUnified(fixture);

    final theme = Theme.of(context);
    final selectedFill = Color.alphaBlend(
      bg.withValues(alpha: 0.10),
      theme.colorScheme.surface,
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: selected ? selectedFill : null,
      elevation: selected ? 3 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? bg : Colors.black12,
          width: selected ? 2.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => widget.onSelected(row),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 58,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(10),
                  bottomLeft: Radius.circular(10),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          status.isEmpty ? 'Unknown' : status,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? bg
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fixtureGroup(String title, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(title),
        for (final row in rows) _fixtureCard(row),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Text(
        _error!,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      );
    }

    final recent = _recentPublished();
    final upcoming = _upcomingRows();
    final past = _pastRows();

    if (_rows.isEmpty) {
      return const Text('No team selections found yet.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            children: [
              _fixtureGroup('Recently Published', recent),
              _fixtureGroup('Upcoming Fixtures', upcoming),

              if (_showPast) _fixtureGroup('Past Fixtures', past),
            ],
          ),
        ),

        const Divider(),

        Row(
          children: [
            Checkbox(
              value: _showPast,
              onChanged: (value) {
                setState(() => _showPast = value == true);
              },
            ),
            const Text('Show past fixtures'),
            const Spacer(),
            IconButton(
              tooltip: 'Reload fixtures',
              onPressed: _loadFixtures,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ],
    );
  }
}
