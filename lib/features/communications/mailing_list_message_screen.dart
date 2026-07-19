import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MailingListMessageScreen extends StatefulWidget {
  final String clubId;
  final String mailingListId;
  final String mailingListName;

  const MailingListMessageScreen({
    super.key,
    required this.clubId,
    required this.mailingListId,
    required this.mailingListName,
  });

  @override
  State<MailingListMessageScreen> createState() =>
      _MailingListMessageScreenState();
}

class _MailingListMessageScreenState extends State<MailingListMessageScreen> {
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  bool _listIsActive = false;
  bool _sendApp = true;
  bool _sendEmail = true;

  int _activeMemberCount = 0;
  int _emailRecipientCount = 0;

  String? _error;

  int get _membersWithoutEmail {
    final missing = _activeMemberCount - _emailRecipientCount;
    return missing < 0 ? 0 : missing;
  }

  String get _emailSummary {
    if (_membersWithoutEmail == 0) {
      return '$_emailRecipientCount email(s)';
    }

    return '$_emailRecipientCount email(s) — '
        '$_membersWithoutEmail without email';
  }

  @override
  void initState() {
    super.initState();
    _loadRecipientSummary();
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadRecipientSummary() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final supabase = Supabase.instance.client;

      final listRow = await supabase
          .from('mailing_lists')
          .select('id, club_id, name, is_active')
          .eq('id', widget.mailingListId)
          .eq('club_id', widget.clubId)
          .single();

      final memberRows = await supabase
          .from('mailing_list_members')
          .select('''
            member_profile_id,
            member_profile:member_profiles!mailing_list_members_member_profile_id_fkey(
              email_address
            )
          ''')
          .eq('mailing_list_id', widget.mailingListId)
          .eq('is_active', true);

      final rows = List<Map<String, dynamic>>.from(memberRows as List);

      final memberIds = rows
          .map((row) => row['member_profile_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final activeClubMemberIds = <String>{};

      if (memberIds.isNotEmpty) {
        final membershipRows = await supabase
            .from('club_memberships')
            .select('member_profile_id')
            .eq('club_id', widget.clubId)
            .eq('is_active', true)
            .inFilter('member_profile_id', memberIds);

        for (final raw in membershipRows as List) {
          final row = Map<String, dynamic>.from(raw as Map);
          final memberId = row['member_profile_id']?.toString();

          if (memberId != null && memberId.isNotEmpty) {
            activeClubMemberIds.add(memberId);
          }
        }
      }

      var emailCount = 0;

      for (final row in rows) {
        final memberId = row['member_profile_id']?.toString() ?? '';
        if (!activeClubMemberIds.contains(memberId)) continue;

        final profileRaw = row['member_profile'];
        final profile = profileRaw is Map
            ? Map<String, dynamic>.from(profileRaw)
            : const <String, dynamic>{};

        final email = (profile['email_address'] ?? '').toString().trim();
        if (email.isNotEmpty) emailCount++;
      }

      if (!mounted) return;

      final activeCount = activeClubMemberIds.length;

      setState(() {
        _listIsActive = listRow['is_active'] == true;
        _activeMemberCount = activeCount;
        _emailRecipientCount = emailCount;

        if (emailCount == 0) {
          _sendEmail = false;
        }

        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<bool> _confirmSend() async {
    final appCount = _sendApp ? _activeMemberCount : 0;
    final emailCount = _sendEmail ? _emailRecipientCount : 0;

    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Send mailing-list message?'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.mailingListName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Text('Active list members: $_activeMemberCount'),
                  Text('App messages to create: $appCount'),
                  Text('Emails to queue: $emailCount'),
                  if (_sendEmail && _membersWithoutEmail > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '$_membersWithoutEmail member(s) have no email address. '
                      'They will still receive the app message when that '
                      'option is selected.',
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'This creates the messages immediately and cannot be '
                    'undone from this screen.',
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.send),
                label: const Text('Send'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _send() async {
    if (_sending || _loading) return;

    final subject = _subjectController.text.trim();
    final message = _messageController.text.trim();

    if (!_listIsActive) {
      setState(() {
        _error = 'This mailing list is inactive and cannot be used.';
      });
      return;
    }

    if (_activeMemberCount == 0) {
      setState(() {
        _error = 'There are no active members on this mailing list.';
      });
      return;
    }

    if (subject.isEmpty) {
      setState(() {
        _error = 'Please enter a subject.';
      });
      return;
    }

    if (message.isEmpty) {
      setState(() {
        _error = 'Please enter a message.';
      });
      return;
    }

    if (!_sendApp && !_sendEmail) {
      setState(() {
        _error = 'Select app notification, email, or both.';
      });
      return;
    }

    if (_sendEmail && _emailRecipientCount == 0) {
      setState(() {
        _error = 'No active list members have an email address.';
      });
      return;
    }

    final confirmed = await _confirmSend();
    if (!confirmed || !mounted) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final rawResult = await Supabase.instance.client.rpc(
        'queue_mailing_list_message',
        params: {
          'p_mailing_list_id': widget.mailingListId,
          'p_subject': subject,
          'p_message': message,
          'p_send_app': _sendApp,
          'p_send_email': _sendEmail,
        },
      );

      final result = rawResult is Map
          ? Map<String, dynamic>.from(rawResult)
          : const <String, dynamic>{};

      final recipientCount =
          int.tryParse('${result['recipient_count'] ?? 0}') ?? 0;
      final appCreated =
          int.tryParse('${result['app_messages_created'] ?? 0}') ?? 0;
      final emailsQueued = int.tryParse('${result['emails_queued'] ?? 0}') ?? 0;
      final noEmail =
          int.tryParse('${result['members_without_email'] ?? 0}') ?? 0;

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Message created'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recipients recorded: $recipientCount'),
              Text('App messages created: $appCreated'),
              Text('Emails queued: $emailsQueued'),
              if (_sendEmail && noEmail > 0)
                Text('Members without email: $noEmail'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _sending = false;
        _error = e.toString();
      });
    }
  }

  Widget _summaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.mailingListName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Active members: $_activeMemberCount'),
            Text('Members with email: $_emailRecipientCount'),
            if (_membersWithoutEmail > 0)
              Text('Members without email: $_membersWithoutEmail'),
            if (!_listIsActive) ...[
              const SizedBox(height: 8),
              const Text(
                'This list is inactive.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSend =
        !_loading && !_sending && _listIsActive && _activeMemberCount > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Send to ${widget.mailingListName}'),
        actions: [
          IconButton(
            tooltip: 'Refresh recipients',
            onPressed: _loading || _sending ? null : _loadRecipientSummary,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _summaryCard(),
                const SizedBox(height: 16),
                TextField(
                  controller: _subjectController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Subject',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _messageController,
                  minLines: 8,
                  maxLines: 16,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('Send app notification'),
                        subtitle: Text('$_activeMemberCount app message(s)'),
                        value: _sendApp,
                        onChanged: _sending
                            ? null
                            : (value) {
                                setState(() {
                                  _sendApp = value;
                                  _error = null;
                                });
                              },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('Send email'),
                        subtitle: Text(_emailSummary),
                        value: _sendEmail,
                        onChanged: _sending || _emailRecipientCount == 0
                            ? null
                            : (value) {
                                setState(() {
                                  _sendEmail = value;
                                  _error = null;
                                });
                              },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: canSend ? _send : null,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(_sending ? 'Sending...' : 'Review and Send'),
                ),
              ],
            ),
    );
  }
}
