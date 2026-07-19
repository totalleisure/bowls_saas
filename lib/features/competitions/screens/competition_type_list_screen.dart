import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/hex_color.dart';
import '../models/competition_type.dart';
import 'competition_type_edit_screen.dart';

class CompetitionTypeListScreen extends StatefulWidget {
  final String clubId;
  final bool readOnly;

  const CompetitionTypeListScreen({
    super.key,
    required this.clubId,
    this.readOnly = false,
  });

  @override
  State<CompetitionTypeListScreen> createState() =>
      _CompetitionTypeListScreenState();
}

class _CompetitionTypeListScreenState extends State<CompetitionTypeListScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<CompetitionType> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _sectionLabel(String section) {
    switch (section) {
      case 'mens':
        return "Men's";
      case 'ladies':
        return 'Ladies';
      case 'mixed':
        return 'Mixed';
      default:
        return 'Open';
    }
  }

  String _dressLabel(String? dress) {
    switch (dress) {
      case 'whites':
        return 'Whites';
      case 'greys':
        return 'Greys';
      case 'blacks':
        return 'Blacks';
      default:
        return 'Unspecified';
    }
  }

  String _selectionLabel(CompetitionType row) {
    if (!row.teamSelectionEnabled) return 'None';
    switch (row.selectionMode) {
      case 'team':
        return 'Team';
      case 'rsvp':
        return 'RSVP';
      case 'practice':
        return 'Practice';
      case 'preselect':
        return 'Pre-Select';
      default:
        return 'Yes';
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _client
          .from('competition_types')
          .select('''
            id,
            club_id,
            name,
            is_internal,
            section,
            default_rinks_required,
            default_players_per_rink,
            default_duration_minutes,
            dress_code,
            team_selection_enabled,
            selection_mode,
            is_active,
            colour_scheme:fixture_colour_schemes(
              id,
              name,
              background_hex,
              foreground_hex
            )
          ''')
          .eq('club_id', widget.clubId)
          .eq('is_active', true)
          .order('name', ascending: true);

      final rows = (res as List)
          .map((e) => CompetitionType.fromMap(Map<String, dynamic>.from(e)))
          .toList();

      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openEdit({String? competitionTypeId}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CompetitionTypeEditScreen(
          clubId: widget.clubId,
          competitionTypeId: competitionTypeId,
          readOnly: widget.readOnly,
        ),
      ),
    );

    if (changed == true) {
      await _load();
    }
  }

  String _subtitle(CompetitionType row) {
    final parts = <String>[
      _sectionLabel(row.section),
      '${row.defaultRinksRequired ?? '-'} rink(s)',
      '${row.defaultPlayersPerRink ?? '-'} / rink',
      '${row.defaultDurationMinutes ?? '-'} mins',
      'Dress: ${_dressLabel(row.dressCode)}',
      'Selection: ${_selectionLabel(row)}',
    ];

    if (row.isInternal) {
      parts.add('Internal');
    }

    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Fixture Type List - Matches, Competitions and Leagues',
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: widget.readOnly
          ? null
          : FloatingActionButton(
              onPressed: () => _openEdit(),
              child: const Icon(Icons.add),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : _rows.isEmpty
          ? const Center(child: Text('No fixture types found'))
          : ListView.builder(
              itemCount: _rows.length,
              itemBuilder: (context, index) {
                final row = _rows[index];
                final hasColours = row.colourScheme != null;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Material(
                    color: hasColours
                        ? colorFromHex(
                            row.colourScheme!.backgroundHex,
                            fallback: Colors.grey.shade200,
                          )
                        : Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _openEdit(competitionTypeId: row.id),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: hasColours
                                ? colorFromHex(
                                    row.colourScheme!.foregroundHex,
                                    fallback: Colors.black87,
                                  ).withOpacity(0.25)
                                : Colors.black12,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: hasColours
                                    ? colorFromHex(
                                        row.colourScheme!.foregroundHex,
                                        fallback: Colors.black87,
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _subtitle(row),
                              style: TextStyle(
                                fontSize: 14,
                                color: hasColours
                                    ? colorFromHex(
                                        row.colourScheme!.foregroundHex,
                                        fallback: Colors.black87,
                                      ).withOpacity(0.85)
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
