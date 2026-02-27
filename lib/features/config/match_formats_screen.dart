import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

class MatchFormatsScreen extends StatelessWidget {
  final String clubId;
  final String clubName;

  const MatchFormatsScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Match formats')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('Match formats for $clubName (to build next).'),
      ),
    );
  }
}


