import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

class SetCaptainSection extends StatefulWidget {
  final Map<String, dynamic> fixture;
  const SetCaptainSection({super.key, required this.fixture});

  @override
  State<SetCaptainSection> createState() => _SetCaptainSectionState();
}


class _SetCaptainSectionState extends State<SetCaptainSection> {
  bool _loading = true;
  String? _error;

  bool _isAdmin = false;

  List<Map<String, dynamic>> _members = [];

  String? _selectedCaptainId;
  String? _selectedViceCaptainId;

  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _selectedCaptainId = widget.fixture['captain_member_profile_id'] as String?;
    _selectedViceCaptainId =
        widget.fixture['vice_captain_member_profile_id'] as String?;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final clubId = widget.fixture['club_id'] as String;
      final fixtureId = widget.fixture['id'] as String;

      // Fetch latest captain + vice from DB
      final fx = await client
          .from('fixtures')
          .select('captain_member_profile_id, vice_captain_member_profile_id')
          .eq('id', fixtureId)
          .single();

      _selectedCaptainId = fx['captain_member_profile_id'] as String?;
      _selectedViceCaptainId = fx['vice_captain_member_profile_id'] as String?;

      // Who am I?
      final myId = (await client.rpc('my_member_profile_id')).toString();

      // Am I admin of this club?
      final cm = await client
          .from('club_memberships')
          .select('role, is_active')
          .eq('club_id', clubId)
          .eq('member_profile_id', myId)
          .maybeSingle();

      _isAdmin = cm != null && (cm['is_active'] == true) && (cm['role'] == 'admin');

      if (!_isAdmin) {
        setState(() => _loading = false);
        return;
      }

      // Load active members
      final rows = await client
          .from('club_memberships')
          .select('member_profile_id, member_profiles(display_name)')
          .eq('club_id', clubId)
          .eq('is_active', true);

      _members = List<Map<String, dynamic>>.from(rows);

      _members.sort((a, b) {
        final an = (a['member_profiles']?['display_name'] as String?) ?? '';
        final bn = (b['member_profiles']?['display_name'] as String?) ?? '';
        return an.compareTo(bn);
      });

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _nameForMemberId(String? id) {
    if (id == null) return 'None';
    final match = _members.where((m) => m['member_profile_id'] == id).toList();
    if (match.isEmpty) return 'Unknown';
    final mp = match.first['member_profiles'] as Map<String, dynamic>?;
    return (mp?['display_name'] as String?) ?? 'Unknown';
    }

  List<DropdownMenuItem<String?>> _dropdownItems() {
    return [
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('None'),
      ),
      ..._members.map<DropdownMenuItem<String?>>((m) {
        final id = m['member_profile_id'] as String;
        final mp = m['member_profiles'] as Map<String, dynamic>?;
        final name = (mp?['display_name'] as String?) ?? '(no name)';
        return DropdownMenuItem<String?>(
          value: id,
          child: Text(name),
        );
      }),
    ];
  }

  Future<void> _saveCaptaincy() async {
    try {
      final client = Supabase.instance.client;
      final fixtureId = widget.fixture['id'] as String;

      final updated = await client
          .from('fixtures')
          .update({
            'captain_member_profile_id': _selectedCaptainId,
            'vice_captain_member_profile_id': _selectedViceCaptainId,
          })
          .eq('id', fixtureId)
          .select('captain_member_profile_id, vice_captain_member_profile_id')
          .single();

      setState(() {
        _selectedCaptainId = updated['captain_member_profile_id'] as String?;
        _selectedViceCaptainId =
            updated['vice_captain_member_profile_id'] as String?;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Captaincy saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Card(
        child: ListTile(
          title: const Text('Captaincy'),
          subtitle: Text(_error!),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ),
      );
    }

    if (!_isAdmin) return const SizedBox.shrink();

    final captainName = _nameForMemberId(_selectedCaptainId);
    final viceName = _nameForMemberId(_selectedViceCaptainId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Captaincy', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),

            if (!_editing) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Captain',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(captainName),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Vice-captain',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(viceName),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _editing = true),
                    child: const Text('Amend'),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _selectedCaptainId,
                      decoration: const InputDecoration(labelText: 'Captain'),
                      items: _dropdownItems(),
                      onChanged: (v) =>
                          setState(() => _selectedCaptainId = v),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      value: _selectedViceCaptainId,
                      decoration:
                          const InputDecoration(labelText: 'Vice-captain'),
                      items: _dropdownItems(),
                      onChanged: (v) =>
                          setState(() => _selectedViceCaptainId = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      await _saveCaptaincy();
                      setState(() => _editing = false);
                    },
                    child: const Text('Save'),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => setState(() => _editing = false),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}


