import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'club_online_scaffold.dart';

bool isOpponentClubResult(Map<String, dynamic> place) =>
    place['placeId'] != null &&
    place['businessStatus'] != 'CLOSED_PERMANENTLY' &&
    !RegExp(
      r'\b(car park|parking|bowls shop|bowling shop)\b',
      caseSensitive: false,
    ).hasMatch('${place['name'] ?? ''}');

/// A conservative match: Google identity, or full name and postcode together.
bool sameOpponentPlace(Map<String, dynamic> a, Map<String, dynamic> b) {
  String key(dynamic v) =>
      '$v'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final id = a['placeId'] ?? a['google_place_id'];
  final other = b['placeId'] ?? b['google_place_id'];
  if (id != null && '$id'.isNotEmpty && id == other) return true;
  final postcode = key(a['postcode'] ?? '');
  return postcode.isNotEmpty &&
      postcode == key(b['postcode'] ?? '') &&
      key(a['name']) == key(b['name']);
}

class OpponentDiscoveryScreen extends StatefulWidget {
  const OpponentDiscoveryScreen({super.key, required this.clubId});
  final String clubId;
  @override
  State<OpponentDiscoveryScreen> createState() =>
      _OpponentDiscoveryScreenState();
}

class _OpponentDiscoveryScreenState extends State<OpponentDiscoveryScreen> {
  final _query = TextEditingController();
  final _selected = <String>{};
  final _failures = <String, String>{};
  List<Map<String, dynamic>> _venues = [], _places = [], _centres = [];
  Map<String, dynamic> _home = {}, _matches = {}, _centre = {};
  bool _busy = true;
  String? _error, _message;
  double _radius = 20;
  SupabaseClient get _client => Supabase.instance.client;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      _venues = List<Map<String, dynamic>>.from(
        await _client.from('venues').select().eq('club_id', widget.clubId),
      );
      _home = _venues.firstWhere(
        (v) => v['is_home_venue'] == true,
        orElse: () => {},
      );
      if (_home['latitude'] != null && _home['longitude'] != null) {
        _centre = {
          'name': _home['name'],
          'latitude': _home['latitude'],
          'longitude': _home['longitude'],
        };
      }
      _query.text = '${_home['name'] ?? ''} ${_home['postcode'] ?? ''}'.trim();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<Map<String, dynamic>> _google(Map<String, dynamic> body) async {
    final result = await _client.functions.invoke(
      'venue-places',
      body: {'clubId': widget.clubId, ...body},
    );
    final data = Map<String, dynamic>.from(result.data as Map);
    if (result.status != 200 || data['error'] != null)
      throw StateError('${data['error'] ?? 'Venue search unavailable'}');
    return data;
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await work();
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  bool _saved(Map<String, dynamic> p) =>
      _venues.any((v) => sameOpponentPlace(p, v));
  Future<void> _findCentre() => _run(() async {
    final data = await _google({
      'action': 'search',
      'mode': 'general',
      'query': _query.text.trim(),
    });
    _centres = List<Map<String, dynamic>>.from(data['places'] as List? ?? []);
    if (_centres.isEmpty)
      _message = 'No location found. Try your postcode or a nearby landmark.';
  });
  Future<void> _search({bool named = false}) => _run(() async {
    _selected.clear();
    _places = [];
    _matches = {};
    _failures.clear();
    final data = await _google(
      named
          ? {
              'action': 'search',
              'mode': 'bowls_club',
              'query': _query.text.trim(),
            }
          : {
              'action': 'nearby_bowls',
              'latitude': _centre['latitude'],
              'longitude': _centre['longitude'],
              'radiusMetres': _radius * 1609.344,
            },
    );
    var places = List<Map<String, dynamic>>.from(data['places'] as List? ?? []);
    final unique = <String, Map<String, dynamic>>{};
    for (var p in places) {
      if (!isOpponentClubResult(p) || sameOpponentPlace(p, _home)) continue;
      unique['${p['placeId']}'] = p;
    }
    var reviewed = unique.values.take(20).toList();
    // Search results omit postal components; load details before matching.
    if (named) {
      reviewed = [
        for (final p in reviewed)
          Map<String, dynamic>.from(
            (await _google({
                  'action': 'details',
                  'placeId': p['placeId'],
                }))['place']
                as Map,
          ),
      ];
    }
    reviewed = reviewed.where((p) => !sameOpponentPlace(p, _home)).toList();
    final matches = Map<String, dynamic>.from(
      await _client.rpc(
            'match_staging_opponent_venues',
            params: {'p_club': widget.clubId, 'p_places': reviewed},
          )
          as Map,
    );
    _places = reviewed;
    _matches = matches;
    _selected.clear();
    _failures.clear();
    _selected.addAll(
      _places.where((p) => !_saved(p)).map((p) => '${p['placeId']}'),
    );
    if (_places.isEmpty)
      _message =
          'No clubs found in this search. Try a wider area or search by name.';
  });
  Future<void> _save() => _run(() async {
    var added = 0;
    _failures.clear();
    for (final p
        in _places
            .where((p) => _selected.contains('${p['placeId']}'))
            .toList()) {
      try {
        await _client.rpc(
          'create_club_venue',
          params: {
            'p_club_id': widget.clubId,
            'p_name': p['name'],
            'p_is_home_venue': false,
            'p_address_line1': p['addressLine1'],
            'p_town_city': p['townCity'],
            'p_postcode': p['postcode'],
            'p_latitude': p['latitude'],
            'p_longitude': p['longitude'],
            'p_google_place_id': p['placeId'],
            'p_contact_phone': p['phone'],
            'p_website_url': p['websiteUrl'],
            'p_google_maps_url': p['googleMapsUrl'],
            'p_directions_url': p['googleMapsUrl'],
            'p_allow_possible_duplicate': false,
          },
        );
        _venues.add({
          'name': p['name'],
          'postcode': p['postcode'],
          'google_place_id': p['placeId'],
        });
        _selected.remove('${p['placeId']}');
        added++;
      } catch (e) {
        _failures['${p['placeId']}'] = '$e';
      }
    }
    _message =
        '$added opponent venues added. No invitations or messages were sent.';
  });
  @override
  Widget build(BuildContext context) => ClubOnlineScaffold(
    appBar: AppBar(title: const Text('Find your opponent clubs')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Build your opponent list',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const Text(
            'Find up to 20 nearby bowls clubs, review their addresses, then add the ones you play. Google results are a starting point, not a complete directory. You can find more clubs later from Venues.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _query,
            decoration: const InputDecoration(
              labelText: 'Club name, town or postcode',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: _busy ? null : _findCentre,
                child: const Text('Find search location'),
              ),
              OutlinedButton(
                onPressed: _busy ? null : () => _search(named: true),
                child: const Text('Find another club by name'),
              ),
            ],
          ),
          if (_centres.isNotEmpty) ...[
            const Text(
              'Choose the correct location for this search. This does not change your home address.',
            ),
            for (final c in _centres)
              ListTile(
                title: Text('${c['name']}'),
                subtitle: Text('${c['formattedAddress'] ?? ''}'),
                trailing: const Icon(Icons.place_outlined),
                onTap: _busy
                    ? null
                    : () => setState(() {
                        _centre = c;
                        _centres = [];
                      }),
              ),
          ],
          if (_centre.isNotEmpty) ...[
            Text('Searching around ${_centre['name']}'),
            DropdownButtonFormField<double>(
              initialValue: _radius,
              decoration: const InputDecoration(labelText: 'Search radius'),
              items: [5.0, 10.0, 20.0, 30.0]
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text('${r.toInt()} miles'),
                    ),
                  )
                  .toList(),
              onChanged: _busy ? null : (r) => setState(() => _radius = r!),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : () => _search(),
              icon: const Icon(Icons.travel_explore),
              label: const Text('Find nearby clubs'),
            ),
          ],
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Color(0xff991b1b))),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _message!,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          for (final p in _places)
            Card(
              child: CheckboxListTile(
                value: _saved(p) || _selected.contains('${p['placeId']}'),
                onChanged: _busy || _saved(p)
                    ? null
                    : (v) => setState(
                        () => v == true
                            ? _selected.add('${p['placeId']}')
                            : _selected.remove('${p['placeId']}'),
                      ),
                title: Text('${p['name']}'),
                subtitle: Text(
                  [
                    '${p['formattedAddress'] ?? [p['addressLine1'], p['townCity'], p['postcode']].whereType<String>().join(', ')}',
                    if (p['distanceMiles'] is num)
                      '${(p['distanceMiles'] as num).toStringAsFixed(1)} miles away in a straight line',
                    if (_saved(p)) 'Already in your venues — kept unchanged',
                    if (_matches['${p['placeId']}'] is List &&
                        (_matches['${p['placeId']}'] as List).isNotEmpty)
                      'Known venue at: ${(_matches['${p['placeId']}'] as List).join(', ')}',
                    if (_failures['${p['placeId']}'] != null)
                      'Not added: ${_failures['${p['placeId']}']}. Review this venue in Venues before trying again.',
                  ].join('\n'),
                ),
              ),
            ),
          if (_places.isNotEmpty)
            FilledButton(
              onPressed: _busy || _selected.isEmpty ? null : _save,
              child: Text('Add ${_selected.length} selected opponent venues'),
            ),
          const SizedBox(height: 12),
          const Text(
            'Existing venues are not overwritten. Adding an opponent venue does not create a club account or contact its members.',
          ),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Done for now'),
          ),
        ],
      ),
    ),
  );
}
