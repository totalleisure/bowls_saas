
import '../config/venues_screen.dart';
import '../config/match_formats_screen.dart';
import '../members/members_screen.dart';
import '../fixtures/fixtures_screen.dart';
import '../team/teams_screen.dart';
import '../config/green_areas_screen.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/utils/date_format.dart';
import '../competitions/screens/competition_type_list_screen.dart';

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
              leading: const Icon(Icons.location_on_outlined),
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
              leading: const Icon(Icons.grass_outlined),
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
              leading: const Icon(Icons.emoji_events_outlined),
              title: const Text('Fixture Types'),
              subtitle: const Text('(Matches, Competitions and Leagues)'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CompetitionTypeListScreen(
                      clubId: clubId,
                      readOnly: false,
                    ),
                  ),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event),
              title: const Text('Fixtures'),
              subtitle: const Text('Schedule fixtures + allocate greens'),
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
              leading: const Icon(Icons.people_outline),
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
              leading: const Icon(Icons.groups_2_outlined),
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
