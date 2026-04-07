import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GreenAreasScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const GreenAreasScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  State<GreenAreasScreen> createState() => _GreenAreasScreenState();
}

class _GreenAreasScreenState extends State<GreenAreasScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _venues = [];
  List<Map<String, dynamic>> _greenAreas = [];

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

      final venues = await client
          .from('venues')
          .select('id, name')
          .eq('club_id', widget.clubId)
          .eq('is_home_venue', true)
          .order('name');

      final greens = await client
          .from('green_areas')
          .select(
            'id, venue_id, name, discipline, rink_count, scheme_type, '
            'scheme_prefix, scheme_padding, custom_labels, '
            'orientation_mode, allowed_orientations, '
            'venues!inner(id, name, club_id, is_home_venue)',
          )
          .eq('venues.club_id', widget.clubId)
          .eq('venues.is_home_venue', true)
          .order('name');

      _venues = List<Map<String, dynamic>>.from(venues);
      _greenAreas = List<Map<String, dynamic>>.from(greens);
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _createGreenArea() async {
    if (_venues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a home venue first.')),
      );
      return;
    }

    final name = TextEditingController();
    int rinkCount = 6;
    String discipline = 'indoor';
    String schemeType = 'numeric';
    String prefix = '';
    int padding = 0;
    String customLabelsCsv = '';
    String orientationMode = 'not_applicable';
    List<String> allowedOrients = [];
    String venueId = _venues.first['id'] as String;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Text('Create home green'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  value: venueId,
                  items: _venues
                      .map<DropdownMenuItem<String>>(
                        (v) => DropdownMenuItem<String>(
                          value: v['id'] as String,
                          child: Text(v['name'] as String),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setD(() => venueId = v!),
                  decoration: const InputDecoration(labelText: 'Home venue'),
                ),
                TextField(
                  controller: name,
                  decoration:
                      const InputDecoration(labelText: 'Green area name'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: discipline,
                  items: const [
                    DropdownMenuItem(value: 'indoor', child: Text('Indoor')),
                    DropdownMenuItem(value: 'outdoor', child: Text('Outdoor')),
                  ],
                  onChanged: (v) => setD(() {
                    discipline = v!;
                    orientationMode = (discipline == 'outdoor')
                        ? 'required'
                        : 'not_applicable';
                    allowedOrients =
                        (discipline == 'outdoor') ? ['north_south'] : [];
                  }),
                  decoration: const InputDecoration(labelText: 'Discipline'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: rinkCount.toString(),
                  decoration: const InputDecoration(labelText: 'Rink count'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      setD(() => rinkCount = int.tryParse(v) ?? rinkCount),
                ),
                const Divider(height: 24),
                DropdownButtonFormField<String>(
                  value: schemeType,
                  items: const [
                    DropdownMenuItem(
                      value: 'numeric',
                      child: Text('Numeric (1..N)'),
                    ),
                    DropdownMenuItem(
                      value: 'alpha',
                      child: Text('Alpha (A..Z)'),
                    ),
                    DropdownMenuItem(
                      value: 'custom_list',
                      child: Text('Custom list'),
                    ),
                  ],
                  onChanged: (v) => setD(() => schemeType = v!),
                  decoration:
                      const InputDecoration(labelText: 'Rink naming scheme'),
                ),
                TextField(
                  decoration:
                      const InputDecoration(labelText: 'Prefix (optional)'),
                  onChanged: (v) => setD(() => prefix = v),
                ),
                TextFormField(
                  initialValue: padding.toString(),
                  decoration:
                      const InputDecoration(labelText: 'Padding (0..6)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      setD(() => padding = int.tryParse(v) ?? padding),
                ),
                if (schemeType == 'custom_list')
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Custom labels (CSV)',
                      hintText: 'e.g. M1,M2,M3,M4',
                    ),
                    onChanged: (v) => setD(() => customLabelsCsv = v),
                  ),
                const Divider(height: 24),
                DropdownButtonFormField<String>(
                  value: orientationMode,
                  items: const [
                    DropdownMenuItem(
                      value: 'not_applicable',
                      child: Text('Not applicable'),
                    ),
                    DropdownMenuItem(
                      value: 'required',
                      child: Text('Required'),
                    ),
                    DropdownMenuItem(
                      value: 'optional',
                      child: Text('Optional'),
                    ),
                  ],
                  onChanged: (v) => setD(() => orientationMode = v!),
                  decoration: const InputDecoration(
                    labelText: 'Outdoor orientation rule',
                  ),
                ),
                if (discipline == 'outdoor' &&
                    orientationMode != 'not_applicable')
                  Column(
                    children: [
                      CheckboxListTile(
                        value: allowedOrients.contains('north_south'),
                        onChanged: (v) => setD(() {
                          if (v == true) {
                            if (!allowedOrients.contains('north_south')) {
                              allowedOrients.add('north_south');
                            }
                          } else {
                            allowedOrients.remove('north_south');
                          }
                        }),
                        title: const Text('North/South'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        value: allowedOrients.contains('east_west'),
                        onChanged: (v) => setD(() {
                          if (v == true) {
                            if (!allowedOrients.contains('east_west')) {
                              allowedOrients.add('east_west');
                            }
                          } else {
                            allowedOrients.remove('east_west');
                          }
                        }),
                        title: const Text('East/West'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final greenName = name.text.trim();
    if (greenName.isEmpty) return;

    final customLabels = schemeType == 'custom_list'
        ? customLabelsCsv
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : null;

    try {
      await Supabase.instance.client.from('green_areas').insert({
        'club_id': widget.clubId,
        'venue_id': venueId,
        'name': greenName,
        'discipline': discipline,
        'rink_count': rinkCount,
        'scheme_type': schemeType,
        'scheme_prefix': prefix,
        'scheme_padding': padding,
        'custom_labels': customLabels,
        'orientation_mode': orientationMode,
        'allowed_orientations': allowedOrients,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Home green created ✅')),
        );
      }

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Create green area error: $e')),
        );
      }
    }
  }

  String _venueNameFor(String venueId) {
    final v = _venues.firstWhere(
      (x) => x['id'] == venueId,
      orElse: () => {'name': 'Unknown'},
    );
    return (v['name'] ?? 'Unknown').toString();
  }

  List<String> _buildRinkNames(Map<String, dynamic> g) {
    final schemeType = (g['scheme_type'] ?? 'numeric').toString();
    final prefix = (g['scheme_prefix'] ?? '').toString();
    final padding = (g['scheme_padding'] as int?) ?? 0;
    final rinkCount = (g['rink_count'] as int?) ?? 0;

    if (rinkCount <= 0) return const [];

    if (schemeType == 'custom_list') {
      final raw = g['custom_labels'];
      if (raw is List) {
        return raw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    if (schemeType == 'alpha') {
      return List.generate(rinkCount, (i) {
        final letter = String.fromCharCode(65 + i);
        return '$prefix$letter';
      });
    }

    return List.generate(rinkCount, (i) {
      final n = (i + 1).toString().padLeft(padding, '0');
      return '$prefix$n';
    });
  }

  String _orientationText(Map<String, dynamic> g) {
    final mode = (g['orientation_mode'] ?? 'not_applicable').toString();
    final allowed = (g['allowed_orientations'] is List)
        ? (g['allowed_orientations'] as List)
            .map((e) => e.toString())
            .toList()
        : <String>[];

    if (mode == 'not_applicable') return 'Orientation: not applicable';
    if (allowed.isEmpty) return 'Orientation: $mode';

    final pretty = allowed.map((e) {
      switch (e) {
        case 'north_south':
          return 'North/South';
        case 'east_west':
          return 'East/West';
        default:
          return e;
      }
    }).join(', ');

    return 'Orientation: $mode ($pretty)';
  }

  Widget _buildGreenCard(Map<String, dynamic> g) {
    final name = (g['name'] ?? '').toString();
    final discipline = (g['discipline'] ?? '').toString();
    final rinks = (g['rink_count'] as int?) ?? 0;
    final scheme = (g['scheme_type'] ?? '').toString();
    final venue = _venueNameFor(g['venue_id'] as String);
    final rinkNames = _buildRinkNames(g);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.isEmpty ? 'Unnamed green' : name,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text('$venue • $discipline • $rinks rinks • $scheme'),
            const SizedBox(height: 4),
            Text(_orientationText(g)),
            if (rinkNames.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'The rinks on this Green will be called',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(rinkNames.join(', ')),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Home Greens — ${widget.clubName}'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createGreenArea,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _greenAreas.isEmpty
                  ? const Center(
                      child: Text('No home greens have been set up yet.'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _greenAreas.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 12),
                      itemBuilder: (_, i) => _buildGreenCard(_greenAreas[i]),
                    ),
    );
  }
}