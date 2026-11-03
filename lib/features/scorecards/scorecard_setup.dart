import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'scorecard.dart';

class ScorecardSetup extends StatefulWidget {
  const ScorecardSetup({super.key, required this.card});
  final Scorecard card;
  @override
  State<ScorecardSetup> createState() => _ScorecardSetupState();
}

class _ScorecardSetupState extends State<ScorecardSetup> {
  final form = GlobalKey<FormState>();
  late final Scorecard card;
  final fields = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    card = Scorecard.fromJson(widget.card.toJson());
    final j = card.toJson();
    for (final key in [
      'title',
      'date',
      'venue',
      'rink',
      'sideA',
      'sideB',
      'playersA',
      'playersB',
      'marker',
      'notes',
      'woods',
      'target',
      'maxEnds',
      'durationMinutes',
      'lastJackMinutes',
      'handicapA',
      'handicapB',
    ]) {
      fields[key] = TextEditingController(text: j[key]?.toString() ?? '');
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget field(
    String key,
    String label, {
    bool required = false,
    bool number = false,
    bool signed = false,
    bool rules = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      controller: fields[key],
      enabled: !(rules && card.startedAt != null),
      maxLines: lines,
      keyboardType: number
          ? TextInputType.numberWithOptions(signed: signed)
          : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (v) {
        final s = v?.trim() ?? '';
        if (s.isEmpty) return required ? 'Please enter $label' : null;
        if (number) {
          final n = int.tryParse(s);
          if (n == null || (!signed && n <= 0)) {
            return 'Enter ${signed ? "a whole number" : "a positive whole number"}';
          }
        }
        if (key == 'date') {
          try {
            DateFormat('yyyy-MM-dd').parseStrict(s);
          } catch (_) {
            return 'Use YYYY-MM-DD';
          }
        }
        return null;
      },
    ),
  );
  void save() {
    if (!form.currentState!.validate()) return;
    final j = card.toJson();
    for (final e in fields.entries) {
      j[e.key] =
          [
            'woods',
            'target',
            'maxEnds',
            'durationMinutes',
            'lastJackMinutes',
            'handicapA',
            'handicapB',
          ].contains(e.key)
          ? int.tryParse(e.value.text.trim())
          : e.value.text.trim();
    }
    j['format'] = card.format;
    j['scoring'] = card.scoring;
    final next = Scorecard.fromJson(j);
    if (next.lastJackMinutes != null &&
        next.durationMinutes != null &&
        next.lastJackMinutes! > next.durationMinutes!) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'The last-jack deadline must not exceed the match duration.',
          ),
        ),
      );
      return;
    }
    next.changed('Match details saved');
    Navigator.pop(context, next);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        card.title.isEmpty ? 'New offline scorecard' : 'Match details',
      ),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Saved on this device. No sign-in or connection is required. Player names are entered manually; this does not book a rink or submit a competition result.',
          ),
          const SizedBox(height: 18),
          field('title', 'Match / competition name', required: true),
          field('date', 'Date (YYYY-MM-DD)', required: true),
          field('venue', 'Venue / club'),
          field('rink', 'Rink number'),
          DropdownButtonFormField<String>(
            initialValue: card.format,
            decoration: const InputDecoration(labelText: 'Format'),
            items: [
              'Singles',
              'Pairs',
              'Triples',
              'Fours',
            ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: card.startedAt != null
                ? null
                : (v) => setState(() => card.format = v!),
          ),
          const SizedBox(height: 16),
          field('sideA', 'Side A name', required: true),
          field('playersA', 'Side A players (positions / names)', lines: 3),
          field('sideB', 'Side B name', required: true),
          field('playersB', 'Side B players (positions / names)', lines: 3),
          field('marker', 'Marker / scorer'),
          DropdownButtonFormField<String>(
            initialValue: card.scoring,
            decoration: const InputDecoration(labelText: 'Scoring method'),
            items: const [
              DropdownMenuItem(value: 'shots', child: Text('Normal shots')),
              DropdownMenuItem(
                value: '100up',
                child: Text('100 Up — 4, 3, 2, 1'),
              ),
            ],
            onChanged: card.startedAt != null
                ? null
                : (v) => setState(() {
                    card.scoring = v!;
                    if (v == '100up' && fields['target']!.text.isEmpty) {
                      fields['target']!.text = '100';
                    }
                  }),
          ),
          const SizedBox(height: 16),
          field(
            'woods',
            'Woods per player',
            required: true,
            number: true,
            rules: true,
          ),
          field('target', 'Target score (optional)', number: true, rules: true),
          field(
            'maxEnds',
            'Maximum ends (optional)',
            number: true,
            rules: true,
          ),
          field(
            'handicapA',
            'Starting handicap A',
            required: true,
            number: true,
            signed: true,
            rules: true,
          ),
          field(
            'handicapB',
            'Starting handicap B',
            required: true,
            number: true,
            signed: true,
            rules: true,
          ),
          field(
            'durationMinutes',
            'Match duration in minutes (optional)',
            number: true,
            rules: true,
          ),
          field(
            'lastJackMinutes',
            'Last jack delivered by — minutes from start (optional)',
            number: true,
            rules: true,
          ),
          const Text(
            'The last-jack deadline prevents a new end. An end started before the deadline may be completed and scored afterwards. Warnings are shown at 10 and 5 minutes remaining. Keep the scorecard open for visual / sound alerts; background alarms are not included in this revision.',
          ),
          const SizedBox(height: 16),
          if (card.startedAt != null)
            const Text(
              'Playing format, scoring and timer conditions are fixed once the match starts.',
            ),
          field('notes', 'Playing conditions / notes', lines: 3),
          FilledButton(onPressed: save, child: const Text('Save scorecard')),
        ],
      ),
    ),
  );
}
