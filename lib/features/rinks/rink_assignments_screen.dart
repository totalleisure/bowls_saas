import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/date_format.dart';

import 'package:bowls_saas/Services/team_sheet_pdf.dart';
import 'package:bowls_saas/Services/team_sheet_share.dart';

class RinkAssignmentsScreen extends StatefulWidget {
  final String fixtureId;
  final String teamSelectionId;

  const RinkAssignmentsScreen({
    super.key,
    required this.fixtureId,
    required this.teamSelectionId,
  });

  @override
  State<RinkAssignmentsScreen> createState() => _RinkAssignmentsScreenState();
}

class _RinkAssignmentsScreenState extends State<RinkAssignmentsScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _rinks = [];
  List<Map<String, dynamic>> _pool = [];

  // For colouring dropdown options: member_profile_id values already assigned
  Set<String> _assignedMemberIds = {};

  //Map<String, List<Map<String, dynamic>>> _assignmentsByRink = {};
  Map<String, Map<int, Map<String, dynamic>>> _assignmentsByRink = {};
  
  Future<Map<String, dynamic>> _loadFixtureHeader(String fixtureId) async {
    final row = await Supabase.instance.client
        .from('fixtures')
        .select('''
          start_at,
          is_home,
          section,
          club_id,
          venue_id,
          opponent_venue_id,
          captain_member_profile_id,
          vice_captain_member_profile_id,
          clubs(name),
          venue:venues!fixtures_venue_id_fkey(
            id,
            name,
            clubs(name)
          ),
          opponent_venue:venues!fixtures_opponent_venue_id_fkey(
            id,
            name,
            clubs(name)
          ),
          captain:member_profiles!fixtures_captain_member_profile_id_fkey(
            id,
            display_name,
            first_name,
            last_name,
            email_address,
            phone
          ),
          vice_captain:member_profiles!fixtures_vice_captain_member_profile_id_fkey(
            id,
            display_name,
            first_name,
            last_name,
            email_address,
            phone
          )
        ''')
        .eq('id', fixtureId)
        .single();

    return Map<String, dynamic>.from(row);
  }

  Map<String, dynamic>? _memberProfileFromPool(String? memberProfileId) {
    if (memberProfileId == null || memberProfileId.isEmpty) return null;

    for (final r in _pool) {
      final id = r['member_profile_id']?.toString() ?? '';
      if (id == memberProfileId) {
        final profile = r['member_profiles'];
        if (profile is Map<String, dynamic>) return profile;
        if (profile is Map) return Map<String, dynamic>.from(profile);
      }
    }
    return null;
  }

  String _clubOrVenueName(Map<String, dynamic>? venueRow) {
    if (venueRow == null) return '';
    final club = venueRow['clubs'];
    if (club is Map && (club['name']?.toString().trim().isNotEmpty ?? false)) {
      return club['name'].toString().trim();
    }
    final venueName = venueRow['name']?.toString().trim() ?? '';
    return venueName;
  }

  String _displayNameFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return '';

    final display = profile['display_name']?.toString().trim() ?? '';
    if (display.isNotEmpty) return display;

    final first = profile['first_name']?.toString().trim() ?? '';
    final last = profile['last_name']?.toString().trim() ?? '';
    return '$first $last'.trim();
  }

  String _emailFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return '';
    return profile['email_address']?.toString().trim() ?? '';
  }

  String _phoneFromProfile(Map<String, dynamic>? profile) {
    if (profile == null) return '';
    return profile['telephone']?.toString().trim() ??
        profile['phone']?.toString().trim() ??
        profile['mobile']?.toString().trim() ??
        '';
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;

      // 1) Load rinks for this fixture
      final rinks = await client
          .from('fixture_rinks')
          .select('id, fixture_rink_no, format, players_per_rink, home_rink_label')
          .eq('fixture_id', widget.fixtureId);

      final rinkList = List<Map<String, dynamic>>.from(rinks);

      int _asInt(dynamic v) {
        if (v == null) return 0;
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v.toString()) ?? 0;
      }

      rinkList.sort((a, b) {
        final al = (a['home_rink_label'] as String?)?.trim();
        final bl = (b['home_rink_label'] as String?)?.trim();

        // if both labels exist, sort by label
        if (al != null && al.isNotEmpty && bl != null && bl.isNotEmpty) {
          return al.compareTo(bl);
        }

        // otherwise sort by fixture_rink_no
        final ao = _asInt(a['fixture_rink_no']);
        final bo = _asInt(b['fixture_rink_no']);
        return ao.compareTo(bo);
      });

      // 2) Load pool (players + reserves) from published team selection
      final poolRows = await client
          .from('team_selection_members')
          .select(
            'member_profile_id, role, acceptance, '
            'member_profiles(display_name)',
          )
          .eq('team_selection_id', widget.teamSelectionId)
          .inFilter('role', ['player', 'reserve']);

      // 3) Load assignments
      final asnRows = await client
          .from('fixture_rink_assignments')
          .select('fixture_rink_id, position, member_profile_id, member_profiles(display_name)')
          .eq('fixture_id', widget.fixtureId);

      // Build lookup: rinkId -> position -> assignment row
      final byRink = <String, Map<int, Map<String, dynamic>>>{};
      final assigned = <String>{};

      for (final a in List<Map<String, dynamic>>.from(asnRows)) {
        final rinkId = a['fixture_rink_id'].toString();
        final pos = _asInt(a['position']);
        final mid = a['member_profile_id']?.toString();

        byRink.putIfAbsent(rinkId, () => {});
        byRink[rinkId]![pos] = a;

        if (mid != null && mid.isNotEmpty) assigned.add(mid);
      }

      if (!mounted) return;
      setState(() {
        _rinks = rinkList;
        _pool = List<Map<String, dynamic>>.from(poolRows);
        _assignmentsByRink = byRink;
        _assignedMemberIds = assigned;
        _loading = false;
      });
    } catch (e) {
      debugPrint('RinkAssignments load error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _formatLabel(String f) {
    if (f == 'pairs') return 'Pairs';
    if (f == 'triples') return 'Triples';
    return 'Rinks';
  }

  Future<void> _clearSlot(String rinkId, int position) async {
    try {
      await Supabase.instance.client
          .from('fixture_rink_assignments')
          .delete()
          .eq('fixture_rink_id', rinkId)
          .eq('position', position);

      await _loadAll();
    } catch (e) {
      debugPrint('RinkAssignments load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Clear failed: $e')));
      }
    }
  }

  Future<void> _assign({
    required String rinkId,
    required int position,
    required String memberProfileId,
  }) async {
    try {
      final client = Supabase.instance.client;

      // Remove any existing occupant of this slot
      await client
          .from('fixture_rink_assignments')
          .delete()
          .eq('fixture_rink_id', rinkId)
          .eq('position', position);

      // Remove this player from any other slot in this fixture
      await client
          .from('fixture_rink_assignments')
          .delete()
          .eq('fixture_id', widget.fixtureId)
          .eq('member_profile_id', memberProfileId);

      // Insert new assignment
      await client.from('fixture_rink_assignments').insert({
        'fixture_id': widget.fixtureId,
        'fixture_rink_id': rinkId,
        'member_profile_id': memberProfileId,
        'position': position,
      });

      await _loadAll();
    } catch (e) {
      debugPrint('RinkAssignments load error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Assign failed: $e')));
      }
    }
  }

  Future<void> _shareTeamSheetPdf() async {
    try {
      // Ensure we have rinks/pool/assignments loaded
      if (_rinks.isEmpty) {
        await _loadAll();
      }

      final header = await _loadFixtureHeader(widget.fixtureId);

      Map<String, dynamic>? asMap(dynamic v) {
        if (v is Map<String, dynamic>) return v;
        if (v is Map) return Map<String, dynamic>.from(v);
        return null;
      }

      String venueNameOnly(Map<String, dynamic>? venueRow) {
        if (venueRow == null) return '';
        return venueRow['name']?.toString().trim() ?? '';
      }

      final clubName =
          header['clubs']?['name']?.toString().trim() ??
          'Club';

      final isHome = header['is_home'] == true;

      final venueRow = asMap(header['venue']);
      final opponentVenueRow = asMap(header['opponent_venue']);

      // IMPORTANT RULE:
      // home  -> opponent is opponent_venue.name
      // away  -> opponent is venue.name
      final opponentName = isHome
          ? venueNameOnly(opponentVenueRow)
          : venueNameOnly(venueRow);

      final safeOpponentName =
          opponentName.isEmpty ? 'Opponent' : opponentName;

      final startAt = DateTime.tryParse(header['start_at']?.toString() ?? '') ?? DateTime.now();
      final section = header['section']?.toString() ?? '';

      // 1) role lookup + reserves from _pool (team_selection_members)
      final roleByMember = <String, String>{};
      final reserves = <String>[];

      for (final r in _pool) {
        final mpId = r['member_profile_id']?.toString() ?? '';
        final role = r['role']?.toString().toLowerCase() ?? '';
        final name = r['member_profiles']?['display_name']?.toString() ?? '';
        if (mpId.isNotEmpty) roleByMember[mpId] = role;
        if (role == 'reserve' && name.isNotEmpty) reserves.add(name);
      }

      // 2) Build TeamSheetRink list
      final rinks = <TeamSheetRink>[];
      int playersPerRink = 4;

      for (final rr in _rinks) {
        final rinkId = rr['id']?.toString() ?? '';
        final rinkNo = (rr['fixture_rink_no'] as int?) ?? 0;
        final label = rr['home_rink_label']?.toString();
        final ppr = (rr['players_per_rink'] as int?) ?? 4;
        playersPerRink = ppr;

        final byPos = _assignmentsByRink[rinkId] ?? <int, Map<String, dynamic>>{};
        final positions = byPos.keys.toList()..sort();

        final players = <String>[];
        for (final pos in positions) {
          final a = byPos[pos]!;
          final mpId = a['member_profile_id']?.toString() ?? '';
          final role = roleByMember[mpId] ?? 'player';
          if (role == 'reserve') continue;

          final name = a['member_profiles']?['display_name']?.toString() ?? '';
          if (name.isNotEmpty) players.add(name);
        }

        rinks.add(
          TeamSheetRink(
            rinkNumber: rinkNo,
            homeRinkLabel: label,
            players: players,
          ),
        );
      }

      final captainId = header['captain_member_profile_id']?.toString() ?? '';
      final viceId = header['vice_captain_member_profile_id']?.toString() ?? '';

      final captainProfile = _memberProfileFromPool(captainId);
      final viceProfile = _memberProfileFromPool(viceId);

      final captain = asMap(header['captain']);
      final vice = asMap(header['vice_captain']);

      final captainName = _displayNameFromProfile(captain);
      final captainEmail = _emailFromProfile(captain);
      final captainPhone = _phoneFromProfile(captain);

      final viceName = _displayNameFromProfile(vice);
      final viceEmail = _emailFromProfile(vice);
      final vicePhone = _phoneFromProfile(vice);

      debugPrint('TEAM_SHEET isHome=$isHome');
      debugPrint('TEAM_SHEET venueRow=$venueRow');
      debugPrint('TEAM_SHEET opponentVenueRow=$opponentVenueRow');
      debugPrint('TEAM_SHEET clubName=$clubName');
      debugPrint('TEAM_SHEET opponentName=$safeOpponentName');

      // 3) Build TeamSheetData
      final data = TeamSheetData(
        clubName: clubName,
        opponentName: safeOpponentName,
        startAt: startAt,
        isHome: isHome,
        section: section,
        rinksRequired: rinks.length,
        playersPerRink: playersPerRink,
        dress: 'Greys/Whites or Blacks',
        mealInfo: null,
        notes: null,
        captainName: captainName,
        captainEmail: captainEmail,
        captainPhone: captainPhone,
        viceName: viceName,
        viceEmail: viceEmail,
        vicePhone: vicePhone,
        rinks: rinks,
        reserves: reserves,
        primaryColor: 0xFF0B3D91,
        secondaryColor: 0xFFFFD200,
        logoBytes: null,
      );

      final pdfBytes = await buildTeamSheetPdf(data);

      final d = data.startAt.toLocal();
      final when = '${d.day.toString().padLeft(2,'0')}-${d.month.toString().padLeft(2,'0')}-${d.year}';
      final safeClub = data.clubName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '-');
      final safeOpp = data.opponentName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '-');

      final path = await shareTeamSheetPdf(
        pdfBytes,
        message: '${data.clubName} v ${data.opponentName} — ${data.startAt.toLocal()}',
        filename: '$safeClub v $safeOpp - $when.pdf',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF saved: $path')),
      );

    } catch (e) {
      debugPrint('Share team sheet failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Share failed: $e')),
      );
    }
  }

  List<DropdownMenuItem<String?>> _poolItems() {
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('—'),
      ),
    ];

    // Sort pool by name
    final sorted = [..._pool];
    sorted.sort((a, b) {
      final an = ((a['member_profiles']?['display_name']) as String?) ?? '';
      final bn = ((b['member_profiles']?['display_name']) as String?) ?? '';
      return an.compareTo(bn);
    });

    for (final p in sorted) {
      final id = p['member_profile_id'].toString();
      final mp = p['member_profiles'] as Map<String, dynamic>?;
      final name = (mp?['display_name'] as String?) ?? '(no name)';
      final role = p['role']?.toString() ?? '';
      final acc = p['acceptance']?.toString() ?? 'pending';

      final suffix = acc == 'accepted'
          ? ' ✅'
          : acc == 'declined'
              ? ' ❌'
              : ' ⏳';

      final roleTag = role == 'reserve' ? ' (R)' : '';

      items.add(
        DropdownMenuItem<String?>(
          value: id,
          child: Container(
            // IMPORTANT: no width: double.infinity and no vertical padding
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: _assignedMemberIds.contains(id)
                ? Colors.green.withOpacity(0.18)
                : Colors.red.withOpacity(0.14),
            alignment: Alignment.centerLeft,
            child: Text(
              '$name$roleTag$suffix',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ),
      );
    }

    return items;
  }

  String _positionLabel(int position, int playersPerRink) {
    if (position == 1) return 'Lead';
    if (position == playersPerRink) return 'Skip';

    // middle positions
    if (playersPerRink == 4) {
      return position == 2 ? '2' : '3';
    }
    if (playersPerRink == 3) {
      return '2';
    }
    return position.toString();
  }

  Widget _slotRow({
    required String rinkId,
    required int position,
    required int playersPerRink,
  }) {
    final asn = _assignmentsByRink[rinkId]?[position];
    final selectedId = asn?['member_profile_id']?.toString();

    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(_positionLabel(position, playersPerRink)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String?>(
            value: selectedId,
            isDense: true,
            decoration: const InputDecoration(labelText: 'Player'),
            items: _poolItems(),
            onChanged: (v) async {
              if (v == null) {
                await _clearSlot(rinkId, position);
              } else {
                await _assign(
                  rinkId: rinkId,
                  position: position,
                  memberProfileId: v,
                );
              }
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assign rinks & positions'),
        actions: [
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
          IconButton(
              tooltip: 'Share team sheet (PDF)',
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: _loading ? null : _shareTeamSheetPdf,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_rinks.isEmpty)
                      const Text('No rinks created yet. Go back and set up rinks first.')
                    else
                      ..._rinks.map((r) {
                        final rinkId = r['id'].toString();
                        final order = r['fixture_rink_no'] as int;
                        final fmt = r['format'].toString();
                        final ppr = (r['players_per_rink'] is num)
                            ? (r['players_per_rink'] as num).toInt()
                            : int.tryParse(r['players_per_rink']?.toString() ?? '') ?? 0;
                        final label = (r['home_rink_label'] as String?) ?? '';

                        final heading = 'Rink $order • ${_formatLabel(fmt)}'
                            '${label.isNotEmpty ? ' • $label' : ''}';

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  heading,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),

                                for (int pos = 1; pos <= ppr; pos++) ...[
                                  _slotRow(
                                    rinkId: rinkId,
                                    position: pos,
                                    playersPerRink: ppr,
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
    );
  }
}