import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FixtureMessageScreen extends StatefulWidget {
  final String fixtureId;
  final String? currentMemberProfileId;
  final String senderName;

  const FixtureMessageScreen({
    super.key,
    required this.fixtureId,
    required this.currentMemberProfileId,
    required this.senderName,
  });

  @override
  State<FixtureMessageScreen> createState() => _FixtureMessageScreenState();
}

class _FixtureMessageScreenState extends State<FixtureMessageScreen> {
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  String? _error;

  Map<String, dynamic>? _fixture;
  String? _currentMemberProfileId;
  String _senderName = '';

  bool _includePlayers = true;
  bool _includeReserves = false;
  bool _includeOpponents = false;
  bool _includeMarkers = false;
  bool _includeCaptainVice = false;

  String? _teamSelectionId;

  final Map<String, Map<String, dynamic>> _recipientsByMemberId = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final supabase = Supabase.instance.client;

      _currentMemberProfileId = widget.currentMemberProfileId;
      _senderName = widget.senderName;

      final fixture = await supabase
          .from('fixtures')
          .select('''
            id,
            club_id,
            start_at,
            is_home,
            captain_member_profile_id,
            vice_captain_member_profile_id,
            competition_types(name, selection_mode),
            venue:venues!fixtures_venue_id_fkey(name),
            opponent_venue:venues!fixtures_opponent_venue_id_fkey(name)
          ''')
          .eq('id', widget.fixtureId)
          .single();

      _fixture = Map<String, dynamic>.from(fixture);

      await _loadRecipients();

      if (!mounted) return;
      setState(() {
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

  Future<void> _loadRecipients() async {
    _recipientsByMemberId.clear();

    final supabase = Supabase.instance.client;

    void addRecipient({
      required String? memberId,
      required String? name,
      required String role,
    }) {
      if (memberId == null || memberId.trim().isEmpty) return;

      _recipientsByMemberId[memberId] = {
        'member_profile_id': memberId,
        'name': name?.trim().isNotEmpty == true ? name!.trim() : 'Member',
        'role': role,
      };
    }

    // Captain / vice from fixture.
    addRecipient(
      memberId: _fixture?['captain_member_profile_id']?.toString(),
      name: 'Captain',
      role: 'captain',
    );

    addRecipient(
      memberId: _fixture?['vice_captain_member_profile_id']?.toString(),
      name: 'Vice-Captain',
      role: 'vice_captain',
    );

    // Team selection members: players/reserves/opponents/markers.
    final selection = await supabase
        .from('team_selections')
        .select('id')
        .eq('fixture_id', widget.fixtureId)
        .maybeSingle();

    final selectionId = selection?['id']?.toString();

    if (selectionId == null || selectionId.isEmpty) {
      return;
    }

    _teamSelectionId = selectionId;

    final rows = await supabase
        .from('team_selection_members')
        .select('''
        member_profile_id,
        role,
        member_profile:member_profiles!team_selection_members_member_profile_id_fkey(display_name)
        ''')
        .eq('team_selection_id', selectionId);

    for (final raw in rows as List) {
      final row = Map<String, dynamic>.from(raw as Map);
      final mp = row['member_profile'] as Map?;
      addRecipient(
        memberId: row['member_profile_id']?.toString(),
        name: mp?['display_name']?.toString(),
        role: row['role']?.toString() ?? 'player',
      );
    }
  }

  String get _fixtureLabel {
    final ct = _fixture?['competition_types'] as Map?;
    return ct?['name']?.toString() ?? 'Fixture';
  }

  DateTime? get _fixtureStartAt {
    final raw = _fixture?['start_at']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  bool _roleIncluded(String role) {
    final clean = role.toLowerCase();

    if (_includePlayers && clean == 'player') return true;
    if (_includeReserves && clean == 'reserve') return true;
    if (_includeOpponents && clean == 'opponent') return true;
    if (_includeMarkers && clean == 'marker') return true;
    if (_includeCaptainVice &&
        (clean == 'captain' || clean == 'vice_captain')) {
      return true;
    }

    return false;
  }

  List<Map<String, dynamic>> get _selectedRecipients {
    return _recipientsByMemberId.values
        .where((r) => _roleIncluded(r['role']?.toString() ?? ''))
        .toList();
  }

  Future<void> _send() async {
    final title = _titleController.text.trim();
    final message = _messageController.text.trim();

    if (title.isEmpty) {
      setState(() => _error = 'Please enter a title.');
      return;
    }

    if (message.isEmpty) {
      setState(() => _error = 'Please enter a message.');
      return;
    }

    final recipients = _selectedRecipients;
    if (recipients.isEmpty) {
      setState(() => _error = 'Please select at least one recipient group.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final startAt = _fixtureStartAt;

      final rows = recipients.map((r) {
        return {
          'event_type': 'fixture_message',
          'member_profile_id': _currentMemberProfileId,
          'target_member_profile_id': r['member_profile_id'],
          'fixture_id': widget.fixtureId,
          'team_selection_id': _teamSelectionId,
          'payload': {
            'title': title,
            'message': message,
            'sender_name': _senderName,
            'recipient_role': r['role'],
            'fixture_label': _fixtureLabel,
            'fixture_date': startAt?.toIso8601String(),
          },
          'status': 'pending',
        };
      }).toList();

      await supabase.from('notification_queue').insert(rows);

      // Keep this if you want immediate delivery into app_notifications.
      await supabase.rpc('process_notification_queue');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Message sent to ${recipients.length} recipient(s).'),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _sending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedRecipients.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Send Fixture Message')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _fixture == null
          ? Center(child: Text(_error!))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _messageController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Message',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Send to',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                CheckboxListTile(
                  value: _includePlayers,
                  title: const Text('Players'),
                  onChanged: (v) =>
                      setState(() => _includePlayers = v ?? false),
                ),
                CheckboxListTile(
                  value: _includeReserves,
                  title: const Text('Reserves'),
                  onChanged: (v) =>
                      setState(() => _includeReserves = v ?? false),
                ),
                CheckboxListTile(
                  value: _includeOpponents,
                  title: const Text('Opponents'),
                  onChanged: (v) =>
                      setState(() => _includeOpponents = v ?? false),
                ),
                CheckboxListTile(
                  value: _includeMarkers,
                  title: const Text('Markers'),
                  onChanged: (v) =>
                      setState(() => _includeMarkers = v ?? false),
                ),
                CheckboxListTile(
                  value: _includeCaptainVice,
                  title: const Text('Captain / Vice-Captain'),
                  onChanged: (v) =>
                      setState(() => _includeCaptainVice = v ?? false),
                ),
                const SizedBox(height: 12),
                Text('Recipients selected: $selectedCount'),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: _sending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: const Text('Send Message'),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
    );
  }
}
