import 'package:flutter/material.dart';
export 'fixture_scorecard_availability.dart';
import 'scorecard.dart';
import 'scorecard_match_summary.dart';

/// An in-memory preview only: no repository, timer, setup RPC or save controls.
class FixtureScorecardPreview extends StatelessWidget {
  const FixtureScorecardPreview({super.key, required this.card});
  final Scorecard card;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scorecard Preview')),
    body: ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: const Color(0xffdce8f7),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xff9bb5d5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScorecardMatchSummary(card: card),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: FilledButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.event_outlined),
                  label: const Text(
                    'Scorecard available on the day of the Fixture',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Preview only — no scorecard has been saved. Reopen from the fixture on match day to use its latest details.',
          ),
        ),
      ],
    ),
  );
}
