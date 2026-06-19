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
            'is_outdoor, uses_sunset_cutoff, sunset_booking_offset_minutes, '
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

  Future<void> _editGreenArea([Map<String, dynamic>? existing]) async {
    if (_venues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a home venue first.')),
      );
      return;
    }

    final isEdit = existing != null;

    final name = TextEditingController(
      text: existing?['name']?.toString() ?? '',
    );

    int rinkCount = (existing?['rink_count'] as int?) ?? 6;
    String discipline = existing?['discipline']?.toString() ?? 'indoor';
    String schemeType = existing?['scheme_type']?.toString() ?? 'numeric';
    String prefix = existing?['scheme_prefix']?.toString() ?? '';
    int padding = (existing?['scheme_padding'] as int?) ?? 0;
    String orientationMode =
        existing?['orientation_mode']?.toString() ?? 'not_applicable';

    List<String> allowedOrients = existing?['allowed_orientations'] is List
        ? (existing!['allowed_orientations'] as List)
              .map((e) => e.toString())
              .toList()
        : <String>[];

    String venueId =
        existing?['venue_id']?.toString() ?? _venues.first['id'] as String;

    String customLabelsCsv = existing?['custom_labels'] is List
        ? (existing!['custom_labels'] as List).join(', ')
        : '';

    bool usesSunsetCutoff = (existing?['uses_sunset_cutoff'] as bool?) ?? false;

    int sunsetBookingOffsetMinutes =
        (existing?['sunset_booking_offset_minutes'] as int?) ?? 0;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(isEdit ? 'Edit home green' : 'Create home green'),
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
                  decoration: const InputDecoration(
                    labelText: 'Green area name',
                  ),
                ),

                const SizedBox(height: 8),
                Row(
                  children: const [
                    Icon(Icons.keyboard_arrow_down, size: 18),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Scroll down for more settings',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),

                DropdownButtonFormField<String>(
                  value: discipline,
                  items: const [
                    DropdownMenuItem(value: 'indoor', child: Text('Indoor')),
                    DropdownMenuItem(value: 'outdoor', child: Text('Outdoor')),
                  ],
                  onChanged: (v) => setD(() {
                    discipline = v!;

                    final isOutdoor = discipline == 'outdoor';

                    orientationMode = isOutdoor ? 'required' : 'not_applicable';
                    allowedOrients = isOutdoor ? ['north_south'] : [];

                    if (!isOutdoor) {
                      usesSunsetCutoff = false;
                      sunsetBookingOffsetMinutes = 0;
                    }
                  }),
                  decoration: const InputDecoration(labelText: 'Discipline'),
                ),

                const SizedBox(height: 8),

                TextFormField(
                  initialValue: rinkCount.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Rink count (1 to 16)',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setD(() {
                    final parsed = int.tryParse(v);
                    if (parsed != null) {
                      rinkCount = parsed.clamp(1, 16);
                    }
                  }),
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
                  decoration: const InputDecoration(
                    labelText: 'Rink naming scheme',
                  ),
                ),

                TextField(
                  controller: TextEditingController(text: prefix),
                  decoration: const InputDecoration(
                    labelText: 'Prefix (optional)',
                  ),
                  onChanged: (v) => setD(() => prefix = v),
                ),

                TextFormField(
                  initialValue: padding.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Padding (0..6)',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      setD(() => padding = int.tryParse(v) ?? padding),
                ),

                if (schemeType == 'custom_list')
                  TextField(
                    controller: TextEditingController(text: customLabelsCsv),
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
                          v == true
                              ? allowedOrients.add('north_south')
                              : allowedOrients.remove('north_south');
                          allowedOrients = allowedOrients.toSet().toList();
                        }),
                        title: const Text('North/South'),
                        contentPadding: EdgeInsets.zero,
                      ),
                      CheckboxListTile(
                        value: allowedOrients.contains('east_west'),
                        onChanged: (v) => setD(() {
                          v == true
                              ? allowedOrients.add('east_west')
                              : allowedOrients.remove('east_west');
                          allowedOrients = allowedOrients.toSet().toList();
                        }),
                        title: const Text('East/West'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),

                if (discipline == 'outdoor') ...[
                  const Divider(height: 24),
                  SwitchListTile(
                    value: usesSunsetCutoff,
                    onChanged: (v) => setD(() => usesSunsetCutoff = v),
                    title: const Text('Use sunset cutoff'),
                    subtitle: const Text(
                      'Restrict fixture and booking times using sunset.',
                    ),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (usesSunsetCutoff)
                    TextFormField(
                      initialValue: sunsetBookingOffsetMinutes.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Sunset booking offset minutes',
                        helperText:
                            'Use -30 for 30 minutes before sunset, 0 for sunset.',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => setD(() {
                        sunsetBookingOffsetMinutes =
                            int.tryParse(v) ?? sunsetBookingOffsetMinutes;
                      }),
                    ),
                ],
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
              child: Text(isEdit ? 'Save' : 'Create'),
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

    final data = {
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
      'is_outdoor': discipline == 'outdoor',
      'uses_sunset_cutoff': usesSunsetCutoff,
      'sunset_booking_offset_minutes': sunsetBookingOffsetMinutes,
    };

    try {
      final client = Supabase.instance.client;

      if (isEdit) {
        await client
            .from('green_areas')
            .update(data)
            .eq('id', existing['id'].toString());
      } else {
        await client.from('green_areas').insert(data);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEdit ? 'Home green updated ✅' : 'Home green created ✅',
            ),
          ),
        );
      }

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save green area error: $e')));
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
        ? (g['allowed_orientations'] as List).map((e) => e.toString()).toList()
        : <String>[];

    if (mode == 'not_applicable') return 'Orientation: not applicable';
    if (allowed.isEmpty) return 'Orientation: $mode';

    final pretty = allowed
        .map((e) {
          switch (e) {
            case 'north_south':
              return 'North/South';
            case 'east_west':
              return 'East/West';
            default:
              return e;
          }
        })
        .join(', ');

    return 'Orientation: $mode ($pretty)';
  }

  Widget _buildGreenCard(Map<String, dynamic> g) {
    final name = (g['name'] ?? '').toString();
    final discipline = (g['discipline'] ?? '').toString();
    final rinks = (g['rink_count'] as int?) ?? 0;
    final scheme = (g['scheme_type'] ?? '').toString();
    final venue = _venueNameFor(g['venue_id'] as String);
    final rinkNames = _buildRinkNames(g);
    final usesSunsetCutoff = (g['uses_sunset_cutoff'] as bool?) ?? false;
    final sunsetOffset = (g['sunset_booking_offset_minutes'] as int?) ?? 0;

    return Card(
      child: InkWell(
        onTap: () => _editGreenArea(g),
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
              if (discipline == 'outdoor') ...[
                const SizedBox(height: 4),
                Text(
                  usesSunsetCutoff
                      ? 'Sunset cutoff: yes ($sunsetOffset minutes)'
                      : 'Sunset cutoff: no',
                ),
              ],
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Home Greens — ${widget.clubName}'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editGreenArea(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : _greenAreas.isEmpty
          ? const Center(child: Text('No home greens have been set up yet.'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _greenAreas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _buildGreenCard(_greenAreas[i]),
            ),
    );
  }
}
