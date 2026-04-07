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
  String _section = 'mens';
  String _dressCode = 'whites';
  bool _teamSelectionEnabled = false;
  String? _selectionMode;
  ColourScheme? _selectedColourScheme;

  bool get _isEdit => widget.competitionTypeId != null;

  @override
  void initState() {
    super.initState();
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
            .eq('id', widget.competitionTypeId!)
            .single();

        final row = CompetitionType.fromMap(Map<String, dynamic>.from(res));

        _nameController.text = row.name;
        _rinksController.text = row.defaultRinksRequired?.toString() ?? '';
        _playersController.text = row.defaultPlayersPerRink?.toString() ?? '';
        _durationController.text = row.defaultDurationMinutes?.toString() ?? '';
        _isInternal = row.isInternal;
        _section = row.section;
        _dressCode = row.dressCode ?? 'whites';
        _teamSelectionEnabled = row.teamSelectionEnabled;
        _selectionMode = row.selectionMode;
        _selectedColourScheme = row.colourScheme;
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

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final payload = <String, dynamic>{
        'club_id': widget.clubId,
        'name': _nameController.text.trim(),
        'is_internal': _isInternal,
        'section': _section,
        'default_rinks_required': rinks,
        'default_players_per_rink': players,
        'default_duration_minutes': duration,
        'dress_code': _dressCode,
        'team_selection_enabled': _teamSelectionEnabled,
        'selection_mode': _teamSelectionEnabled ? _selectionMode : null,
        'colour_scheme_id': _selectedColourScheme?.id,
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
//        subtitle: text('(Matches, Competitions and Leagues)'),
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
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _section,
                        decoration: _dec('Section'),
                        items: const [
                          DropdownMenuItem(
                            value: 'mens',
                            child: Text("Men's"),
                          ),
                          DropdownMenuItem(
                            value: 'ladies',
                            child: Text('Ladies'),
                          ),
                          DropdownMenuItem(
                            value: 'mixed',
                            child: Text('Mixed'),
                          ),
                        ],
                        onChanged: widget.readOnly
                            ? null
                            : (v) => setState(() => _section = v ?? 'mens'),
                      ),
                      const SizedBox(height: 16),
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
                            child: TextFormField(
                              controller: _playersController,
                              readOnly: widget.readOnly,
                              keyboardType: TextInputType.number,
                              decoration: _dec('Default players per rink'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
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
                          DropdownMenuItem(
                            value: 'whites',
                            child: Text('Whites'),
                          ),
                          DropdownMenuItem(
                            value: 'greys',
                            child: Text('Greys'),
                          ),
                          DropdownMenuItem(
                            value: 'blacks',
                            child: Text('Blacks'),
                          ),
                        ],
                        onChanged: widget.readOnly
                            ? null
                            : (v) => setState(() => _dressCode = v ?? 'whites'),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        value: _teamSelectionEnabled,
                        onChanged: widget.readOnly
                            ? null
                            : (v) {
                                setState(() {
                                  _teamSelectionEnabled = v;
                                  if (!v) _selectionMode = null;
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
                            DropdownMenuItem(
                              value: 'team',
                              child: Text('Team'),
                            ),
                            DropdownMenuItem(
                              value: 'rsvp',
                              child: Text('RSVP'),
                            ),
                            DropdownMenuItem(
                              value: 'practice',
                              child: Text('Practice'),
                            ),
                            DropdownMenuItem(
                              value: 'preselect',
                              child: Text('Pre-Select'),
                            ),
                          ],
                          onChanged: widget.readOnly
                              ? null
                              : (v) => setState(() => _selectionMode = v),
                        ),
                      ],
                      const SizedBox(height: 24),
                      const Text(
                        'Colour scheme',
                        style: TextStyle(fontWeight: FontWeight.w600),
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
                      if (_selectedColourScheme != null) ...[
                        const SizedBox(height: 8),
                        Text('Selected: ${_selectedColourScheme!.name}'),
                      ],
                      const SizedBox(height: 24),
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
                      const SizedBox(height: 24),
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