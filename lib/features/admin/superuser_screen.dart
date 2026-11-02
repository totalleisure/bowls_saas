import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'feature_revision_screen.dart';
import 'queue_admin_screen.dart';
import '../communications/communications_control_centre.dart';
import 'audit_journal_screen.dart';
import '../reports/club_reports_screen.dart';
import '../communications/mailing_lists_screen.dart';

class SuperuserScreen extends StatefulWidget {
  final String clubId;
  const SuperuserScreen({super.key, required this.clubId});
  @override
  State<SuperuserScreen> createState() => _SuperuserScreenState();
}

class _SuperuserScreenState extends State<SuperuserScreen> {
  late final Future<String> _clubName = Supabase.instance.client
      .from('clubs')
      .select('name')
      .eq('id', widget.clubId)
      .single()
      .then((r) => r['name'].toString());
  late final Future<bool> _allowed = Supabase.instance.client
      .rpc('is_app_superuser')
      .then((value) => value == true);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Superuser')),
    body: FutureBuilder<bool>(
      future: _allowed,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data != true) {
          return const Center(child: Text('Superuser access required.'));
        }
        Widget entry(String title, IconData icon, Widget Function() screen) =>
            Card(
              child: ListTile(
                leading: Icon(icon),
                title: Text(title),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => screen())),
              ),
            );
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            entry(
              'Messages from Total Leisure',
              Icons.outgoing_mail,
              () => FutureBuilder<String>(
                future: _clubName,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Scaffold(
                      body: Center(
                        child: Text(
                          'The selected Club could not be loaded. Please return and try again.',
                        ),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return MailingListsScreen(
                    clubId: widget.clubId,
                    clubName: snapshot.data!,
                    totalLeisureByDefault: true,
                  );
                },
              ),
            ),
            entry(
              'Club reports and App usage',
              Icons.assessment_outlined,
              () => ClubReportsScreen(clubId: widget.clubId),
            ),
            entry(
              'Audit journal',
              Icons.history,
              () => AuditJournalScreen(clubId: widget.clubId),
            ),
            entry(
              'Feature releases',
              Icons.toggle_on_outlined,
              () => const FeatureRevisionScreen(),
            ),
            entry(
              'Queue Administration',
              Icons.settings_outlined,
              () => const QueueAdminScreen(),
            ),
            entry(
              'Communications Control Centre',
              Icons.support_agent,
              () => CommunicationsControlCentreScreen(clubId: widget.clubId),
            ),
          ],
        );
      },
    ),
  );
}
