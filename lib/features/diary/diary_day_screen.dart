import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../fixtures/fixture_details_page.dart';
import '../fixtures/fixture_display.dart';
import 'rinks_day_view.dart';

class DiaryDayScreen extends StatefulWidget {
  const DiaryDayScreen({
    super.key,
    required this.clubId,
    required this.clubName,
    required this.date,
  });

  final String clubId;
  final String clubName;
  final DateTime date;

  @override
  State<DiaryDayScreen> createState() => _DiaryDayScreenState();
}

class _DiaryDayScreenState extends State<DiaryDayScreen> {
  final _client = Supabase.instance.client;

  late DateTime _date;
  bool _loading = true;
  String? _error;
  String? _myProfileId;

  List<_DiaryItem> _items = [];

  @override
  void initState() {
    super.initState();
    _date = DateTime(widget.date.year, widget.date.month, widget.date.day);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _loadMyProfileId();

      final startLocal = DateTime(_date.year, _date.month, _date.day);
      final endLocal = startLocal.add(const Duration(days: 1));

      final startUtc = startLocal.toUtc();
      final endUtc = endLocal.toUtc();

      final res = await _client
          .from('fixtures')
          .select('''
            id,
            club_id,
            start_at,
            end_at,
            is_home,
            section,
            team_name,
            opponent_name,
            venue_id,
            opponent_venue_id,
            green_area_id,
            rinks_required,
            notes,
            venue:venues!fixtures_venue_id_fkey (
              id,
              name
            ),
            opponent_venue:venues!fixtures_opponent_venue_id_fkey (
              id,
              name
            ),
            competition_type:competition_types (
              id,
              name,
              is_internal,
              selection_mode,
              uses_rinks,
              colour_scheme:fixture_colour_schemes (
                background_hex,
                foreground_hex
              )
            ),
            fixture_rinks (
              id,
              fixture_rink_no,
              home_rink_label,
              fixture_rink_assignments (
                member_profile_id
              )
            )
          ''')
          .eq('club_id', widget.clubId)
          .gte('start_at', startUtc.toIso8601String())
          .lt('start_at', endUtc.toIso8601String())
          .order('start_at');

      final rows = List<Map<String, dynamic>>.from(res);

debugPrint('DIARY DAY ${_date.toIso8601String()} rows=${rows.length}');
for (final r in rows) {
  debugPrint('DIARY ROW id=${r['id']} start=${r['start_at']} team=${r['team_name']}');
}

debugPrint('DIARY DAY date=$_date rows=${rows.length}');

for (final r in rows) {
  debugPrint(
    'DIARY ROW id=${r['id']} start=${r['start_at']} '
    'team=${r['team_name']} type=${r['competition_type']}',
  );
}

      final items = rows.map(_mapFixture).toList()
        ..sort((a, b) {
          final t = a.startAt.compareTo(b.startAt);
          if (t != 0) return t;
          return a.title.compareTo(b.title);
        });

debugPrint('DIARY ITEMS mapped=${items.length}');

      if (!mounted) return;
      setState(() {
        _items = items;
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

  Future<void> _loadMyProfileId() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      _myProfileId = null;
      return;
    }

    final mp = await _client
        .from('member_profiles')
        .select('id')
        .eq('user_id', userId)
        .maybeSingle();

    _myProfileId = mp?['id']?.toString();
  }

  _DiaryItem _mapFixture(Map<String, dynamic> f) {
    final startAt = DateTime.parse(f['start_at'].toString()).toLocal();
    final endAt = f['end_at'] != null
        ? DateTime.parse(f['end_at'].toString()).toLocal()
        : startAt.add(const Duration(hours: 3));

    final type = f['competition_type'] as Map<String, dynamic>?;
    final colourScheme = type?['colour_scheme'] as Map<String, dynamic>?;

    final bg = _parseHexColor(
      colourScheme?['background_hex']?.toString(),
      const Color(0xFFDBEAFE),
    );

    final fg = _parseHexColor(
      colourScheme?['foreground_hex']?.toString(),
      const Color(0xFF1E3A8A),
    );
  
    final usesRinksRaw = type?['uses_rinks'];
    final usesRinks = usesRinksRaw == null ? true : usesRinksRaw == true;

    final rinks = List<Map<String, dynamic>>.from(f['fixture_rinks'] ?? []);

    final rinkLabels = rinks
        .map((r) => (r['home_rink_label'] ?? '').toString().trim())
        .where((label) => label.isNotEmpty)
        .toList();

    final isMine = _myProfileId != null &&
        rinks.any((rink) {
          final assignments = List<Map<String, dynamic>>.from(
            rink['fixture_rink_assignments'] ?? [],
          );
          return assignments.any(
            (a) => a['member_profile_id']?.toString() == _myProfileId,
          );
        });

    return _DiaryItem(
      fixtureId: f['id'].toString(),
      startAt: startAt,
      endAt: endAt,
      title: fixtureTitleUnified(f, myClubName: widget.clubName),
      subtitle: fixtureSubtitleUnified(f),
      fixtureTypeName: (type?['name'] ?? '').toString(),
      notes: (f['notes'] ?? '').toString().trim(),
      venueName: _venueName(f),
      isHome: f['is_home'] == true,
      usesRinks: usesRinks,
      rinksRequired: (f['rinks_required'] ?? 0) as int,
      rinkLabels: rinkLabels,
      isMine: isMine,
      backgroundColor: bg,
      foregroundColor: fg,
    );
  }

  String _venueName(Map<String, dynamic> f) {
    final venue = f['venue'] as Map<String, dynamic>?;
    return (venue?['name'] ?? '').toString().trim();
  }

  void _moveDay(int delta) {
    setState(() {
      _date = _date.add(Duration(days: delta));
    });
    _load();
  }

  Future<void> _openFixture(_DiaryItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FixtureDetailsPage(fixtureId: item.fixtureId),
      ),
    );

