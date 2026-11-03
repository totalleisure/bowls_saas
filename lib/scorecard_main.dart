// Standalone, fully offline entrypoint for the Electronic Scorecard add-on.
// It deliberately does not initialise Supabase or perform any network calls.
import 'package:flutter/material.dart';
import 'features/scorecards/scorecard_screen.dart';
import 'features/scorecards/scorecard_recovery_host.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ScorecardRecoveryHost(
      child: MaterialApp(
        title: 'Total Leisure Electronic Scorecards',
        theme: ThemeData(
          colorSchemeSeed: const Color(0xff0057b8),
          useMaterial3: true,
        ),
        home: const ScorecardsScreen(),
      ),
    ),
  );
}
