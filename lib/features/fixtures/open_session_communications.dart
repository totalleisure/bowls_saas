import 'package:flutter/material.dart';

/// Open sessions reserve playing space; they do not publish a selected squad.
bool isOpenSessionFixture(Map<String, dynamic>? fixture) {
  final type = fixture?['competition_type'];
  if (type is! Map || type['uses_rinks'] == false) return false;
  return type['selection_mode']?.toString().trim().toLowerCase() == 'open';
}

String fixtureCommunicationStatus(
  Map<String, dynamic>? fixture,
  String selectionStatus,
) => isOpenSessionFixture(fixture) ? 'Open' : selectionStatus;

class OpenSessionCommunicationsCard extends StatelessWidget {
  const OpenSessionCommunicationsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Open session',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'Players turn up to join this session. No team selection or publication is required.',
            ),
            SizedBox(height: 8),
            Text('Team-selection messages and team sheets do not apply.'),
          ],
        ),
      ),
    );
  }
}
