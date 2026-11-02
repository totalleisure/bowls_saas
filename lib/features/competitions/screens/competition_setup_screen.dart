import 'package:flutter/material.dart';
import '../competition_repository.dart';

class CompetitionSetupScreen extends StatefulWidget {
  final String clubId;
  final CompetitionRepository repository;
  final CompetitionRow? initial;
  final bool structureLocked;
  const CompetitionSetupScreen({
    super.key,
    required this.clubId,
    required this.repository,
    this.initial,
    this.structureLocked = false,
  });
  @override
  State<CompetitionSetupScreen> createState() => _CompetitionSetupScreenState();
}

class _CompetitionSetupScreenState extends State<CompetitionSetupScreen> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{
    for (final key in [
      'name',
      'season',
      'players',
      'booking',
      'woods',
      'limit',
      'rules',
      'eligibility',
      'dress',
      'scoring',
      'rinks',
      'handicap',
    ])
      key: TextEditingController(),
  };
  String section = 'open', format = 'singles', timeMode = 'unknown';
  bool saving = false, loadingTypes = true;
  List<CompetitionRow> fixtureTypes = [];
  String? fixtureTypeId, typeError;
  String? error;
  @override
  void initState() {
    super.initState();
    fields['players']!.text = '1';
    fields['booking']!.text = '150';
    fields['rinks']!.text = '1';
    fields['season']!.text =
        '${DateTime.now().year}–${DateTime.now().year + 1}';
    fixtureTypeId = widget.initial?['fixture_type_id']?.toString();
    loadFixtureTypes();
    final initial = widget.initial;
    if (initial != null) {
      fields['name']!.text = '${initial['name']}';
      fields['season']!.text = '${initial['season']}';
      final settings = initial['settings'] as Map;
      section = settings['section'].toString();
      format = settings['playing_format'].toString();
      timeMode = settings['time_limit_mode'].toString();
      for (final pair in {
        'players': 'players_per_entry',
        'rinks': 'rinks_required',
        'booking': 'booking_minutes',
        'woods': 'woods_per_player',
        'limit': 'time_limit_minutes',
        'rules': 'rules',
        'eligibility': 'eligibility',
        'dress': 'dress',
        'scoring': 'scoring',
        'handicap': 'handicap',
      }.entries) {
        fields[pair.key]!.text = settings[pair.value]?.toString() ?? '';
      }
    }
  }

  Future<void> loadFixtureTypes() async {
    try {
      final rows = await widget.repository.fixtureTypes(widget.clubId);
      if (mounted)
        setState(() {
          fixtureTypes = rows;
          loadingTypes = false;
          typeError = null;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          loadingTypes = false;
          typeError = 'Unable to load Fixture Types. Please retry.';
        });
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget input(
    String key,
    String label, {
    bool required = false,
    int? maxNumber,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: fields[key],
      enabled: !(widget.structureLocked && key == 'players'),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      maxLines: lines,
      keyboardType: maxNumber != null
          ? TextInputType.number
          : TextInputType.text,
      validator: (v) {
        if (required && (v == null || v.trim().isEmpty)) return 'Required';
        if (maxNumber != null &&
            v!.isNotEmpty &&
            (int.tryParse(v) == null ||
                int.parse(v) < 1 ||
                int.parse(v) > maxNumber)) {
          return 'Enter 1–$maxNumber';
        }
        return null;
      },
    ),
  );
  Widget choice(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> change,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final s in options)
          DropdownMenuItem(
            value: s,
            child: Text(
              s == 'none'
                  ? 'No playing time limit'
                  : s == 'unknown'
                  ? 'Not yet confirmed'
                  : s,
            ),
          ),
      ],
      onChanged: widget.structureLocked && label == 'Playing format'
          ? null
          : (v) => setState(() => change(v!)),
    ),
  );
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final settings = <String, dynamic>{
        ...?widget.initial?['settings'] as Map<String, dynamic>?,
        'section': section,
        'playing_format': format,
        'players_per_entry': int.parse(fields['players']!.text),
        'rinks_required': int.parse(fields['rinks']!.text),
        'booking_minutes': int.parse(fields['booking']!.text),
        'time_limit_mode': timeMode,
        'time_limit_minutes': timeMode == 'minutes'
            ? int.parse(fields['limit']!.text)
            : null,
        'woods_per_player': int.tryParse(fields['woods']!.text),
        for (final k in [
          'rules',
          'eligibility',
          'dress',
          'scoring',
          'handicap',
        ])
          k: fields[k]!.text.trim(),
      };
      String id;
      if (widget.initial != null) {
        id = widget.initial!['id'].toString();
        await widget.repository.update(
          id,
          fields['name']!.text.trim(),
          fields['season']!.text.trim(),
          settings,
          fixtureTypeId: fixtureTypeId,
        );
      } else {
        id = await widget.repository.create(
          widget.clubId,
          fields['name']!.text.trim(),
          fields['season']!.text.trim(),
          settings,
          fixtureTypeId: fixtureTypeId,
        );
      }
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.initial == null ? 'New competition' : 'Edit competition',
      ),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Edit the competition rules and playing conditions here. Existing round overrides remain in effect.',
              ),
              if (widget.structureLocked)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Playing format and team size are fixed because entries or a draw exist. Other settings can be edited without rebuilding the draw.',
                  ),
                ),
              const SizedBox(height: 20),
              if (loadingTypes) const LinearProgressIndicator(),
              if (typeError != null) ...[
                Text(typeError!),
                TextButton(
                  onPressed: loadFixtureTypes,
                  child: const Text('Retry Fixture Types'),
                ),
              ],
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    'fixture-type-${fixtureTypes.length}-$fixtureTypeId',
                  ),
                  initialValue:
                      fixtureTypes.any((t) => t['id'] == fixtureTypeId)
                      ? fixtureTypeId
                      : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Fixture Type',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final type in fixtureTypes)
                      DropdownMenuItem(
                        value: type['id'].toString(),
                        child: Text('${type['name']}'),
                      ),
                  ],
                  onChanged: saving || loadingTypes
                      ? null
                      : (value) => setState(() => fixtureTypeId = value),
                  validator: (value) =>
                      value == null ? 'Select a Fixture Type' : null,
                ),
              ),
              input('name', 'Competition name', required: true),
              input('season', 'Season', required: true),
              choice('Section', section, [
                'open',
                'mens',
                'ladies',
                'mixed',
              ], (v) => section = v),
              choice(
                'Playing format',
                format,
                ['singles', 'pairs', 'triples', 'fours', 'aussie_pairs'],
                (v) {
                  format = v;
                  fields['players']!.text = switch (v) {
                    'singles' => '1',
                    'pairs' || 'aussie_pairs' => '2',
                    'triples' => '3',
                    _ => '4',
                  };
                },
              ),
              input(
                'players',
                'Players per entry / team',
                required: true,
                maxNumber: 12,
              ),
              input('rinks', 'Rinks per match', required: true, maxNumber: 20),
              input(
                'woods',
                'Woods per player (leave blank if unconfirmed)',
                maxNumber: 4,
              ),
              input(
                'scoring',
                'Winning condition / scoring (e.g. first to 21)',
                required: true,
              ),
              choice('Playing time limit', timeMode, [
                'unknown',
                'none',
                'minutes',
              ], (v) => timeMode = v),
              if (timeMode == 'minutes')
                input(
                  'limit',
                  'Playing time limit in minutes',
                  required: true,
                  maxNumber: 1440,
                ),
              input(
                'booking',
                'Rink-booking duration in minutes',
                required: true,
                maxNumber: 1440,
              ),
              input('dress', 'Dress code'),
              input(
                'eligibility',
                'Eligibility and partner arrangements',
                lines: 2,
              ),
              input('handicap', 'Handicap rules (if applicable)', lines: 2),
              input('rules', 'Competition rules and notes', lines: 5),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: saving || loadingTypes || typeError != null
                    ? null
                    : save,
                child: Text(
                  saving
                      ? 'Saving…'
                      : widget.initial == null
                      ? 'Create draft competition'
                      : 'Save competition',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
