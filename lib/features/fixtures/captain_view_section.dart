import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

class CaptainViewSection extends StatefulWidget {
  final Map<String, dynamic> fixture;
  const CaptainViewSection({super.key, required this.fixture});

  @override
  State<CaptainViewSection> createState() => _CaptainViewSectionState();
}


class _CaptainViewSectionState extends State<CaptainViewSection> {
  bool _loading = true;
  String? _error;

  String? _myProfileId;
  bool _isCaptain = false;

  List<Map<String, dynamic>> _yes = [];
  List<Map<String, dynamic>> _maybe = [];
  List<Map<String, dynamic>> _no = [];
  List<Map<String, dynamic>> _noResponse = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<String> _getMyProfileId() async {
    // Calls your existing SQL function: public.my_member_profile_id()
    final res = await Supabase.instance.client.rpc('my_member_profile_id');
    return res.toString(); // uuid returned as string-like
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fixtureId = widget.fixture['id'] as String;
      final clubId = widget.fixture['club_id'] as String;
      final captainId = widget.fixture['captain_member_profile_id'] as String?;

      final myId = await _getMyProfileId();
      _myProfileId = myId;

      _isCaptain = (captainId != null && captainId == myId);

      if (!_isCaptain) {
        // Not captain: hide details, but don't treat as error.
        setState(() => _loading = false);
        return;
      }

      // 1) Load RSVPs for this fixture
      final rsvpRows = await Supabase.instance.client
          .from('fixture_rsvps')
          .select('status, responded_at, member_profiles(display_name)')
          .eq('fixture_id', fixtureId);

      final rsvps = List<Map<String, dynamic>>.from(rsvpRows);

      // 2) Load all active members in the club (for "no response yet")
      final memberRows = await Supabase.instance.client
          .from('club_memberships')
          .select('member_profile_id, member_profiles(display_name)')
          .eq('club_id', clubId)
          .eq('is_active', true);

      final members = List<Map<String, dynamic>>.from(memberRows);

      // Build a set of member_profile_ids who responded
      final respondedIds = <String>{};
      for (final r in rsvps) {
        // r has member_profiles but not member_profile_id; we need it.
        // Easiest: fetch member_profile_id as well in RSVP query.
      }

      // Re-load RSVPs including member_profile_id (fix above)
      final rsvpRows2 = await Supabase.instance.client
          .from('fixture_rsvps')
          .select('member_profile_id, status, responded_at, member_profiles(display_name)')
          .eq('fixture_id', fixtureId);

      final rsvps2 = List<Map<String, dynamic>>.from(rsvpRows2);

      respondedIds.clear();
      for (final r in rsvps2) {
        respondedIds.add(r['member_profile_id'] as String);
      }

      // Split RSVPs by status
      List<Map<String, dynamic>> byStatus(String s) {
        final rows = rsvps2.where((r) => r['status'] == s).toList();
        rows.sort((a, b) {
          final an = (a['member_profiles']?['display_name'] as String?) ?? '';
          final bn = (b['member_profiles']?['display_name'] as String?) ?? '';
          return an.compareTo(bn);
        });
        return rows;
      }

      final yes = byStatus('yes');
      final maybe = byStatus('maybe');
      final no = byStatus('no');

      // No response list
      final noResp = <Map<String, dynamic>>[];
      for (final m in members) {
        final mpId = m['member_profile_id'] as String;
        if (!respondedIds.contains(mpId)) {
          noResp.add(m);
        }
      }
      noResp.sort((a, b) {
        final an = (a['member_profiles']?['display_name'] as String?) ?? '';
        final bn = (b['member_profiles']?['display_name'] as String?) ?? '';
        return an.compareTo(bn);
      });

      setState(() {
        _yes = yes;
        _maybe = maybe;
        _no = no;
        _noResponse = noResp;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _nameFromRow(Map<String, dynamic> row) {
    final mp = row['member_profiles'] as Map<String, dynamic>?;
    final name = (mp?['display_name'] as String?) ?? '(no name)';
    return Text(name);
  }

  Widget _section(String title, List<Map<String, dynamic>> rows) {
    return ExpansionTile(
      title: Text('$title (${rows.length})'),
      children: rows.isEmpty
          ? [ListTile(title: Text('None'))]
          : rows.map((r) => ListTile(title: _nameFromRow(r))).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Card(
        child: ListTile(
          title: const Text('Captain view error'),
          subtitle: Text(_error!),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ),
      );
    }

    if (!_isCaptain) {
      return const SizedBox.shrink(); // hide completely
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            ListTile(
              title: const Text('Captain view'),
              subtitle: Text('You are the captain.'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              ),
            ),
            _section('Yes', _yes),
            _section('Maybe', _maybe),
            _section('No', _no),
            _section('No response yet', _noResponse),
          ],
        ),
      ),
    );
  }
}


