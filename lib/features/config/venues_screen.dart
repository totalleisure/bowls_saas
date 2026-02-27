import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

class VenuesScreen extends StatefulWidget {
  final String clubId;
  final String clubName;

  const VenuesScreen({super.key, required this.clubId, required this.clubName});

  @override
  State<VenuesScreen> createState() => _VenuesScreenState();
}


class _VenuesScreenState extends State<VenuesScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _venues = [];

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
          .from('venues')
          .select('id, name, is_home_venue, town_city, postcode')
          .eq('club_id', widget.clubId)
          .order('name');

      _venues = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createVenue() async {
    final name = TextEditingController();
    final town = TextEditingController();
    final postcode = TextEditingController();
    bool isHome = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Create venue'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Venue name')),
                TextField(controller: town, decoration: const InputDecoration(labelText: 'Town/City (optional)')),
                TextField(controller: postcode, decoration: const InputDecoration(labelText: 'Postcode (optional)')),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: isHome,
                  onChanged: (v) => setStateDialog(() => isHome = v),
                  title: const Text('Home venue'),
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
    final venueName = name.text.trim();
    if (venueName.isEmpty) return;

    try {
      await Supabase.instance.client.from('venues').insert({
        'club_id': widget.clubId,
        'name': venueName,
        'is_home_venue': isHome,
        'town_city': town.text.trim().isEmpty ? null : town.text.trim(),
        'postcode': postcode.text.trim().isEmpty ? null : postcode.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Venue created ✅')));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Create venue error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Venues — ${widget.clubName}'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createVenue,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView.builder(
                  itemCount: _venues.length,
                  itemBuilder: (_, i) {
                    final v = _venues[i];
                    final name = v['name'] as String;
                    final isHome = v['is_home_venue'] as bool;
                    return ListTile(
                      tileColor: isHome
                          ? Colors.green.withOpacity(0.08)
                          : Colors.orange.withOpacity(0.08),
                      title: Text(name),
                      subtitle: Text([
                        if ((v['address'] ?? '').toString().isNotEmpty) v['address'].toString(),
                        if ((v['phone'] ?? '').toString().isNotEmpty) v['phone'].toString(),
                      ].join(' • ')),
                    );
                    final town = v['town_city'] as String?;
                    final pc = v['postcode'] as String?;
                    return ListTile(
                      title: Text(name),
                      subtitle: Text([
                        if (isHome) 'Home' else 'Opponent',
                        if (town != null && town.isNotEmpty) town,
                        if (pc != null && pc.isNotEmpty) pc,
                      ].join(' • ')),
                    );
                  },
                ),
    );
  }
}


