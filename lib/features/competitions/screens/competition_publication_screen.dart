import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/club_member_picker_page.dart';

class CompetitionPublicationScreen extends StatefulWidget {
  final String clubId;
  final String? competitionId;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>)? request;
  const CompetitionPublicationScreen({
    super.key,
    required this.clubId,
    this.competitionId,
    this.request,
  });
  @override
  State<CompetitionPublicationScreen> createState() =>
      _CompetitionPublicationScreenState();
}

class _CompetitionPublicationScreenState
    extends State<CompetitionPublicationScreen> {
  Map<String, dynamic>? preview;
  String? error, recipient, memberId, status;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<Map<String, dynamic>> request(Map<String, dynamic> body) async {
    body = {
      ...body,
      if (widget.competitionId != null) 'competitionId': widget.competitionId,
    };
    if (widget.request != null) {
      return widget.request!({...body, 'clubId': widget.clubId});
    }
    final response = await Supabase.instance.client.functions.invoke(
      'competition-publication',
      body: {...body, 'clubId': widget.clubId},
    );
    final result = Map<String, dynamic>.from(response.data as Map);
    if (result['error'] != null) throw Exception(result['error']);
    return result;
  }

  Future<void> load([String? id]) async {
    setState(() {
      busy = true;
      preview = null;
      error = null;
      status = null;
      memberId = id;
    });
    try {
      final data = await request({'action': 'preview', 'memberId': ?id});
      if (mounted) {
        setState(() {
          preview = data;
          recipient = (data['testRecipients'] as List).first.toString();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> choosePlayer() async {
    final ids = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(
        builder: (_) => ClubMemberPickerPage(
          clubId: widget.clubId,
          title: 'Preview competition email for player',
        ),
      ),
    );
    if (ids != null && ids.isNotEmpty && mounted) await load(ids.first);
  }

  Future<void> sendTest() async {
    final data = preview;
    if (data == null || recipient == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send staging test email?'),
        content: Text(
          'Send this player’s preview only to $recipient. No emails or notifications will be sent to the competition players.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send test'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await request({
        'action': 'send_test',
        'previewId': data['id'],
        'recipients': [recipient],
      });
      if (mounted) {
        setState(
          () => status = (result['outcomes'] as List)
              .map(
                (x) =>
                    "${x['recipient']}: ${{'sent': 'Test email sent', 'already_attempted': 'Already attempted for this preview; no duplicate sent', 'uncertain_do_not_retry': 'Delivery not confirmed. Check the mailbox before preparing another preview.'}[x['status']] ?? x['status']}",
              )
              .join('\n'),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveHtml() async {
    final data = preview;
    if (data == null) return;
    await FilePicker.platform.saveFile(
      dialogTitle: 'Save exact HTML email preview',
      fileName: 'Competition-email-preview.html',
      type: FileType.custom,
      allowedExtensions: ['html'],
      bytes: utf8.encode(data['html'].toString()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = preview?['content'] as Map?;
    final entries = content?['entries'] as List? ?? [];
    final contacts = content?['contacts'] as List? ?? [];
    final teamContacts = content?['teamContacts'] as List? ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Player email preview')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'PREVIEW ONLY. To publish or send publication emails, return to the Draw tab and choose Publish competition or Publication emails / status. Test copies are limited to approved addresses.',
              ),
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: busy ? null : () => load(),
                child: const Text('Preview my entries'),
              ),
              OutlinedButton(
                onPressed: busy ? null : choosePlayer,
                child: const Text('Choose player'),
              ),
            ],
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (content != null) ...[
            Text(
              'Email for ${content['recipientName']}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text('${preview!['subject']}'),
            const SizedBox(height: 12),
            Text('Hello ${content['recipientName']},'),
            const Text(
              'Your competition entries and match details are below. Open Competitions from the Options menu in the App for the latest draw and results.',
            ),
            for (final entry in entries)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blueGrey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry['competitionName']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text('${entry['stageName']}'),
                    Text(
                      "Play by: ${entry['playByLabel'] ?? entry['playBy'] ?? 'Not yet set'}",
                    ),
                    const Divider(),
                    Text('Your entry: ${entry['entryName']}'),
                    Text(
                      'Opponent: ${entry['opponentName'] ?? 'To be confirmed after the preliminary round'}',
                    ),
                    const Divider(),
                    const Text(
                      'Competition rules',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text('${entry['rules']}'),
                  ],
                ),
              ),
            if (teamContacts.isNotEmpty) ...[
              Text(
                'Your team contact details',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final person in teamContacts)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${person['name']}'),
                  subtitle: SelectableText(
                    [
                      if (person['email'] != null) 'Email: ${person['email']}',
                      if (person['mobile'] != null)
                        'Mobile: ${person['mobile']}',
                      if (person['email'] == null && person['mobile'] == null)
                        'No email or mobile number available.',
                    ].join('\n'),
                  ),
                ),
            ],
            Text(
              'Opponent contact details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (contacts.isEmpty)
              const Text('No opponent contacts are available yet.'),
            for (final person in contacts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${person['name']}'),
                subtitle: SelectableText(
                  [
                    if (person['email'] != null) 'Email: ${person['email']}',
                    if (person['mobile'] != null) 'Mobile: ${person['mobile']}',
                    if (person['email'] == null && person['mobile'] == null)
                      'Please contact the Competitions Manager for help arranging the match.',
                  ].join('\n'),
                ),
              ),
            const Divider(),
            const Text('Total Leisure Bowls — Your Club. Your Way.'),
            TextButton(
              onPressed: busy ? null : saveHtml,
              child: const Text('Save exact HTML email preview'),
            ),
            DropdownButtonFormField<String>(
              initialValue: recipient,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Test delivery address',
              ),
              items: [
                for (final address in preview!['testRecipients'] as List)
                  DropdownMenuItem(
                    value: address.toString(),
                    child: Text(address.toString()),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(() => recipient = value),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : sendTest,
              child: const Text('Send test copy'),
            ),
          ],
          if (status != null) SelectableText(status!),
        ],
      ),
    );
  }
}
