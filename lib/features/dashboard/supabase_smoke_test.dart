import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

class SupabaseSmokeTest extends StatelessWidget {
  const SupabaseSmokeTest({super.key});

  @override
  Widget build(BuildContext context) {
    final client = Supabase.instance.client;

    return Scaffold(
      appBar: AppBar(title: const Text('Bowls SaaS')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            try {
              final session = client.auth.currentSession;
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Supabase connection OK ✅')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Supabase error: $e')),
                );
              }
            }
          },
          child: const Text('Test Supabase connection'),
        ),
      ),
    );
  }
}


