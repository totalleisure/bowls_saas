import 'package:flutter/material.dart';
import '../features/auth/auth_gate.dart';

class BowlsApp extends StatelessWidget {
  const BowlsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Bowls SaaS',
      theme: ThemeData(useMaterial3: true),
      home: AuthGate(),
    );
  }
}
