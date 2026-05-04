import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/competition_type.dart';
import '../../../core/utils/hex_color.dart';
import '../widgets/competition_type_colour_chip.dart';
import 'colour_scheme_picker_screen.dart';

class CompetitionTypeEditScreen extends StatefulWidget {
  final String clubId;
  final String? competitionTypeId;
  final bool readOnly;

  const CompetitionTypeEditScreen({
    super.key,
    required this.clubId,
    this.competitionTypeId,
    this.readOnly = false,
  });

  @override
  State<CompetitionTypeEditScreen> createState() =>
      _CompetitionTypeEditScreenState();
}

class _CompetitionTypeEditScreenState
    extends State<CompetitionTypeEditScreen> {
  final _client = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _rinksController = TextEditingController();
  final _playersController = TextEditingController();
  final _durationController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  
  String? _error;

  bool _isInternal = false;
  bool _usesRinks = true;
  bool _bookableByMembers = false;

  String _section = 'mens';
  String _dressCode = 'whites';
  bool _teamSelectionEnabled = false;
  String? _selectionMode;
  ColourScheme? _selectedColourScheme;

  String? _defaultFormat;

  bool get _isEdit => widget.competitionTypeId != null;

  final Set<String> _selectedTags = <String>{};

  @override
  void initState() {
    super.initState();
    _durationController.text = '180';
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rinksController.dispose();
    _playersController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    );
  }

  int? _parseInt(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  Widget _buildTagsSection() {
    Widget chip(String value, String label) {
      final selected = _selectedTags.contains(value);

      return FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: widget.readOnly
            ? null
            : (_) {
                setState(() {
                  if (selected) {
                    _selectedTags.remove(value);
                  } else {
                    _selectedTags.add(value);
                  }
                });
              },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tags',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            chip('match', 'Matches'),
            chip('league', 'Leagues'),
            chip('competition', 'Competitions'),
            chip('drive', 'Drives'),
            chip('rollup', 'Roll-Ups'),
            chip('event', 'Events'),
            chip('friendly', 'Friendly'),
            chip('cup', 'Cup'),
            chip('social', 'Social'),
            chip('training', 'Training'),
          ],
        ),
      ],
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isEdit) {
        final res = await _client
            .from('competition_types')
            .select('''
              id,
              club_id,
              name,
              is_internal,
              uses_rinks,
              bookable_by_members,              
              section,
              tags,
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
            .eq('id', widget.competitionTypeId!)
            .single()
            .order('name');

        final row = CompetitionType.fromMap(Map<String, dynamic>.from(res));

        final ppr = row.defaultPlayersPerRink;

        _defaultFormat = switch (ppr) {
          1 => 'singles',
          2 => 'pairs', // or aussie_pairs if you want to detect it later
          3 => 'triples',
          4 => 'rinks',
          _ => null,
        };

        _nameController.text = row.name;
        _rinksController.text = row.defaultRinksRequired?.toString() ?? '';
        _playersController.text = row.defaultPlayersPerRink?.toString() ?? '';
        _durationController.text = row.defaultDurationMinutes?.toString() ?? '';
        _isInternal = row.isInternal;
        
        _usesRinks = res['uses_rinks'] == true;
        _bookableByMembers = res['bookable_by_members'] == true;
        
        _section = row.section;
        _dressCode = row.dressCode ?? 'whites';
        _teamSelectionEnabled = row.teamSelectionEnabled;
        _selectionMode = row.selectionMode;
        _selectedColourScheme = row.colourScheme;
        _selectedTags
          ..clear()
          ..addAll(
            (res['tags'] as List<dynamic>? ?? const [])
                .map((e) => e.toString().toLowerCase().trim()),
          );        
      }

      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickColours() async {
    final selected = await Navigator.of(context).push<ColourScheme>(
      MaterialPageRoute(
        builder: (_) => ColourSchemePickerScreen(
          initialSelectedId: _selectedColourScheme?.id,
          previewText: _nameController.text.trim(),
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _selectedColourScheme = selected;
      });
    }
  }

  Future<void> _save() async {
    if (widget.readOnly) return;
    if (!_formKey.currentState!.validate()) return;

    final rinks = _parseInt(_rinksController.text);
    final players = _parseInt(_playersController.text);
    final duration = _parseInt(_durationController.text);

    if (_teamSelectionEnabled &&
        (_selectionMode == null || _selectionMode!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose Team, RSVP or Practice'),
        ),
      );
      return;
    }

    if (!_usesRinks && _bookableByMembers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only fixture types that use rinks can be bookable by members.'),
        ),
      );
      return;
    }

    if (_bookableByMembers &&
        (!_teamSelectionEnabled || _selectionMode != 'preselect')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Member-bookable fixture types must use Pre-Select mode.'),
        ),
      );
      return;
    }

    if (!_usesRinks) {
      _teamSelectionEnabled = false;
      _selectionMode = null;
      _bookableByMembers = false;
      _section = 'open';
      _dressCode = 'open';
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final payload = <String, dynamic>{
        'club_id': widget.clubId,
        'name': _nameController.text.trim(),
        'is_internal': _isInternal,
        'uses_rinks': _usesRinks,
        'default_rinks_required': rinks,
        'default_players_per_rink': players,
        'default_duration_minutes': duration,
        'dress_code': _dressCode,
        'team_selection_enabled': _teamSelectionEnabled,
        'selection_mode': _teamSelectionEnabled ? _selectionMode : null,
        'bookable_by_members': _bookableByMembers,
        'section': _section,
        'colour_scheme_id': _selectedColourScheme?.id,
        'tags': _selectedTags.toList()..sort(),
      };

      if (_isEdit) {
        await _client
            .from('competition_types')
            .update(payload)
            .eq('id', widget.competitionTypeId!);
      } else {
        await _client.from('competition_types').insert(payload);
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewName = _nameController.text.trim().isEmpty
        ? 'Example Name'
        : _nameController.text.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Fixture Type' : 'Add New Fixture Type'),
      ),     
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                        Container(
                        decoration: BoxDecoration(
                            color: _selectedColourScheme == null
                                ? null
                                : colorFromHex(
                                    _selectedColourScheme!.backgroundHex,
                                    fallback: Colors.grey.shade200,
                                ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                            color: _selectedColourScheme == null
                                ? Colors.black26
                                : colorFromHex(
                                    _selectedColourScheme!.foregroundHex,
                                    fallback: Colors.black87,
                                    ).withOpacity(0.35),
                            ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: TextFormField(
                            controller: _nameController,
                            readOnly: widget.readOnly,
                            style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: _selectedColourScheme == null
                                ? null
                                : colorFromHex(
                                    _selectedColourScheme!.foregroundHex,
                                    fallback: Colors.black87,
                                    ),
                            ),
                            decoration: InputDecoration(
                            labelText: 'Fixture Type Name',
                            labelStyle: TextStyle(
                                color: _selectedColourScheme == null
                                    ? null
                                    : colorFromHex(
                                        _selectedColourScheme!.foregroundHex,
                                        fallback: Colors.black87,
                                    ).withOpacity(0.85),
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                            validator: (v) {
                            if ((v ?? '').trim().isEmpty) {
                                return 'Please enter a name';
                            }
                            return null;
                            },
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildTagsSection(),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Fixture behaviour',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              SwitchListTile(
                                value: _usesRinks,
                                onChanged: widget.readOnly
                                    ? null
                                    : (v) {
                                        setState(() {
                                          _usesRinks = v;

                                          if (!_usesRinks) {
                                            _teamSelectionEnabled = false;
                                            _selectionMode = null;
                                            _bookableByMembers = false;
                                            _section = 'open';
                                            _dressCode = 'open';

                                            _rinksController.clear();
                                            _playersController.clear();
                                          } else {
                                            _rinksController.text =
                                                _rinksController.text.trim().isEmpty ? '1' : _rinksController.text;

                                            _playersController.text =
                                                _playersController.text.trim().isEmpty ? '4' : _playersController.text;
                                          }
                                        });
                                      },
                                title: const Text('Uses green / rinks'),
                                subtitle: const Text(
                                  'Turn this off for meetings, lunches, AGMs and other events that do not reserve rink space.',
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              SwitchListTile(
                                value: _bookableByMembers,
                                onChanged: widget.readOnly || !_usesRinks
                                    ? null
                                    : (v) {
                                        setState(() {
                                          _bookableByMembers = v;
                                          if (v) {
                                            _teamSelectionEnabled = true;
                                            _selectionMode = 'preselect';
                                            _isInternal = true;
                                          }
                                        });
                                      },
                                title: const Text('Bookable by members'),
                                subtitle: const Text(
                                  'Allows members to use this fixture type themselves, usually for club competition bookings and other general member bookings.',
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              if (!_usesRinks)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                    'This will behave as an event/information fixture and will not require rinks.',
                                    style: TextStyle(fontStyle: FontStyle.italic),
                                  ),
                                ),
                              SwitchListTile(
                                value: _isInternal,
                                onChanged: widget.readOnly
                                    ? null
                                    : (v) => setState(() => _isInternal = v),
                                title: const Text('Internal fixture type'),
                                subtitle: const Text(
                                  'Use this for club-internal fixtures with no opponent.',
                                ),
                                contentPadding: EdgeInsets.zero,
                              ),
                              if (_usesRinks) ...[
                                const SizedBox(height: 8),
                                SwitchListTile(
                                  value: _teamSelectionEnabled,
                                  onChanged: widget.readOnly
                                      ? null
                                      : (v) {
                                          setState(() {
                                            _teamSelectionEnabled = v;
                                            if (!v) {
                                              _selectionMode = null;
                                            } else {
                                              _selectionMode ??= 'rsvp';
                                            }
                                          });
                                        },
                                  title: const Text('Team Selection'),
                                  contentPadding: EdgeInsets.zero,
                                ),

                                if (_teamSelectionEnabled) ...[
                                  const SizedBox(height: 8),
                                  DropdownButtonFormField<String>(
                                    value: _selectionMode,
                                    decoration: _dec('Selection mode'),
                                    items: const [
                                      DropdownMenuItem(value: 'team', child: Text('Team')),
                                      DropdownMenuItem(value: 'rsvp', child: Text('RSVP')),
                                      DropdownMenuItem(value: 'preselect', child: Text('Pre-Select')),
                                      DropdownMenuItem(value: 'open', child: Text('Open Session')),
                                    ],
                                    onChanged: widget.readOnly
                                        ? null
                                        : (v) => setState(() => _selectionMode = v),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _section,
                        decoration: _dec('Section'),
                        items: const [
                          DropdownMenuItem(value: 'mens',child: Text("Men's")),                          
                          DropdownMenuItem(value: 'ladies',child: Text('Ladies')),
                          DropdownMenuItem(value: 'mixed',child: Text('Mixed')),
                          DropdownMenuItem(value: 'open',child: Text("Open")),
                        ],
                        onChanged: widget.readOnly
                            ? null
                            : (v) => setState(() => _section = v ?? 'mens'),
                      ),
                      const SizedBox(height: 8),
                      if (_usesRinks) ...[                      
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _rinksController,
                                readOnly: widget.readOnly,
                                keyboardType: TextInputType.number,
                                decoration: _dec('Default rinks required'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _defaultFormat,
                                decoration: _dec('Format'),
                                items: const [
                                  DropdownMenuItem(value: 'singles', child: Text('Singles')),
                                  DropdownMenuItem(value: 'pairs', child: Text('Pairs')),
                                  DropdownMenuItem(value: 'triples', child: Text('Triples')),
                                  DropdownMenuItem(value: 'rinks', child: Text('Rinks')),
                                ],
                                onChanged: widget.readOnly
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _defaultFormat = value;

                                          // 🔑 enforce players per rink automatically
                                          _playersController.text = switch (value) {
                                            'singles' => '1',
                                            'pairs' => '2',
                                            'triples' => '3',
                                            'rinks' => '4',
                                            _ => '',
                                          };
                                        });
                                      },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _durationController,
                        readOnly: widget.readOnly,
                        keyboardType: TextInputType.number,
                        decoration: _dec('Default duration (mins)'),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _dressCode,
                        decoration: _dec('Dress code'),
                        items: const [
                          DropdownMenuItem(value: 'whites',child: Text('Whites')),
                          DropdownMenuItem(value: 'greys',child: Text('Greys')),
                          DropdownMenuItem(value: 'blacks',child: Text('Blacks')),
                          DropdownMenuItem(value: 'open', child: Text('Open')),
                        ],
                        onChanged: widget.readOnly
                            ? null
                            : (v) => setState(() => _dressCode = v ?? 'whites'),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _selectedColourScheme == null
                            ? 'Colour scheme'
                            : 'Colour scheme - ${_selectedColourScheme!.name}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          CompetitionTypeColourChip(
                            text: previewName,
                            backgroundHex: _selectedColourScheme?.backgroundHex,
                            foregroundHex: _selectedColourScheme?.foregroundHex,
                          ),
                          if (!widget.readOnly)
                            OutlinedButton.icon(
                              onPressed: _pickColours,
                              icon: const Icon(Icons.palette_outlined),
                              label: const Text('Choose colours'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      if (!widget.readOnly)
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: Text(_saving ? 'Saving...' : 'Save'),
                        ),
                    ],
                  ),
                ),
    );
  }
}