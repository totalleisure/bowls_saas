import 'package:flutter/material.dart';
import '../features/auth/auth_gate.dart';
import '../features/releases/feature_revision_scope.dart';

class BowlsApp extends StatelessWidget {
  const BowlsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FeatureRevisionHost(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Bowls SaaS',
        theme: ThemeData(useMaterial3: true),
        home: const AuthGate(),
      ),
    );
  }
}
