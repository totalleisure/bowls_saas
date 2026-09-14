import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class MemberInvitationScreen extends StatefulWidget {
  const MemberInvitationScreen({
    super.key,
    required this.clubId,
    required this.storagePath,
    this.excludedEmails = const [],
  });
  final String clubId;
  final String storagePath;
  final List<String> excludedEmails;
  @override
  State<MemberInvitationScreen> createState() => _MemberInvitationScreenState();
}

class _MemberInvitationScreenState extends State<MemberInvitationScreen> {
  bool _busy = false, _resend = false;
  String? _error;
  List<dynamic> _guides = [], _recipients = [], _exceptions = [];
  final Set<String> _selected = {};
  final Map<String, String> _results = {};

  @override
  void initState() {
    super.initState();
    _loadGuides();
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final response = await Supabase.instance.client.functions.invoke(
      'member_invitations',
      body: {'club_id': widget.clubId, ...body},
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    if (response.status != 200 || data['error'] != null) {
      throw Exception(data['error'] ?? 'Request could not complete.');
    }
    return data;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is FunctionException ? '${e.details}' : '$e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadGuides() => _run(() async {
    final data = await _call({'action': 'guides'});
    if (mounted) setState(() => _guides = data['guides'] as List);
  });

  Future<void> _upload(String kind, String label) => _run(() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final file = picked.files.single;
    if (file.bytes == null || file.size > 1500000) {
      throw Exception('Choose a PDF smaller than 1.5 MB.');
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Use this $label?'),
        content: Text(
          '${file.name}\n\nThis becomes the guide for future invitations from this club. Please select the approved document.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use this guide'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    final data = await _call({
      'action': 'upload_guide',
      'kind': kind,
      'content': base64Encode(file.bytes!),
    });
    if (mounted) {
      setState(() {
        _guides = data['guides'] as List;
        _recipients = [];
        _exceptions = [];
        _selected.clear();
        _results.clear();
      });
    }
  });

  Future<void> _prepare() => _run(() async {
    final data = await _call({
      'action': 'preview',
      'storage_path': widget.storagePath,
      'resend': _resend,
      'excluded_emails': widget.excludedEmails,
    });
    if (!mounted) return;
    setState(() {
      _recipients = data['recipients'] as List;
      _exceptions = data['exceptions'] as List;
      _guides = data['guides'] as List;
      _selected
        ..clear()
        ..addAll(_recipients.map((r) => r['id'] as String));
      _results.clear();
    });
  });

  Future<void> _open(String value) async {
    try {
      if (!await launchUrl(
        Uri.parse(value),
        mode: LaunchMode.externalApplication,
      )) {
        throw Exception('Could not open the link.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'Could not open the document or link. Please try again.',
        );
      }
    }
  }

  Future<void> _preview(Map<String, dynamic> content) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Invitation preview'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: MemberInvitationPreview(content: content, onOpen: _open),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

  Future<void> _send() async {
    final chosen = _recipients
        .where(
          (r) => _selected.contains(r['id']) && !_results.containsKey(r['id']),
        )
        .toList();
    if (chosen.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Send ${chosen.length} invitations now?'),
        content: const Text(
          'Each selected member will receive their personalised email with both PDF guides attached. This will send real emails.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send invitations'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      for (final recipient in chosen) {
        if (!mounted) break;
        final id = recipient['id'] as String;
        try {
          final result = await _call({
            'action': 'send',
            'invitation_id': id,
            'confirm': true,
          });
          if (mounted) setState(() => _results[id] = '${result['status']}');
        } catch (_) {
          // A lost response may follow a successful send. Do not retry blindly.
          if (mounted) {
            setState(() {
              _results[id] = 'check';
              _error =
                  'Sending stopped because a result could not be confirmed. Prepare a new review to check which invitations can safely be retried.';
            });
          }
          break;
        }
      }
    });
  }

  String _status(String value) => switch (value) {
    'sent' => 'Accepted by the email service',
    'failed' =>
      'Email service rejected this invitation — prepare a new review to retry',
    'unknown' ||
    'sending' ||
    'check' => 'Outcome uncertain — check Sent Items; do not resend yet',
    _ => 'Not sent — prepare a new review',
  };

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('Review member invitations')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Both guides are attached to every invitation. Open them below to check the approved copies.',
            ),
            for (final entry in const {
              'introduction': 'Member introduction',
              'android': 'Android & Samsung installation guide',
            }.entries) ...[
              const SizedBox(height: 12),
              Text(entry.value, style: Theme.of(context).textTheme.titleMedium),
              Wrap(
                spacing: 12,
                children: [
                  for (final guide in _guides.where(
                    (g) => g['kind'] == entry.key,
                  ))
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _open(guide['url'] as String),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('Open guide'),
                    ),
                  TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _upload(entry.key, entry.value),
                    icon: const Icon(Icons.upload_file),
                    label: Text(
                      _guides.any((g) => g['kind'] == entry.key)
                          ? 'Replace guide'
                          : 'Add guide',
                    ),
                  ),
                ],
              ),
            ],
            const Divider(),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Resend invitations to previously invited members',
              ),
              subtitle: const Text(
                'Leave unchecked to skip members already invited.',
              ),
              value: _resend,
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _resend = v ?? false;
                      _recipients = [];
                      _exceptions = [];
                      _selected.clear();
                      _results.clear();
                    }),
            ),
            FilledButton.tonal(
              onPressed: _busy || _guides.length != 2 ? null : _prepare,
              child: const Text('Prepare invitation review'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_recipients.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '${_recipients.length} eligible members — select who to invite',
              ),
              for (final recipient in _recipients)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CheckboxListTile(
                          title: Text('${recipient['name']}'),
                          subtitle: Text(
                            '${recipient['email']}${recipient['resend'] == true ? '\nPreviously invited — resend selected' : ''}',
                          ),
                          value: _selected.contains(recipient['id']),
                          onChanged:
                              _busy || _results.containsKey(recipient['id'])
                              ? null
                              : (v) => setState(() {
                                  if (v == true) {
                                    _selected.add(recipient['id'] as String);
                                  } else {
                                    _selected.remove(recipient['id']);
                                  }
                                }),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _preview(
                                  Map<String, dynamic>.from(
                                    recipient['preview'] as Map,
                                  ),
                                ),
                          child: const Text('Preview personalised email'),
                        ),
                        if (_results[recipient['id']] != null)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(_status(_results[recipient['id']]!)),
                          ),
                      ],
                    ),
                  ),
                ),
              FilledButton(
                onPressed:
                    _busy || !_selected.any((id) => !_results.containsKey(id))
                    ? null
                    : _send,
                child: const Text('Send invitations'),
              ),
            ],
            if (_exceptions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                'Not included (${_exceptions.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final row in _exceptions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Row ${row['row']}: ${row['name']} ${row['email']}\n${row['reason']}',
                  ),
                ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Importing and inviting are separate. To retry rejected emails, prepare another review. Already accepted invitations are skipped by default. Acceptance by the email service does not confirm delivery to the inbox.',
            ),
          ],
        ),
      ),
    ),
  );
}

class MemberInvitationPreview extends StatelessWidget {
  const MemberInvitationPreview({
    super.key,
    required this.content,
    required this.onOpen,
  });
  final Map<String, dynamic> content;
  final void Function(String) onOpen;
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    child: DefaultTextStyle(
      style: const TextStyle(
        color: Color(0xff243b32),
        fontSize: 15,
        height: 1.6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Subject: ${content['subject']}'),
          ),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xff153f32),
              border: Border(
                top: BorderSide(color: Color(0xffd9b85b), width: 7),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${content['club']}',
                  style: const TextStyle(color: Color(0xffe1cc91)),
                ),
                const Text(
                  'Your club.\nNow at your fingertips.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Welcome to the Bowls Club App',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${content['greeting']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 12),
                Text('${content['introduction']}'),
              ],
            ),
          ),
          for (final section in content['sections'] as List)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${section['title']}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${section['text']}'),
                  if (section['link'] != null)
                    TextButton(
                      onPressed: () => onOpen(section['link'] as String),
                      child: Text('${section['link_label']}'),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text('${content['closing']}'),
          ),
        ],
      ),
    ),
  );
}
