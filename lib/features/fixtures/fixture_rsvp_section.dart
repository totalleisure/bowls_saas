import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FixtureRsvpSection extends StatefulWidget {
  final Map<String, dynamic> fixture;

  const FixtureRsvpSection({
    super.key,
    required this.fixture,
  });

  @override
  State<FixtureRsvpSection> createState() => _FixtureRsvpSectionState();
}

class _FixtureRsvpSectionState extends State<FixtureRsvpSection> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _displayStatus(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'yes':
        return 'Accepted';
      case 'maybe':
        return 'Maybe';
      case 'no':
        return 'Declined';
      default:
        return 'Pending';
    }
  }

  Color? _statusColor(String? status) {
    switch ((status ?? '').toLowerCase()) {
      case 'yes':
        return const Color(0xFFE8F5E9); // soft green
      case 'maybe':
        return const Color(0xFFFFF8E1); // soft amber
      case 'no':
        return const Color(0xFFFFEBEE); // soft red
      default:
        return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fixtureId = widget.fixture['id']?.toString();
      final clubId = widget.fixture['club_id']?.toString();

      if (fixtureId == null || clubId == null) {
        throw Exception('Fixture missing id/club_id');
      }

      // All active club members
      final memberRows = await _client
          .from('club_memberships')
          .select('member_profile_id, member_profiles(display_name, first_name, last_name)')
          .eq('club_id', clubId)
          .eq('is_active', true);

      // RSVP responses for this fixture
      final rsvpRows = await _client
          .from('fixture_rsvps')
          .select('member_profile_id, status')
          .eq('fixture_id', fixtureId);

      final rsvpByMemberId = <String, String>{};
      for (final r in List<Map<String, dynamic>>.from(rsvpRows)) {
        final memberId = r['member_profile_id']?.toString();
        final status = r['status']?.toString();
        if (memberId != null && status != null) {
          rsvpByMemberId[memberId] = status;
        }
      }

      final rows = <Map<String, dynamic>>[];

      for (final m in List<Map<String, dynamic>>.from(memberRows)) {
        final memberId = m['member_profile_id']?.toString();
        if (memberId == null || memberId.isEmpty) continue;

        final mp = m['member_profiles'] as Map<String, dynamic>?;
        final displayName = (mp?['display_name'] ?? '').toString().trim();
        final firstName = (mp?['first_name'] ?? '').toString().trim();
        final lastName = (mp?['last_name'] ?? '').toString().trim();

        final fallbackName = ('$firstName $lastName').trim();
        final name = displayName.isNotEmpty
            ? displayName
            : (fallbackName.isNotEmpty ? fallbackName : memberId);

        rows.add({
          'member_profile_id': memberId,
          'display_name': name,
          'status': rsvpByMemberId[memberId], // null => Pending
        });
      }

      rows.sort((a, b) =>
          (a['display_name'] as String).compareTo(b['display_name'] as String));

      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error: $_error'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RSVP responses',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_rows.isEmpty)
          const Text('No members found.')
        else
          ..._rows.map((r) {
            final name = r['display_name']?.toString() ?? '(no name)';
            final status = r['status']?.toString();

            return Card(
              color: _statusColor(status),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                title: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(_displayStatus(status)),
              ),
            );
          }),
      ],
    );
  }
}