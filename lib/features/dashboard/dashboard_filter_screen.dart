import 'package:intl/intl.dart';
import '../../core/utils/date_format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../../models/dashboard_fixture_filter.dart';

class DashboardFilterScreen extends StatefulWidget {
  final DashboardFixtureFilter initialFilter;
  final String clubId;
  final bool diaryMode;
  final Future<List<Map<String, dynamic>>> Function()? fixtureTypesLoader;

  const DashboardFilterScreen({
    super.key,
    required this.initialFilter,
    required this.clubId,
    this.fixtureTypesLoader,
    this.diaryMode = false,
  });

  @override
  State<DashboardFilterScreen> createState() => _DashboardFilterScreenState();
}

class _DashboardFilterScreenState extends State<DashboardFilterScreen> {
  late DashboardFixtureFilter _draft;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialFilter;
    _loadFixtureTypes();
  }

  bool get _changed => _draft != widget.initialFilter;

  List<Map<String, dynamic>> _allTypes = [];
  bool _loadingTypes = true;

  String? _typesError;

  Color _colorFromHex(String? hex, {Color fallback = Colors.grey}) {
    if (hex == null || hex.trim().isEmpty) return fallback;

    final cleaned = hex.replaceAll('#', '').trim();
    final full = cleaned.length == 6 ? 'FF$cleaned' : cleaned;

    try {
      return Color(int.parse(full, radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  // --------------------------
  // TOGGLES
  // --------------------------

  void _toggleSection(String value) {
    final set = Set<String>.from(_draft.sections);
    set.contains(value) ? set.remove(value) : set.add(value);

    setState(() {
      _draft = _draft.copyWith(sections: set, explicitSections: true);
    });
  }

  void _toggleCategory(String value) {
    setState(() {
      _draft = _draft.toggleTag(value, _allTypes);
    });
  }

  void _setPeriod(String value) {
    setState(() {
      _draft = _draft.copyWith(period: value);
    });
  }

  void _toggleFixtureType(String id) {
    setState(() {
      _draft = _draft.toggleType(id, _allTypes);
    });
  }

  // --------------------------
  // UI
  // --------------------------

  Widget _buildFixtureTypes() {
    if (_loadingTypes) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_typesError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Could not load fixture types. Please try again.'),
          TextButton(onPressed: _loadFixtureTypes, child: const Text('Retry')),
        ],
      );
    }
    final types = _allTypes;

    if (types.isEmpty) {
      return const Text(
        'No fixture types have been set up for this club',
        style: TextStyle(color: Colors.grey),
      );
    }

    return _buildBlock(
      title: 'Fixture Types',
      children: types.map((t) {
        final id = t['id'].toString();
        final name = (t['name'] ?? '').toString();
        final selected = _draft.includesType(id, t);

        final colourScheme = t['colour_scheme'] as Map<String, dynamic>?;

        final bg = _colorFromHex(
          colourScheme?['background_hex']?.toString(),
          fallback: Colors.grey.shade200,
        );

        final fg = _colorFromHex(
          colourScheme?['foreground_hex']?.toString(),
          fallback: Colors.black,
        );

        return FilterChip(
          label: Text(name),
          selected: selected,
          selectedColor: bg,
          checkmarkColor: fg,
          labelStyle: TextStyle(color: selected ? fg : null),
          backgroundColor: bg.withOpacity(0.18),
          side: BorderSide(color: bg),
          onSelected: (_) => _toggleFixtureType(id),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.diaryMode ? 'Filter diary' : 'Filter fixtures'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _draft = const DashboardFixtureFilter();
              });
            },
            child: const Text('Reset'),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _changed ? Colors.red : Colors.grey,
        label: Text(_changed ? 'Save' : 'Return'),
        icon: Icon(_changed ? Icons.check : Icons.arrow_back),
        onPressed: _loadingTypes || _typesError != null
            ? null
            : () {
                Navigator.pop(
                  context,
                  _changed ? _draft : widget.initialFilter,
                );
              },
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionFilter(),
          if (_draft.explicitSections && _draft.sections.isEmpty)
            Text(
              widget.diaryMode
                  ? 'No sections selected. No diary entries will be shown.'
                  : 'No sections selected. Only protected fixtures will be shown.',
            ),
          const SizedBox(height: 24),
          _buildCategoryFilter(),
          const SizedBox(height: 24),
          _buildPeriodFilter(),
          const SizedBox(height: 24),

          const Divider(),
          Text(
            'Tick the fixture types you want to see. Tags select groups; '
                    'you can then add or remove individual types. '
                    'From All, a tag selects just that group. Counts show how many types in a group are selected. ' +
                (widget.diaryMode
                    ? 'Diary filters apply to every entry, with no exceptions. These filters are separate from your Dashboard.'
                    : 'Filters never hide acceptance requests, accepted fixtures or fixtures you manage.'),
          ),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('All types'),
                selected: _draft.allTypesSelected,
                onSelected: _loadingTypes || _typesError != null
                    ? null
                    : (_) => setState(() => _draft = _draft.selectAllTypes()),
              ),
              FilterChip(
                label: const Text('None'),
                selected: _draft.explicitTypes && _draft.fixtureTypeIds.isEmpty,
                onSelected: _loadingTypes || _typesError != null
                    ? null
                    : (_) => setState(() => _draft = _draft.selectTypes({})),
              ),
            ],
          ),
          if (_draft.explicitTypes && _draft.fixtureTypeIds.isEmpty)
            Text(
              widget.diaryMode
                  ? 'No fixture types selected. No diary entries will be shown.'
                  : 'No fixture types selected. Only protected fixtures will be shown.',
            ),
          const SizedBox(height: 8),
          _buildFixtureTypes(),
          const SizedBox(height: 96),
        ],
      ),
    );
  }

  // --------------------------
  // SECTIONS
  // --------------------------

  Widget _buildSectionFilter() {
    return _buildBlock(
      title: 'Section (applies to every selected type)',
      children: [
        _chip(
          label: 'All sections',
          selected: _draft.allSectionsSelected,
          onTap: () => setState(
            () =>
                _draft = _draft.copyWith(sections: {}, explicitSections: false),
          ),
        ),
        _chip(
          label: 'Open / everyone',
          selected: _draft.sections.contains('open'),
          onTap: () => _toggleSection('open'),
        ),
        _chip(
          label: 'Men',
          selected: _draft.sections.contains('mens'),
          onTap: () => _toggleSection('mens'),
        ),
        _chip(
          label: 'Ladies',
          selected: _draft.sections.contains('ladies'),
          onTap: () => _toggleSection('ladies'),
        ),
        _chip(
          label: 'Mixed',
          selected: _draft.sections.contains('mixed'),
          onTap: () => _toggleSection('mixed'),
        ),
      ],
    );
  }

  // --------------------------
  // CATEGORY
  // --------------------------

  Widget _buildCategoryFilter() {
    const tags = {
      'match': 'Matches',
      'league': 'Leagues',
      'competition': 'Competitions',
      'drive': 'Drives',
      'rollup': 'Roll-Ups',
      'event': 'Events',
      'open_session': 'Open sessions',
      'friendly': 'Friendly',
      'cup': 'Cup',
      'social': 'Social',
      'training': 'Training',
      'meeting': 'Meetings',
      'internal': 'Internal',
    };
    final selected = _draft.selectedIds(_allTypes);
    return _buildBlock(
      title: 'Tags — select groups of fixture types',
      children: [
        for (final entry in tags.entries)
          Builder(
            builder: (context) {
              final ids = {
                for (final type in _allTypes)
                  if (DashboardFixtureFilter.matchesTag(type, entry.key))
                    type['id'].toString(),
              };
              final count = ids.intersection(selected).length;
              final full = ids.isNotEmpty && count == ids.length;
              final partial = count > 0 && !full;
              return FilterChip(
                label: Text(
                  partial
                      ? '${entry.value} (${count} of ${ids.length})'
                      : entry.value,
                ),
                tooltip: ids.isEmpty
                    ? 'No matching fixture types'
                    : '$count of ${ids.length} types selected',
                selected: full && !_draft.allTypesSelected,

                onSelected: _loadingTypes || _typesError != null || ids.isEmpty
                    ? null
                    : (_) => _toggleCategory(entry.key),
              );
            },
          ),
      ],
    );
  }

  // --------------------------
  // PERIOD
  // --------------------------

  Widget _buildPeriodFilter() {
    final now = toClubTime(DateTime.now());
    final end = _draft.periodEnd(now);
    final range = end == null
        ? (widget.diaryMode
              ? 'All dates, including earlier diary entries'
              : 'All upcoming dates')
        : '${DateFormat('d MMM yyyy').format(_draft.periodStart(now))} – '
              '${DateFormat('d MMM yyyy').format(end.subtract(const Duration(days: 1)))}';
    Widget tile(String value, String label, double width) {
      final selected = _draft.period == value;

      return SizedBox(
        width: width,
        height: 52,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _setPeriod(value),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? Colors.red : Colors.grey.shade400,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
              color: selected ? Colors.red.withOpacity(0.08) : null,
            ),
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600, // 👈 match your tags weight
                color: selected ? Colors.red.shade700 : null,
              ),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final itemWidth = (constraints.maxWidth - spacing) / 2;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Period', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                tile(
                  'all',
                  widget.diaryMode ? 'All dates' : 'All upcoming',
                  itemWidth,
                ),
                tile('this_month', 'Rest of this month', itemWidth),
                tile('next_month', 'Next calendar month', itemWidth),
                tile('three_months', 'Next 3 months', itemWidth),
              ],
            ),
            const SizedBox(height: 8),
            Text(range, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }

  // --------------------------
  // SHARED UI
  // --------------------------

  Widget _buildBlock({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: children),
      ],
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }

  Future<void> _loadFixtureTypes() async {
    setState(() {
      _loadingTypes = true;
      _typesError = null;
    });
    try {
      final res = widget.fixtureTypesLoader != null
          ? await widget.fixtureTypesLoader!()
          : await Supabase.instance.client
                .from('competition_types')
                .select(
                  'id, name, section, is_internal, tags, selection_mode, uses_rinks, '
                  'colour_scheme:fixture_colour_schemes(name, background_hex, foreground_hex)',
                )
                .eq('club_id', widget.clubId)
                .order('name');

      final rows = List<Map<String, dynamic>>.from(res);

      final byId = <String, Map<String, dynamic>>{};
      for (final row in rows) {
        final id = row['id']?.toString();
        if (id != null && id.isNotEmpty) {
          byId[id] = row;
        }
      }

      _allTypes = byId.values.toList()
        ..sort(
          (a, b) => (a['name'] ?? '').toString().compareTo(
            (b['name'] ?? '').toString(),
          ),
        );
    } catch (e) {
      _typesError = e.toString();
      debugPrint('Error loading fixture types: $e');
    }

    if (mounted) {
      setState(() {
        _loadingTypes = false;
      });
    }
  }
}
