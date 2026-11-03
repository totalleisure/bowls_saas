import 'package:flutter/material.dart';
import '../features/auth/auth_gate.dart';
import '../features/releases/feature_revision_scope.dart';
import '../features/scorecards/scorecard_recovery_host.dart';

class BowlsApp extends StatelessWidget {
  const BowlsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScorecardRecoveryHost(
      child: FeatureRevisionHost(child: AuthGate()),
    );
  }
}
