
import '../config/venues_screen.dart';
import '../config/match_formats_screen.dart';
import '../members/members_screen_with_Import.dart';
import '../fixtures/fixtures_screen.dart';
import '../team/teams_screen.dart';
import '../config/green_areas_screen.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

class ClubHomeScreen extends StatelessWidget {
  final String clubId;
  final String clubName;

  const ClubHomeScreen({
    super.key,
    required this.clubId,
    required this.clubName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(clubName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Club ID: $clubId'),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              title: const Text('Venues'),
              subtitle: const Text('Opponents, addresses, directions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VenuesScreen(clubId: clubId, clubName: clubName),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Greens / Rinks'),
              subtitle: const Text('Indoor/outdoor, rink naming, orientation'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GreenAreasScreen(clubId: clubId, clubName: clubName),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Match formats'),
              subtitle: const Text('Pairs, triples, rinks + positions'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MatchFormatsScreen(clubId: clubId, clubName: clubName),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Fixtures'),
              subtitle: const Text('Schedule matches + allocate greens'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FixturesScreen(
                      clubId: clubId,
                      clubName: clubName,
                    ),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Members'),
              subtitle: const Text('Roster + roles (admin/captain/selector/member)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MembersScreen(clubId: clubId),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Teams'),
              subtitle: const Text('Team pools + captains/vice/manager'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TeamsScreen(
                      clubId: clubId,
                      clubName: clubName,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
