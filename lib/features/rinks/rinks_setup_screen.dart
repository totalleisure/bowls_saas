import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

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
      final rows = await Supabase.instance.client
          .from('fixture_rinks')
          .select('id, fixture_rink_no, format, players_per_rink, home_rink_label')
          .eq('fixture_id', widget.fixtureId)
          .order('fixture_rink_no');

      setState(() {
        _rinks = List<Map<String, dynamic>>.from(rows);
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
    return 4; // 'rinks'
  }

  Future<void> _addRink() async {
    String format = 'rinks';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add rink'),
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
        : (_rinks.map((r) => r['fixture_rink_no'] as int).reduce((a, b) => a > b ? a : b) + 1);

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Add rink failed: $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _editHomeLabel(Map<String, dynamic> rink) async {
    final ctrl = TextEditingController(text: (rink['home_rink_label'] as String?) ?? '');

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Home rink label (Rink ${rink['fixture_rink_no']})'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Label',
            hintText: 'e.g. Rink 3, A, N4',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok != true) return;

    final label = ctrl.text.trim();
    try {
      await Supabase.instance.client
          .from('fixture_rinks')
          .update({'home_rink_label': label.isEmpty ? null : label})
          .eq('id', rink['id'].toString());

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
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
        title: const Text('Rinks setup'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: _addRink, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      widget.isHome
                          ? 'Home fixture: you can label home rinks.'
                          : 'Away fixture: rink labels are not needed.',
                    ),

                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _addRink,
                            icon: const Icon(Icons.add),
                            label: const Text('Add rink'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_rinks.isEmpty)
                      const Text('No rinks yet. Tap "Add rink" to add one.')
                    else
                      ..._rinks.map((r) {
                        final label = (r['home_rink_label'] as String?) ?? '';
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            dense: true,
                            title: Text(
                              'Rink ${r['fixture_rink_no']} • ${_formatLabel(r['format'].toString())} • ${r['players_per_rink']} players',
                            ),
                            subtitle: widget.isHome && label.isNotEmpty
                                ? Text('Label: $label')
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
    );
  }
}


