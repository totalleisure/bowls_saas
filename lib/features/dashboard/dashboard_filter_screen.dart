import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../../models/dashboard_fixture_filter.dart';

class DashboardFilterScreen extends StatefulWidget {
  final DashboardFixtureFilter initialFilter;
  final String clubId;

  const DashboardFilterScreen({
    super.key,
    required this.initialFilter,
    required this.clubId,
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

  List<Map<String, dynamic>> get _visibleTypes {
    return _allTypes.where((t) {
      final section = (t['section'] ?? '').toString().toLowerCase().trim();
      final isInternal = t['is_internal'] == true;

      if (_draft.sections.isNotEmpty && !_draft.sections.contains(section)) {
        return false;
      }

      if (_draft.categories.isNotEmpty) {
        final tags = (t['tags'] as List<dynamic>? ?? const [])
            .map((e) => e.toString().toLowerCase().trim())
            .toSet();

        bool matched = false;

        for (final selected in _draft.categories) {
          if (selected == 'internal') {
            if (isInternal) {
              matched = true;
              break;
            }
          } else {
            if (tags.contains(selected)) {
              matched = true;
              break;
            }
          }
        }

        if (!matched) return false;
      }

      return true;
    }).toList();
  }

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
      _draft = _draft.copyWith(sections: set);
    });
  }

  void _toggleCategory(String value) {
    final set = Set<String>.from(_draft.categories);
    set.contains(value) ? set.remove(value) : set.add(value);

    setState(() {
      _draft = _draft.copyWith(categories: set);
    });
  }

  void _setPeriod(String value) {
    setState(() {
      _draft = _draft.copyWith(period: value);
    });
  }

  void _toggleFixtureType(String id) {
    final set = Set<String>.from(_draft.fixtureTypeIds);

    set.contains(id) ? set.remove(id) : set.add(id);

    setState(() {
      _draft = _draft.copyWith(fixtureTypeIds: set);
    });
  }

  // --------------------------
  // UI
  // --------------------------

  Widget _buildFixtureTypes() {
    if (_loadingTypes) {
      return const Center(child: CircularProgressIndicator());
    }

    final types = _visibleTypes;

    if (types.isEmpty) {
      return const Text(
        'No fixture types match current filters',
        style: TextStyle(color: Colors.grey),
      );
    }

    return _buildBlock(
      title: 'Fixture Types',
      children: types.map((t) {
        final id = t['id'].toString();
        final name = (t['name'] ?? '').toString();
        final selected = _draft.fixtureTypeIds.contains(id);

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
        title: const Text('Filter fixtures'),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _draft = const DashboardFixtureFilter();
              });
            },
            child: const Text('Clear'),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _changed ? Colors.red : Colors.grey,
        label: Text(_changed ? 'Save' : 'Return'),
        icon: Icon(_changed ? Icons.check : Icons.arrow_back),
        onPressed: () {
          Navigator.pop(context, _changed ? _draft : widget.initialFilter);
        },
      ),

      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionFilter(),
          const SizedBox(height: 24),
          _buildCategoryFilter(),
          const SizedBox(height: 24),
          _buildPeriodFilter(),
          const SizedBox(height: 24),

          // placeholder for next phase
          const Divider(),
          _buildFixtureTypes(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // --------------------------
  // SECTIONS
  // --------------------------

  Widget _buildSectionFilter() {
    return _buildBlock(
      title: 'Section',
      children: [
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
    return _buildBlock(
      title: 'Tags',
      children: [
        _chip(
          label: 'Matches',
          selected: _draft.categories.contains('match'),
          onTap: () => _toggleCategory('match'),
        ),
        _chip(
          label: 'Leagues',
          selected: _draft.categories.contains('league'),
          onTap: () => _toggleCategory('league'),
        ),
        _chip(
          label: 'Competitions',
          selected: _draft.categories.contains('competition'),
          onTap: () => _toggleCategory('competition'),
        ),
        _chip(
          label: 'Drives',
          selected: _draft.categories.contains('drive'),
          onTap: () => _toggleCategory('drive'),
        ),
        _chip(
          label: 'Roll-Ups',
          selected: _draft.categories.contains('rollup'),
          onTap: () => _toggleCategory('rollup'),
        ),
        _chip(
          label: 'Events',
          selected: _draft.categories.contains('event'),
          onTap: () => _toggleCategory('event'),
        ),
        _chip(
          label: 'Friendly',
          selected: _draft.categories.contains('friendly'),
          onTap: () => _toggleCategory('friendly'),
        ),
        _chip(
          label: 'Cup',
          selected: _draft.categories.contains('cup'),
          onTap: () => _toggleCategory('cup'),
        ),
        _chip(
          label: 'Social',
          selected: _draft.categories.contains('social'),
          onTap: () => _toggleCategory('social'),
        ),
        _chip(
          label: 'Training',
          selected: _draft.categories.contains('training'),
          onTap: () => _toggleCategory('training'),
        ),
        _chip(
          label: 'Meetings',
          selected: _draft.categories.contains('meeting'),
          onTap: () => _toggleCategory('meeting'),
        ),
        _chip(
          label: 'Internal',
          selected: _draft.categories.contains('internal'),
          onTap: () => _toggleCategory('internal'),
        ),
      ],
    );
  }

  // --------------------------
  // PERIOD
  // --------------------------

  Widget _buildPeriodFilter() {
    Widget tile(String value, String label, double width) {
      final selected = _draft.period == value;

      return SizedBox(
        width: width,
        height: 34,
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
              maxLines: 1,
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
                tile('all', 'All', itemWidth),
                tile('this_month', 'This month', itemWidth),
                tile('next_month', 'Next month', itemWidth),
                tile('three_months', 'Next 3 months', itemWidth),
              ],
            ),
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
    final supabase = Supabase.instance.client;

    try {
      final res = await supabase
          .from('competition_types')
          .select(
            'id, name, section, is_internal, tags, '
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
      debugPrint('Error loading fixture types: $e');
    }

    if (mounted) {
      setState(() {
        _loadingTypes = false;
      });
    }
  }
}
