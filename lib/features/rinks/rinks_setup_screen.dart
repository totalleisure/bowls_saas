import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RinksSetupScreen extends StatefulWidget {
  final String fixtureId;
  final bool isHome;

  const RinksSetupScreen({
    super.key,
    required this.fixtureId,
    required this.isHome,
  });

  @override
  State<RinksSetupScreen> createState() => _RinksSetupScreenState();
}

class _RinksSetupScreenState extends State<RinksSetupScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _rinks = [];

  Map<String, dynamic>? _green;
  List<String> _allRinkNames = [];

  List<String> _buildRinkNames(Map<String, dynamic> g) {
    final schemeType = (g['scheme_type'] ?? 'numeric').toString();
    final prefix = (g['scheme_prefix'] ?? '').toString();
    final padding = (g['scheme_padding'] as int?) ?? 0;
    final rinkCount = (g['rink_count'] as int?) ?? 0;

    if (rinkCount <= 0) return [];

    if (schemeType == 'custom_list') {
      final raw = g['custom_labels'];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      return [];
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

  List<String> _availableRinksFor(String? current) {
    final used = _rinks
        .map((r) => r['home_rink_label'] as String?)
        .where((e) => e != null && e.isNotEmpty)
        .cast<String>()
        .toSet();

    if (current != null && current.isNotEmpty) {
      used.remove(current); // allow current selection
    }

    return _allRinkNames.where((r) => !used.contains(r)).toList();
  }

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

      // Load fixture (to get green_id)
      final fixture = await client
          .from('fixtures')
          .select('green_area_id')
          .eq('id', widget.fixtureId)
          .single();

      final greenId = fixture['green_area_id'];

      Map<String, dynamic>? green;

      if (widget.isHome && greenId != null) {
        green = await client
            .from('green_areas')
            .select(
              'id, rink_count, scheme_type, scheme_prefix, '
              'scheme_padding, custom_labels',
            )
            .eq('id', greenId)
            .single();
      }

      final rows = await client
          .from('fixture_rinks')
          .select(
            'id, fixture_rink_no, format, players_per_rink, home_rink_label',
          )
          .eq('fixture_id', widget.fixtureId)
          .order('fixture_rink_no', ascending: true);

      setState(() {
        _rinks = List<Map<String, dynamic>>.from(rows);
        _green = green;
        _allRinkNames = green != null ? _buildRinkNames(green) : [];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int _playersForFormat(String format) {
    if (format == 'pairs') return 2;
    if (format == 'triples') return 3;
    return 4;
  }

  Future<void> _addRink() async {
    String format = 'rinks';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add team'),
        content: DropdownButtonFormField<String>(
          value: format,
          decoration: const InputDecoration(labelText: 'Format'),
          items: const [
            DropdownMenuItem(value: 'rinks', child: Text('Rinks (4)')),
            DropdownMenuItem(value: 'triples', child: Text('Triples (3)')),
            DropdownMenuItem(value: 'pairs', child: Text('Pairs (2)')),
          ],
          onChanged: (v) => format = v ?? 'rinks',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final nextOrder = (_rinks.isEmpty)
        ? 1
        : (_rinks
                  .map((r) => r['fixture_rink_no'] as int)
                  .reduce((a, b) => a > b ? a : b) +
              1);

    final ppr = _playersForFormat(format);

    try {
      await Supabase.instance.client.from('fixture_rinks').insert({
        'fixture_id': widget.fixtureId,
        'fixture_rink_no': nextOrder,
        'format': format,
        'players_per_rink': ppr,
      });

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Add team failed: $e')));
      }
    }
  }

  Future<void> _deleteRink(String rinkId) async {
    try {
      await Supabase.instance.client
          .from('fixture_rinks')
          .delete()
          .eq('id', rinkId);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<void> _editHomeLabel(Map<String, dynamic> rink) async {
    if (_green == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No green assigned to this fixture')),
      );
      return;
    }

    String? selected = (rink['home_rink_label'] as String?);

    final options = _availableRinksFor(selected);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Select rink (Team ${rink['fixture_rink_no']})'),
        content: DropdownButtonFormField<String>(
          value: selected,
          items: options
              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
              .toList(),
          onChanged: (v) => selected = v,
          decoration: const InputDecoration(labelText: 'Rink'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      await Supabase.instance.client
          .from('fixture_rinks')
          .update({'home_rink_label': selected})
          .eq('id', rink['id'].toString());

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  String _formatLabel(String f) {
    if (f == 'pairs') return 'Pairs';
    if (f == 'triples') return 'Triples';
    return 'Rinks';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teams setup'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _addRink, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.isHome && _allRinkNames.isNotEmpty) ...[
                    const Text(
                      'Available rinks:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(_allRinkNames.join(', ')),
                    const SizedBox(height: 12),
                  ],

                  Text(
                    widget.isHome
                        ? 'Home fixture: you can assign a home rink label to each team.'
                        : 'Away fixture: teams can be set up, but home rink labels are not needed.',
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _addRink,
                          icon: const Icon(Icons.add),
                          label: const Text('Add team'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_rinks.isEmpty)
                    const Text('No teams yet. Tap "Add team" to add one.')
                  else
                    ..._rinks.map((r) {
                      final label = (r['home_rink_label'] as String?) ?? '';
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          dense: true,
                          title: Text(
                            'Team ${r['fixture_rink_no']} • ${_formatLabel(r['format'].toString())} • ${r['players_per_rink']} players',
                          ),
                          subtitle: widget.isHome && label.isNotEmpty
                              ? Text('Home rink: $label')
                              : null,
                          onTap: widget.isHome ? () => _editHomeLabel(r) : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deleteRink(r['id'].toString()),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
