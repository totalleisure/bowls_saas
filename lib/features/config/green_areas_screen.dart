import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

class GreenAreasScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const GreenAreasScreen({super.key, required this.clubId, required this.clubName});

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
              .select('id, name, discipline, orientation_mode, venues!inner(id, name, club_id, is_home_venue)')
              .eq('venues.club_id', widget.clubId)
              .eq('venues.is_home_venue', true)
              .order('name');

      _venues = List<Map<String, dynamic>>.from(venues);
      _greenAreas = List<Map<String, dynamic>>.from(greens)
          .where((g) => (g['venues']?['is_home'] as bool?) == true)
          .toList();
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createGreenArea() async {
    if (_venues.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Create a venue first.')),
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
          title: const Text('Create green area'),
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
                  decoration: const InputDecoration(labelText: 'Venue'),
                ),
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Green area name')),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: discipline,
                  items: const [
                    DropdownMenuItem(value: 'indoor', child: Text('Indoor')),
                    DropdownMenuItem(value: 'outdoor', child: Text('Outdoor')),
                  ],
                  onChanged: (v) => setD(() {
                    discipline = v!;
                    // auto-adjust orientation defaults
                    orientationMode = (discipline == 'outdoor') ? 'required' : 'not_applicable';
                    allowedOrients = (discipline == 'outdoor') ? ['north_south'] : [];
                  }),
                  decoration: const InputDecoration(labelText: 'Discipline'),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  initialValue: rinkCount.toString(),
                  decoration: const InputDecoration(labelText: 'Rink count'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setD(() => rinkCount = int.tryParse(v) ?? rinkCount),
                ),
                const Divider(height: 24),
                DropdownButtonFormField<String>(
                  value: schemeType,
                  items: const [
                    DropdownMenuItem(value: 'numeric', child: Text('Numeric (1..N)')),
                    DropdownMenuItem(value: 'alpha', child: Text('Alpha (A..Z)')),
                    DropdownMenuItem(value: 'custom_list', child: Text('Custom list')),
                  ],
                  onChanged: (v) => setD(() => schemeType = v!),
                  decoration: const InputDecoration(labelText: 'Rink naming scheme'),
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Prefix (optional)'),
                  onChanged: (v) => setD(() => prefix = v),
                ),
                TextFormField(
                  initialValue: padding.toString(),
                  decoration: const InputDecoration(labelText: 'Padding (0..6)'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setD(() => padding = int.tryParse(v) ?? padding),
                ),
                if (schemeType == 'custom_list')
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Custom labels (CSV)',
                      hintText: 'e.g. R1,R2,R3,R4,...',
                    ),
                    onChanged: (v) => setD(() => customLabelsCsv = v),
                  ),
                const Divider(height: 24),
                DropdownButtonFormField<String>(
                  value: orientationMode,
                  items: const [
                    DropdownMenuItem(value: 'not_applicable', child: Text('Not applicable')),
                    DropdownMenuItem(value: 'required', child: Text('Required')),
                    DropdownMenuItem(value: 'optional', child: Text('Optional')),
                  ],
                  onChanged: (v) => setD(() => orientationMode = v!),
                  decoration: const InputDecoration(labelText: 'Outdoor orientation rule'),
                ),
                if (discipline == 'outdoor' && orientationMode != 'not_applicable')
                  Column(
                    children: [
                      CheckboxListTile(
                        value: allowedOrients.contains('north_south'),
                        onChanged: (v) => setD(() {
                          v == true ? allowedOrients.add('north_south') : allowedOrients.remove('north_south');
                        }),
                        title: const Text('North/South'),
                      ),
                      CheckboxListTile(
                        value: allowedOrients.contains('east_west'),
                        onChanged: (v) => setD(() {
                          v == true ? allowedOrients.add('east_west') : allowedOrients.remove('east_west');
                        }),
                        title: const Text('East/West'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Green area created ✅')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Create green area error: $e')));
      }
    }
  }

  String _venueNameFor(String venueId) {
    final v = _venues.firstWhere((x) => x['id'] == venueId, orElse: () => {'name': 'Unknown'});
    return v['name'] as String;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Greens — ${widget.clubName}'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createGreenArea,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView.builder(
                  itemCount: _greenAreas.length,
                  itemBuilder: (_, i) {
                    final g = _greenAreas[i];
                    final name = g['name'] as String;
                    final discipline = g['discipline'] as String;
                    final rinks = g['rink_count'] as int;
                    final scheme = g['scheme_type'] as String;
                    final venue = _venueNameFor(g['venue_id'] as String);
                    final om = g['orientation_mode'] as String;
                    return ListTile(
                      title: Text(name),
                      subtitle: Text('$venue • $discipline • $rinks rinks • $scheme • orient:$om'),
                    );
                  },
                ),
    );
  }
}


