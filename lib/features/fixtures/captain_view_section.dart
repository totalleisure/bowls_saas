// Captain response local-state collapsibles: 20260730-v1.
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
  String _viewerLabel = '';
  bool _isCaptain = false;
  bool _canView = false;
  // Local expansion state avoids PageStorage collisions with the parent
  // fixture-details scroll position.
  bool _showYes = false;
  bool _showMaybe = false;
  bool _showNo = false;
  bool _showNoResponse = false;

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
      final viceCaptainId =
          widget.fixture['vice_captain_member_profile_id'] as String?;

      final myId = await _getMyProfileId();
      _myProfileId = myId;

      final isCaptain = (captainId != null && captainId == myId);
      final isViceCaptain = (viceCaptainId != null && viceCaptainId == myId);

      // club admin?
      final adminRows = await Supabase.instance.client
          .from('club_memberships')
          .select('role')
          .eq('club_id', clubId)
          .eq('member_profile_id', myId)
          .eq('is_active', true);

      final isAdmin = List<Map<String, dynamic>>.from(
        adminRows,
      ).any((r) => (r['role']?.toString() ?? '') == 'admin');

      // superuser?
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final superRows = userId == null
          ? <dynamic>[]
          : await Supabase.instance.client
                .from('app_superusers')
                .select('user_id')
                .eq('user_id', userId);

      final isSuper = (superRows as List).isNotEmpty;

      _canView = isCaptain || isViceCaptain || isAdmin || isSuper;
      _isCaptain = isCaptain;

      if (isCaptain) {
        _viewerLabel = 'You are the captain.';
      } else if (isViceCaptain) {
        _viewerLabel = 'You are the vice-captain.';
      } else if (isAdmin) {
        _viewerLabel = 'You are viewing as club admin.';
      } else if (isSuper) {
        _viewerLabel = 'You are viewing as superuser.';
      } else {
        _viewerLabel = '';
      }

      if (!_canView) {
        setState(() => _loading = false);
        return;
      }

      /*       // 1) Load RSVPs for this fixture
      final rsvpRows = await Supabase.instance.client
          .from('fixture_rsvps')
          .select('status, responded_at, member_profiles(display_name)')
          .eq('fixture_id', fixtureId);

      final rsvps = List<Map<String, dynamic>>.from(rsvpRows);
*/

      // 2) Load all active members in the club (for "no response yet")
      final memberRows = await Supabase.instance.client
          .from('club_memberships')
          .select('member_profile_id, member_profiles(display_name)')
          .eq('club_id', clubId)
          .eq('is_active', true);

      final members = List<Map<String, dynamic>>.from(memberRows);

      // Build a set of member_profile_ids who responded

      final respondedIds = <String>{};
      /*
      for (final r in rsvps) {
        // r has member_profiles but not member_profile_id; we need it.
        // Easiest: fetch member_profile_id as well in RSVP query.
      }
*/

      // Re-load RSVPs including member_profile_id (fix above)
      final rsvpRows2 = await Supabase.instance.client
          .from('fixture_rsvps')
          .select(
            'member_profile_id, status, responded_at, member_profiles(display_name)',
          )
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

  Widget _section({
    required String title,
    required List<Map<String, dynamic>> rows,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    return Column(
      children: [
        ListTile(
          onTap: onToggle,
          title: Text('$title (${rows.length})'),
          trailing: Icon(
            expanded ? Icons.expand_less : Icons.expand_more,
          ),
        ),
        if (expanded) ...[
          if (rows.isEmpty)
            const ListTile(title: Text('None'))
          else
            ...rows.map((r) => ListTile(title: _nameFromRow(r))),
        ],
      ],
    );
  }

  Widget _noResponseSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          ListTile(
            onTap: () {
              setState(() {
                _showNoResponse = !_showNoResponse;
              });
            },
            title: Text('No response yet (${_noResponse.length})'),
            trailing: Icon(
              _showNoResponse ? Icons.expand_less : Icons.expand_more,
            ),
          ),
          if (_showNoResponse) ...[
            if (_noResponse.isEmpty)
              const ListTile(title: Text('None'))
            else
              ..._noResponse.map((r) {
                final name =
                    (r['member_profiles']?['display_name'] as String?) ??
                    '(no name)';
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(name),
                  subtitle: const Text('Pending'),
                );
              }),
          ],
        ],
      ),
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

    if (!_canView) {
      return const SizedBox.shrink(); // hide completely
    }

    final isRsvpFixture = widget.fixture['requires_rsvp'] == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            ListTile(
              title: Text(
                isRsvpFixture
                    ? 'Responses • Yes ${_yes.length} • Maybe ${_maybe.length} • No ${_no.length}'
                    : 'Team availability',
              ),
              subtitle: Text(_viewerLabel),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _load,
              ),
            ),
            _section(
              title: 'Yes',
              rows: _yes,
              expanded: _showYes,
              onToggle: () {
                setState(() {
                  _showYes = !_showYes;
                });
              },
            ),
            _section(
              title: 'Maybe',
              rows: _maybe,
              expanded: _showMaybe,
              onToggle: () {
                setState(() {
                  _showMaybe = !_showMaybe;
                });
              },
            ),
            _section(
              title: 'No',
              rows: _no,
              expanded: _showNo,
              onToggle: () {
                setState(() {
                  _showNo = !_showNo;
                });
              },
            ),
            _noResponseSection(),
          ],
        ),
      ),
    );
  }
}