    if (!mounted) return;
    await _load();
  }

  Future<void> _openRinksView() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RinkDayViewScreen(
          clubId: widget.clubId,
          clubName: widget.clubName,
          date: _date,
        ),
      ),
    );

    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: null,
        actions: [
          IconButton(
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _moveDay(-1),
          ),
          IconButton(
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _moveDay(1),
          ),
          IconButton(
            tooltip: 'Rinks view',
            icon: const Icon(Icons.view_timeline),
            onPressed: _openRinksView,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!),
                )
              : _DiaryDayColumn(
                  clubName: widget.clubName,
                  date: _date,
                  items: _items,
                  onItemTap: _openFixture,
                ),
    );
  }

  Color _parseHexColor(String? hex, Color fallback) {
    if (hex == null || hex.trim().isEmpty) return fallback;
    var value = hex.trim().replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    if (parsed == null) return fallback;
    return Color(parsed);
  }
}

class _DiaryDayColumn extends StatelessWidget {
  const _DiaryDayColumn({
    required this.clubName,
    required this.date,
    required this.items,
    required this.onItemTap,
  });

  final String clubName;
  final DateTime date;
  final List<_DiaryItem> items;
  final ValueChanged<_DiaryItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DayHeader(
          clubName: clubName,
          date: date,
          itemCount: items.length,
        ),
        Expanded(
          child: items.isEmpty
              ? const Center(
                  child: Text(
                    'Nothing in the diary for this day.',
                    style: TextStyle(fontSize: 18),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _DiaryItemTile(
                      item: item,
                      onTap: () => onItemTap(item),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.clubName,
    required this.date,
    required this.itemCount,
  });

  final String clubName;
  final DateTime date;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            clubName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _prettyDate(date),
            style: const TextStyle(
              fontSize: 34,
              height: 1.05,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _HeaderPill('$itemCount item${itemCount == 1 ? '' : 's'}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _DiaryItemTile extends StatelessWidget {
  const _DiaryItemTile({
    required this.item,
    required this.onTap,
  });

  final _DiaryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasRinks = item.rinkLabels.isNotEmpty;
    final rinkText = hasRinks
        ? 'Rinks ${item.rinkLabels.join(', ')}'
        : item.usesRinks && item.rinksRequired > 0
            ? '${item.rinksRequired} rink${item.rinksRequired == 1 ? '' : 's'} needed'
            : item.venueName;

    return Container(
        decoration: item.isMine
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: item.backgroundColor.withOpacity(0.35),
                    blurRadius: 16,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ],
              )
            : null,
        child: Card(
        elevation: item.isMine ? 4 : 2,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: item.isMine
                ? item.foregroundColor
                : item.backgroundColor.withOpacity(0.6),
            width: item.isMine ? 2.2 : 1,
          ),
        ),
        shadowColor: item.isMine
            ? item.backgroundColor.withOpacity(0.55)
            : Colors.black.withOpacity(0.2),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 72,
                  decoration: BoxDecoration(
                    color: item.backgroundColor,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(16),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _timeLabel(item.startAt),
                        style: TextStyle(
                          color: item.foregroundColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 18,
                        height: 2,
                        color: item.foregroundColor.withOpacity(0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _timeLabel(item.endAt),
                        style: TextStyle(
                          color: item.foregroundColor.withOpacity(0.9),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                  color: _isLightColor(item.foregroundColor)
                      ? item.backgroundColor.withOpacity(0.72)
                      : item.backgroundColor.withOpacity(0.10),
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 18,
                                  height: 1.05,
                                  fontWeight: FontWeight.w900,
                                  color: item.foregroundColor,
                                ),
                              ),
                            ),
                            if (item.isMine) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.9),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.person,
                                  size: 14,
                                  color: item.backgroundColor,
                                ),
                              ),
                            ],
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right,
                              color: item.foregroundColor.withOpacity(0.75),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.fixtureTypeName.isEmpty
                              ? item.subtitle
                              : item.fixtureTypeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: item.foregroundColor.withOpacity(0.88),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _MiniChip(
                              icon: item.isHome ? Icons.home : Icons.directions_bus,
                              text: item.isHome ? 'Home' : 'Away',
                              color: item.foregroundColor,
                            ),
                            if (rinkText.isNotEmpty)
                              _MiniChip(
                                icon: item.usesRinks ? Icons.view_timeline : Icons.place,
                                text: rinkText,
                                color: item.foregroundColor,
                              ),
                          ],
                        ),
                        if (item.notes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            item.notes,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF374151),
                              height: 1.15,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      )  
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiaryItem {
  const _DiaryItem({
    required this.fixtureId,
    required this.startAt,
    required this.endAt,
    required this.title,
    required this.subtitle,
    required this.fixtureTypeName,
    required this.notes,
    required this.venueName,
    required this.isHome,
    required this.usesRinks,
    required this.rinksRequired,
    required this.rinkLabels,
    required this.isMine,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String fixtureId;
  final DateTime startAt;
  final DateTime endAt;
  final String title;
  final String subtitle;
  final String fixtureTypeName;
  final String notes;
  final String venueName;
  final bool isHome;
  final bool usesRinks;
  final int rinksRequired;
  final List<String> rinkLabels;
  final bool isMine;
  final Color backgroundColor;
  final Color foregroundColor;
}

String _timeLabel(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String _prettyDate(DateTime dt) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  return '${weekdays[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} ${dt.year}';
}

bool _isLightColor(Color color) {
  return color.computeLuminance() > 0.65;
}
  