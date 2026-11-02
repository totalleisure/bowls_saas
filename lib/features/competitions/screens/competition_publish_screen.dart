import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CompetitionPublishScreen extends StatefulWidget {
  final String clubId, competitionId;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? request;
  const CompetitionPublishScreen({
    super.key,
    required this.clubId,
    required this.competitionId,
    this.request,
  });
  @override
  State<CompetitionPublishScreen> createState() =>
      _CompetitionPublishScreenState();
}

class _CompetitionPublishScreenState extends State<CompetitionPublishScreen> {
  Map<String, dynamic>? status;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<Map<String, dynamic>> request(String action) async {
    final body = {
      'action': action,
      'clubId': widget.clubId,
      'competitionId': widget.competitionId,
    };
    if (widget.request != null) return widget.request!(body);
    final response = await Supabase.instance.client.functions.invoke(
      'competition-publication',
      body: body,
    );
    final value = Map<String, dynamic>.from(response.data as Map);
    if (value['error'] != null) throw Exception(value['error']);
    return value;
  }

  Future<void> refresh() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await request('publication_status');
      if (mounted) setState(() => status = value);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> publish() async {
    final current = status;
    if (current == null) return;
    final eligible = (current['pending'] as num?)?.toInt() ?? 0;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          current['published'] == true
              ? 'Send publication emails?'
              : 'Publish this competition?',
        ),
        content: Text(
          '${current['competitionName']}\n\n${eligible == 0 ? 'No player email addresses are eligible. The competition will be published without sending emails.' : 'Send competition-specific publication emails to $eligible eligible player address(es). Recipients excluded by the current environment policy will not receive mail.'}\n\nPreviously attempted deliveries will not be resent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              current['published'] == true ? 'Send emails' : 'Publish and send',
            ),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final value = await request('publish');
      if (mounted) setState(() => status = value);
    } catch (e) {
      if (mounted)
        setState(
          () => error =
              'The request did not complete: $e. Check publication and delivery status before retrying.',
        );
      try {
        final value = await request('publication_status');
        if (mounted) setState(() => status = value);
      } catch (_) {}
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = status;
    final published = data?['published'] == true;
    final prepared = data?['event_id'] != null;
    final staging = data?['stagingOnly'] != false;
    final pending = (data?['pending'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Publish competition'),
        actions: [
          IconButton(
            tooltip: 'Refresh delivery status',
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                staging
                    ? 'STAGING: publication emails are limited to approved test addresses belonging to players entered in this competition. All other recipients are skipped.'
                    : 'PRODUCTION: publishing sends real emails to eligible players entered in this competition. Check the draw and recipient totals before confirming.',
              ),
            ),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            SelectableText(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (data != null) ...[
            Text(
              '${data['competitionName']}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            ListTile(
              title: const Text('Competition status'),
              subtitle: Text(
                published ? 'Published' : 'Draft — organisers only',
              ),
              leading: Icon(
                published ? Icons.check_circle : Icons.edit_outlined,
              ),
            ),
            ListTile(
              title: const Text('Players entered'),
              trailing: Text('${data['total_players']}'),
            ),
            ListTile(
              title: Text(
                staging
                    ? 'Eligible test addresses'
                    : 'Eligible player email addresses',
              ),
              trailing: Text('${data['eligible_count']}'),
            ),
            ListTile(
              title: const Text(
                'Skipped: other addresses / inactive / duplicates',
              ),
              trailing: Text('${data['restricted_count']}'),
            ),
            ListTile(
              title: const Text('Skipped: no email address'),
              trailing: Text('${data['missing_email_count']}'),
            ),
            const Divider(),
            Text(
              'Publication email delivery',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Sent: ${data['sent']} · Pending: ${data['pending']} · Unconfirmed: ${(data['claimed'] as num? ?? 0) + (data['uncertain'] as num? ?? 0)}',
            ),
            if (prepared && (data['eligible_count'] as num? ?? 0) == 0)
              const Text(
                '0 emails sent: no entrants have an eligible approved test address.',
              ),
            if ((data['claimed'] as num? ?? 0) +
                    (data['uncertain'] as num? ?? 0) >
                0)
              const Text(
                'Some deliveries could not be confirmed. Check the test mailboxes. These deliveries will not be retried automatically.',
              ),
            for (final row in data['recipients'] as List? ?? [])
              ListTile(
                title: Text('${row['recipient']}'),
                trailing: Text('${row['status']}'),
              ),
            const SizedBox(height: 16),
            if (!prepared || pending > 0)
              FilledButton.icon(
                onPressed: busy ? null : publish,
                icon: const Icon(Icons.publish),
                label: Text(
                  !published
                      ? 'Publish competition and send emails'
                      : prepared
                      ? 'Send pending publication emails'
                      : 'Send publication emails',
                ),
              ),
            if (prepared &&
                pending == 0 &&
                (data['claimed'] as num? ?? 0) +
                        (data['uncertain'] as num? ?? 0) ==
                    0)
              const Text(
                'Publication processing complete. Previously sent publication emails will not be sent again.',
              ),
          ],
        ],
      ),
    );
  }
}
