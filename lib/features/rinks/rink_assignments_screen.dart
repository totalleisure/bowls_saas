import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import '../../core/utils/date_format.dart';

import 'package:bowls_saas/services/team_sheet_pdf.dart';
import 'package:bowls_saas/services/team_sheet_share.dart';

class TeamSheetBuildResult {
  final TeamSheetData data;
  final Map<String, dynamic> header;

  TeamSheetBuildResult({required this.data, required this.header});
}

class RinkAssignmentsScreen extends StatefulWidget {
  final String fixtureId;
  final String teamSelectionId;

  final bool readOnly;

  const RinkAssignmentsScreen({
    super.key,
    required this.fixtureId,
    required this.teamSelectionId,
    this.readOnly = false,
  });

  @override
  State<RinkAssignmentsScreen> createState() => _RinkAssignmentsScreenState();
}

class _RinkAssignmentsScreenState extends State<RinkAssignmentsScreen> {
  bool _loading = true;
  bool _changed = false;
  int _assignmentPickerReset = 0;

  String? _error;
  String? _currentMemberProfileId;

  bool _checkingPermissions = true;

  bool _isSuperuser = false;
  bool _isClubAdmin = false;
  bool _isSelector = false;
  bool _isFixtureCaptain = false;
  bool _isFixtureViceCaptain = false;

  bool _canAssignRinks = false;
  bool _canPublishTeamSheet = false;
  bool _canView = true;

  bool _isPreselectFixture = false;
  bool _isInternalFixture = false;
  bool _publishedOrdinaryReadOnly = false;

  List<Map<String, dynamic>> _rinks = [];
  List<Map<String, dynamic>> _pool = [];

  Set<String> _assignedMemberIds = {};

  Map<String, Map<int, Map<String, dynamic>>> _assignmentsByRink = {};

  Future<Map<String, dynamic>> _loadFixtureHeader(String fixtureId) async {
    final row = await Supabase.instance.client
        .from('fixtures')
        .select('''
          start_at,
          is_home,
          section,
          club_id,
          team_id,
          requires_rsvp,
          venue_id,
          opponent_venue_id,
          captain_member_profile_id,
          vice_captain_member_profile_id,
          competition_type:competition_types!fixtures_competition_type_id_fkey(
            name,
            selection_mode,
            is_internal,
            colour_scheme_id,
            colour_scheme:fixture_colour_schemes!competition_types_colour_scheme_id_fkey(
              name,
              background_hex,
              foreground_hex
            )
          ),
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
    _init();
  }

  Future<void> _init() async {
    await _loadUserPermissions();
    await _loadAll();
  }

  Future<String?> _myMemberProfileId() async {
    try {
      final id = await Supabase.instance.client.rpc('my_member_profile_id');
      return id?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadUserPermissions() async {
    if (mounted) {
      setState(() => _checkingPermissions = true);
    }

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;

      if (user == null) {
        if (!mounted) return;
        setState(() {
          _isSuperuser = false;
          _isClubAdmin = false;
          _isSelector = false;
          _isFixtureCaptain = false;
          _isFixtureViceCaptain = false;
          _canAssignRinks = false;
          _canPublishTeamSheet = false;
        });
        return;
      }

      final header = await _loadFixtureHeader(widget.fixtureId);
      final clubId = header['club_id']?.toString() ?? '';

      final fixtureCaptainId =
          header['captain_member_profile_id']?.toString() ?? '';
      final fixtureViceCaptainId =
          header['vice_captain_member_profile_id']?.toString() ?? '';

      bool isSuperuser = false;
      bool isClubAdmin = false;
      bool isSelector = false;
      bool isFixtureCaptain = false;
      bool isFixtureViceCaptain = false;

      final su = await client
          .from('app_superusers')
          .select('user_id')
          .eq('user_id', user.id)
          .maybeSingle();

      isSuperuser = su != null;

      final mp = await client
          .from('member_profiles')
          .select('id')
          .eq('user_id', user.id)
          .maybeSingle();

      final myMemberProfileId = mp?['id']?.toString();
      _currentMemberProfileId = myMemberProfileId;

      if (clubId.isNotEmpty && myMemberProfileId != null) {
        final cm = await client
            .from('club_memberships')
            .select('role, is_active')
            .eq('club_id', clubId)
            .eq('member_profile_id', myMemberProfileId)
            .maybeSingle();

        final isActive = cm?['is_active'] == true;
        final role = (cm?['role'] ?? '').toString().toLowerCase();

        isClubAdmin = isActive && role == 'admin';
        isSelector = isActive && role == 'selector';
      }

      if (myMemberProfileId != null && myMemberProfileId.isNotEmpty) {
        isFixtureCaptain =
            fixtureCaptainId.isNotEmpty &&
            fixtureCaptainId == myMemberProfileId;
        isFixtureViceCaptain =
            fixtureViceCaptainId.isNotEmpty &&
            fixtureViceCaptainId == myMemberProfileId;
      }

      final canAssignRinks =
          !widget.readOnly &&
          (isSuperuser ||
              isClubAdmin ||
              isSelector ||
              isFixtureCaptain ||
              isFixtureViceCaptain);

      final canPublishTeamSheet =
          !widget.readOnly &&
          (isSuperuser ||
              isClubAdmin ||
              isSelector ||
              isFixtureCaptain ||
              isFixtureViceCaptain);

      debugPrint('--- RINK_ASSIGN permissions ---');
      debugPrint('_isSuperuser=$isSuperuser');
      debugPrint('_isClubAdmin=$isClubAdmin');
      debugPrint('_isSelector=$isSelector');
      debugPrint('_isFixtureCaptain=$isFixtureCaptain');
      debugPrint('_isFixtureViceCaptain=$isFixtureViceCaptain');
      debugPrint('_canAssignRinks=$canAssignRinks');
      debugPrint('_canPublishTeamSheet=$canPublishTeamSheet');

      if (!mounted) return;
      setState(() {
        _isSuperuser = isSuperuser;
        _isClubAdmin = isClubAdmin;
        _isSelector = isSelector;
        _isFixtureCaptain = isFixtureCaptain;
        _isFixtureViceCaptain = isFixtureViceCaptain;
        _canAssignRinks = canAssignRinks;
        _canPublishTeamSheet = canPublishTeamSheet;
      });
    } catch (e) {
      debugPrint('RINK_ASSIGN _loadUserPermissions error: $e');
      if (!mounted) return;
      setState(() {
        _isSuperuser = false;
        _isClubAdmin = false;
        _isSelector = false;
        _isFixtureCaptain = false;
        _isFixtureViceCaptain = false;
        _canAssignRinks = false;
        _canPublishTeamSheet = false;
      });
    } finally {
      if (mounted) {
        setState(() => _checkingPermissions = false);
      }
    }
  }

  Future<TeamSheetBuildResult> _buildTeamSheetData() async {
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

    int? parseColor(dynamic v) {
      if (v == null) return null;
      if (v is int) return v;

      final s = v.toString().trim();
      if (s.isEmpty) return null;

      if (s.startsWith('#')) {
        final hex = s.substring(1);
        if (hex.length == 6) {
          return int.tryParse('FF$hex', radix: 16);
        }
        if (hex.length == 8) {
          return int.tryParse(hex, radix: 16);
        }
      }

      if (s.startsWith('0x') || s.startsWith('0X')) {
        return int.tryParse(s.substring(2), radix: 16);
      }

      return int.tryParse(s);
    }

    final clubName = header['clubs']?['name']?.toString().trim() ?? 'Club';
    final isHome = header['is_home'] == true;

    final venueRow = asMap(header['venue']);
    final opponentVenueRow = asMap(header['opponent_venue']);

    final opponentName = isHome
        ? venueNameOnly(opponentVenueRow)
        : venueNameOnly(venueRow);

    final safeOpponentName = opponentName.trim();

    final startAt =
        DateTime.tryParse(header['start_at']?.toString() ?? '') ??
        DateTime.now();
    final section = header['section']?.toString() ?? '';

    final captain = asMap(header['captain']);
    final vice = asMap(header['vice_captain']);

    debugPrint(
      'TEAM_SHEET captain_member_profile_id=${header['captain_member_profile_id']}',
    );
    debugPrint(
      'TEAM_SHEET vice_captain_member_profile_id=${header['vice_captain_member_profile_id']}',
    );
    debugPrint('TEAM_SHEET captain raw=$captain');
    debugPrint('TEAM_SHEET vice raw=$vice');

    final competitionType = asMap(header['competition_type']);
    final colourScheme = asMap(competitionType?['colour_scheme']);

    final fixtureTypeName = (() {
      final s = competitionType?['name']?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    })();

    final isInternal = competitionType?['is_internal'] as bool?;
    final selectionMode = competitionType?['selection_mode']?.toString().trim();

    final fixtureTypeBgColor = parseColor(colourScheme?['background_hex']);

    final fixtureTypeFgColor = parseColor(colourScheme?['foreground_hex']);

    bool isPreselectInternalFixture() {
      final mode = (selectionMode ?? '').toLowerCase().trim();
      return mode == 'preselect' && isInternal == true;
    }

    final roleByMember = <String, String>{};
    final reserves = <String>[];

    for (final r in _pool) {
      final mpId = r['member_profile_id']?.toString() ?? '';
      final role = r['role']?.toString().toLowerCase() ?? '';
      final name = r['member_profiles']?['display_name']?.toString() ?? '';
      if (mpId.isNotEmpty) roleByMember[mpId] = role;
      if (role == 'reserve' && name.isNotEmpty) reserves.add(name);
    }

    final rinks = <TeamSheetRink>[];
    int playersPerRink = 4;

    for (final rr in _rinks) {
      final rinkId = rr['id']?.toString() ?? '';
      final rinkNo = (rr['fixture_rink_no'] as int?) ?? 0;
      final label = rr['home_rink_label']?.toString();
      final ppr = (rr['players_per_rink'] as int?) ?? 4;
      playersPerRink = ppr;

      final byPos = _assignmentsByRink[rinkId] ?? <int, Map<String, dynamic>>{};

      final players = <String>[];
      final opponents = <String>[];
      String? marker;

      if (isPreselectInternalFixture()) {
        for (int lineNo = 1; lineNo <= ppr; lineNo++) {
          final playerAsn = byPos[lineNo];
          final opponentAsn = byPos[100 + lineNo];

          final playerName =
              playerAsn?['member_profiles']?['display_name']?.toString() ?? '';
          final opponentName =
              opponentAsn?['member_profiles']?['display_name']?.toString() ??
              '';

          players.add(playerName);
          opponents.add(opponentName);
        }

        final markerAsn = byPos[201];
        final markerName =
            markerAsn?['member_profiles']?['display_name']?.toString() ?? '';
        marker = markerName.trim().isEmpty ? null : markerName.trim();
      } else {
        final positions = byPos.keys.toList()..sort();

        for (final pos in positions) {
          final a = byPos[pos]!;
          final mpId = a['member_profile_id']?.toString() ?? '';
          final role = roleByMember[mpId] ?? 'player';
          if (role == 'reserve') continue;

          final name = a['member_profiles']?['display_name']?.toString() ?? '';
          if (name.isNotEmpty) players.add(name);
        }
      }

      rinks.add(
        TeamSheetRink(
          rinkNumber: rinkNo,
          homeRinkLabel: label,
          players: players,
          opponents: opponents,
          marker: marker,
        ),
      );
    }

    debugPrint('TEAM_SHEET competitionType=$competitionType');
    debugPrint('TEAM_SHEET colourScheme=$colourScheme');
    debugPrint('TEAM_SHEET fixtureTypeName=$fixtureTypeName');
    debugPrint('TEAM_SHEET isInternal=$isInternal');
    debugPrint('TEAM_SHEET selectionMode=$selectionMode');
    debugPrint('TEAM_SHEET fixtureTypeBgColor=$fixtureTypeBgColor');
    debugPrint('TEAM_SHEET fixtureTypeFgColor=$fixtureTypeFgColor');
    debugPrint('TEAM_SHEET captainName=${_displayNameFromProfile(captain)}');
    debugPrint('TEAM_SHEET captainEmail=${_emailFromProfile(captain)}');
    debugPrint('TEAM_SHEET captainPhone=${_phoneFromProfile(captain)}');
    debugPrint('TEAM_SHEET viceName=${_displayNameFromProfile(vice)}');
    debugPrint('TEAM_SHEET viceEmail=${_emailFromProfile(vice)}');
    debugPrint('TEAM_SHEET vicePhone=${_phoneFromProfile(vice)}');

    for (final r in rinks) {
      debugPrint(
        'TEAM_SHEET rink=${r.rinkNumber} label=${r.homeRinkLabel} players=${r.players}',
      );
    }

    final data = TeamSheetData(
      clubName: clubName,
      opponentName: safeOpponentName,
      startAt: startAt,
      isHome: isHome,
      venueName: venueNameOnly(venueRow),
      section: section,
      rinksRequired: rinks.length,
      playersPerRink: playersPerRink,
      dress: 'Greys/Whites or Blacks',
      mealInfo: null,
      notes: null,
      captainName: _displayNameFromProfile(captain),
      captainEmail: _emailFromProfile(captain),
      captainPhone: _phoneFromProfile(captain),
      viceName: _displayNameFromProfile(vice),
      viceEmail: _emailFromProfile(vice),
      vicePhone: _phoneFromProfile(vice),
      rinks: rinks,
      reserves: reserves,
      primaryColor: 0xFF0B3D91,
      secondaryColor: 0xFFFFD200,
      logoBytes: null,
      fixtureTypeName: fixtureTypeName,
      fixtureTypeBgColor: fixtureTypeBgColor,
      fixtureTypeFgColor: fixtureTypeFgColor,
      isInternal: isInternal,
      selectionMode: selectionMode,
    );

    return TeamSheetBuildResult(data: data, header: header);
  }

  Future<void> _emailTeamSheet({required bool isResend}) async {
    try {
      final result = await _buildTeamSheetData();
      final data = result.data;
      final header = result.header;

      final pdfBytes = await buildTeamSheetPdf(data);

      Map<String, dynamic>? asMap(dynamic v) {
        if (v is Map<String, dynamic>) return v;
        if (v is Map) return Map<String, dynamic>.from(v);
        return null;
      }

      final recipientsByEmail = <String, Map<String, dynamic>>{};

      void addOrUpgradeRecipient({
        required String? email,
        required String? memberId,
        required String type,
        required String name,
      }) {
        if (email == null || email.trim().isEmpty) return;

        final cleanEmail = email.trim();

        const priority = {
          'reserve': 1,
          'player': 2,
          'vice_captain': 3,
          'captain': 4,
        };

        final existing = recipientsByEmail[cleanEmail];
        if (existing == null) {
          recipientsByEmail[cleanEmail] = {
            'member_profile_id': memberId,
            'email': cleanEmail,
            'type': type,
            'name': name,
          };
          return;
        }

        final existingType = existing['type']?.toString() ?? 'reserve';
        final existingPriority = priority[existingType] ?? 0;
        final newPriority = priority[type] ?? 0;

        if (newPriority >= existingPriority) {
          recipientsByEmail[cleanEmail] = {
            'member_profile_id': memberId ?? existing['member_profile_id'],
            'email': cleanEmail,
            'type': type,
            'name': name,
          };
        }
      }

      String? emailForDisplayName(String displayName) {
        for (final r in _pool) {
          final mp = r['member_profiles'];
          final name = mp?['display_name']?.toString().trim() ?? '';
          final email = mp?['email_address']?.toString().trim() ?? '';
          if (name == displayName && email.isNotEmpty) return email;
        }
        return null;
      }

      String? memberIdForDisplayName(String displayName) {
        for (final r in _pool) {
          final mp = r['member_profiles'];
          final name = mp?['display_name']?.toString().trim() ?? '';
          final memberId = r['member_profile_id']?.toString();
          if (name == displayName && memberId != null && memberId.isNotEmpty) {
            return memberId;
          }
        }
        return null;
      }

      for (final rink in data.rinks) {
        for (final playerName in rink.players) {
          addOrUpgradeRecipient(
            email: emailForDisplayName(playerName),
            memberId: memberIdForDisplayName(playerName),
            type: 'player',
            name: playerName,
          );
        }
      }

      for (final reserveName in data.reserves) {
        addOrUpgradeRecipient(
          email: emailForDisplayName(reserveName),
          memberId: memberIdForDisplayName(reserveName),
          type: 'reserve',
          name: reserveName,
        );
      }

      final captain = asMap(header['captain']);
      final vice = asMap(header['vice_captain']);

      final captainId = header['captain_member_profile_id']?.toString();
      final captainRoleName = _displayNameFromProfile(captain);
      final captainRoleEmail = _emailFromProfile(captain);

      addOrUpgradeRecipient(
        email: captainRoleEmail,
        memberId: captainId,
        type: 'captain',
        name: captainRoleName.isNotEmpty ? captainRoleName : 'Captain',
      );

      final viceId = header['vice_captain_member_profile_id']?.toString();
      final viceRoleName = _displayNameFromProfile(vice);
      final viceRoleEmail = _emailFromProfile(vice);

      addOrUpgradeRecipient(
        email: viceRoleEmail,
        memberId: viceId,
        type: 'vice_captain',
        name: viceRoleName.isNotEmpty ? viceRoleName : 'Vice-Captain',
      );

      final recipients = recipientsByEmail.values.toList();

      final d = toClubTime(data.startAt);
      final when =
          '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
      final safeClub = data.clubName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '-');
      final safeOpp = data.opponentName.replaceAll(
        RegExp(r'[<>:"/\\|?*]'),
        '-',
      );
      final filename = '$safeClub v $safeOpp - $when.pdf';

      final res = await Supabase.instance.client.functions.invoke(
        'send-team-sheet-emails',
        body: {
          'fixture_id': widget.fixtureId,
          'club_name': data.clubName,
          'opponent': data.opponentName,
          'start_at': data.startAt.toIso8601String(),
          'recipients': recipients,
          'attachment': {
            'name': filename,
            'contentType': 'application/pdf',
            'contentBytes': base64Encode(pdfBytes),
          },
        },
      );

      debugPrint('TEAM SHEET EMAIL RESPONSE: ${res.data}');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isResend
                ? 'Team sheet emails re-sent'
                : 'Team sheet published and emailed',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Team sheet email failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Email failed: $e')));
    }
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      _currentMemberProfileId = await _myMemberProfileId();

      final header = await _loadFixtureHeader(widget.fixtureId);

      final competitionType =
          header['competition_type'] as Map<String, dynamic>?;
      final selectionMode = (competitionType?['selection_mode'] ?? '')
          .toString()
          .toLowerCase()
          .trim();

      final isPreselect = selectionMode == 'preselect';
      final isInternal = competitionType?['is_internal'] == true;

      final selectionRow = await Supabase.instance.client
          .from('team_selections')
          .select('status')
          .eq('id', widget.teamSelectionId)
          .single();
      final publishedOrdinaryReadOnly =
          selectionRow['status']?.toString() == 'published' &&
          !isPreselect &&
          (header['team_id'] != null || header['requires_rsvp'] == true);

      debugPrint('RINK currentMemberProfileId=$_currentMemberProfileId');

      final client = Supabase.instance.client;

      // 1) Load rinks for this fixture
      final rinks = await client
          .from('fixture_rinks')
          .select(
            'id, fixture_rink_no, format, players_per_rink, home_rink_label',
          )
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
      final allowedRoles = (isPreselect && isInternal)
          ? ['player', 'opponent', 'marker']
          : ['player', 'reserve'];

      final poolRows = await client
          .from('team_selection_members')
          .select(
            'member_profile_id, role, acceptance, '
            'member_profiles!team_selection_members_member_profile_id_fkey(display_name, email_address)',
          )
          .eq('team_selection_id', widget.teamSelectionId)
          .eq('is_selected', true)
          .inFilter('role', allowedRoles);

      for (final r in List<Map<String, dynamic>>.from(poolRows)) {
        debugPrint(
          'RINK POOL member=${r['member_profiles']?['display_name']} '
          'role=${r['role']} '
          'memberId=${r['member_profile_id']}',
        );
      }

      // 3) Load assignments
      final asnRows = await client
          .from('fixture_rink_assignments')
          .select(
            'fixture_rink_id, position, member_profile_id, member_profiles(display_name)',
          )
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
        _isPreselectFixture = isPreselect;
        _isInternalFixture = isInternal;
        _publishedOrdinaryReadOnly = publishedOrdinaryReadOnly;
        if (publishedOrdinaryReadOnly) {
          _canAssignRinks = false;
        }
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

  List<Map<String, dynamic>> _currentAssignmentPayload() {
    final rows = <Map<String, dynamic>>[];

    for (final rinkEntry in _assignmentsByRink.entries) {
      final rinkId = rinkEntry.key;
      for (final positionEntry in rinkEntry.value.entries) {
        final memberProfileId = positionEntry.value['member_profile_id']
            ?.toString()
            .trim();

        if (memberProfileId == null || memberProfileId.isEmpty) {
          continue;
        }

        rows.add({
          'fixture_rink_id': rinkId,
          'position': positionEntry.key,
          'member_profile_id': memberProfileId,
        });
      }
    }

    return rows;
  }

  void _rebuildAssignedMemberIdsFromLocalAssignments() {
    final assigned = <String>{};

    for (final byPosition in _assignmentsByRink.values) {
      for (final row in byPosition.values) {
        final memberProfileId = row['member_profile_id']?.toString().trim();
        if (memberProfileId != null && memberProfileId.isNotEmpty) {
          assigned.add(memberProfileId);
        }
      }
    }

    _assignedMemberIds = assigned;
  }

  Future<void> _saveCurrentAssignments() async {
    await Supabase.instance.client.rpc(
      'save_fixture_rink_assignments',
      params: {
        'p_fixture_id': widget.fixtureId,
        'p_team_selection_id': widget.teamSelectionId,
        'p_assignments': _currentAssignmentPayload(),
      },
    );
  }

  Future<void> _clearSlot(String rinkId, int position) async {
    if (!_canAssignRinks) return;

    final previous = <String, Map<int, Map<String, dynamic>>>{};
    for (final entry in _assignmentsByRink.entries) {
      previous[entry.key] = Map<int, Map<String, dynamic>>.from(entry.value);
    }

    try {
      setState(() {
        _assignmentsByRink[rinkId]?.remove(position);
        if (_assignmentsByRink[rinkId]?.isEmpty == true) {
          _assignmentsByRink.remove(rinkId);
        }
        _rebuildAssignedMemberIdsFromLocalAssignments();
      });

      await _saveCurrentAssignments();
      _changed = true;
      await _loadAll();
    } catch (e) {
      setState(() {
        _assignmentsByRink = previous;
        _rebuildAssignedMemberIdsFromLocalAssignments();
      });

      debugPrint('RinkAssignments clear error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Clear failed: $e')));
      }
    }
  }

  Future<void> _assign({
    required String rinkId,
    required int position,
    required String memberProfileId,
  }) async {
    if (widget.readOnly || !_canAssignRinks) return;

    final previous = <String, Map<int, Map<String, dynamic>>>{};
    for (final entry in _assignmentsByRink.entries) {
      previous[entry.key] = Map<int, Map<String, dynamic>>.from(entry.value);
    }

    try {
      final client = Supabase.instance.client;

      // Check current selection role from source of truth before saving.
      // The RPC repeats validation server-side, but this lets us show a helpful confirmation.
      final existing = await client
          .from('team_selection_members')
          .select('role, is_selected')
          .eq('team_selection_id', widget.teamSelectionId)
          .eq('member_profile_id', memberProfileId)
          .eq('is_selected', true)
          .maybeSingle();

      if (existing == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'This member is no longer active in the team selection.',
              ),
            ),
          );
        }
        return;
      }

      final oldRole = (existing['role'] ?? '').toString().toLowerCase().trim();

      // If reserve, confirm promotion before assignment.
      // The actual promotion and notification are handled atomically by the RPC.
      if (oldRole == 'reserve') {
        final memberRow = _pool.cast<Map<String, dynamic>?>().firstWhere(
          (r) => (r?['member_profile_id']?.toString() ?? '') == memberProfileId,
          orElse: () => null,
        );

        final profile = memberRow?['member_profiles'] as Map<String, dynamic>?;
        final playerName =
            profile?['display_name']?.toString().trim().isNotEmpty == true
            ? profile!['display_name'].toString().trim()
            : [
                profile?['first_name']?.toString().trim() ?? '',
                profile?['last_name']?.toString().trim() ?? '',
              ].where((s) => s.isNotEmpty).join(' ');

        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Promote reserve to player?'),
            content: Text(
              playerName.isNotEmpty
                  ? '$playerName is currently marked as a reserve. Assigning them to a team will promote them to player. Continue?'
                  : 'This member is currently marked as a reserve. Assigning them to a team will promote them to player. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Promote and assign'),
              ),
            ],
          ),
        );

        if (confirmed != true) {
          if (mounted) {
            setState(() {
              _assignmentPickerReset++;
            });
          }
          return;
        }
      }

      setState(() {
        // Move semantics: a member can only occupy one slot in the fixture.
        for (final byPosition in _assignmentsByRink.values) {
          byPosition.removeWhere((_, row) {
            return row['member_profile_id']?.toString() == memberProfileId;
          });
        }

        _assignmentsByRink.removeWhere((_, byPosition) => byPosition.isEmpty);

        _assignmentsByRink.putIfAbsent(rinkId, () => {});
        _assignmentsByRink[rinkId]![position] = {
          'fixture_rink_id': rinkId,
          'position': position,
          'member_profile_id': memberProfileId,
        };

        _rebuildAssignedMemberIdsFromLocalAssignments();
      });

      await _saveCurrentAssignments();
      _changed = true;
      await _loadAll();
    } catch (e) {
      setState(() {
        _assignmentsByRink = previous;
        _rebuildAssignedMemberIdsFromLocalAssignments();
      });

      debugPrint('RinkAssignments assign error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Assign failed: $e')));
      }
    }
  }

  Future<void> _assignOrClear({
    required String rinkId,
    required int position,
    required String? memberProfileId,
  }) async {
    if (memberProfileId == null) {
      await _clearSlot(rinkId, position);
    } else {
      await _assign(
        rinkId: rinkId,
        position: position,
        memberProfileId: memberProfileId,
      );
    }
  }

  List<int>? _parseIncompleteTeamError(Object error) {
    final match = RegExp(
      r'INCOMPLETE_TEAM:(\d+):(\d+)',
    ).firstMatch(error.toString());
    if (match == null) return null;

    return [int.parse(match.group(1)!), int.parse(match.group(2)!)];
  }

  Future<bool> _confirmPublishIncomplete({
    required int requiredPositions,
    required int assignedPositions,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Publish incomplete team sheet?'),
        content: Text(
          'This team sheet is incomplete. '
          '$requiredPositions player positions are required, but only '
          '$assignedPositions have been assigned.\n\n'
          'Do you want to publish it anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Publish anyway'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _publishTeamSelection({required bool allowIncomplete}) async {
    await Supabase.instance.client.rpc(
      'publish_team_selection_safe',
      params: {
        'p_fixture_id': widget.fixtureId,
        'p_team_selection_id': widget.teamSelectionId,
        'p_allow_incomplete': allowIncomplete,
      },
    );
  }

  Future<void> _publishAndEmailTeamSheet() async {
    if (!_canPublishTeamSheet) return;

    try {
      try {
        await _publishTeamSelection(allowIncomplete: false);
      } catch (e) {
        final incomplete = _parseIncompleteTeamError(e);
        if (incomplete == null) rethrow;

        if (!mounted) return;
        final publishAnyway = await _confirmPublishIncomplete(
          requiredPositions: incomplete[0],
          assignedPositions: incomplete[1],
        );

        if (!publishAnyway) return;

        await _publishTeamSelection(allowIncomplete: true);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Team published. Preparing emails...')),
      );

      await _emailTeamSheet(isResend: false);
      await _loadAll();
    } catch (e) {
      debugPrint('Publish/email team sheet error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Publish failed: $e')));
    }
  }

  Future<void> _resendTeamSheetEmails() async {
    if (!_canPublishTeamSheet) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resend team sheet emails?'),
        content: const Text(
          'This will send the current team sheet emails again to the listed players and reserves.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resend'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _emailTeamSheet(isResend: true);
    }
  }

  Future<void> _shareTeamSheetPdf() async {
    try {
      final result = await _buildTeamSheetData();
      final data = result.data;

      debugPrint('TEAM_SHEET isHome=${data.isHome}');
      debugPrint('TEAM_SHEET clubName=${data.clubName}');
      debugPrint('TEAM_SHEET opponentName=${data.opponentName}');
      debugPrint('TEAM_SHEET fixtureType=${data.fixtureTypeName}');

      final pdfBytes = await buildTeamSheetPdf(data);

      final d = toClubTime(data.startAt);
      final when =
          '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';
      final safeClub = data.clubName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '-');
      final safeOpp = data.opponentName.replaceAll(
        RegExp(r'[<>:"/\\|?*]'),
        '-',
      );

      final path = await shareTeamSheetPdf(
        pdfBytes,
        message:
            '${data.clubName} v ${data.opponentName} — ${toClubTime(data.startAt)}',
        filename: '$safeClub v $safeOpp - $when.pdf',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF saved: $path')));
    } catch (e) {
      debugPrint('Share team sheet failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  List<DropdownMenuItem<String?>> _poolItems() {
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(value: null, child: Text('—')),
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

  List<DropdownMenuItem<String?>> _poolItemsFiltered(
    List<String> allowedRoles,
  ) {
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(value: null, child: Text('—')),
    ];

    final filtered = _pool.where((p) {
      final role = (p['role'] ?? '').toString().toLowerCase().trim();
      return allowedRoles.contains(role);
    }).toList();

    filtered.sort((a, b) {
      final an = ((a['member_profiles']?['display_name']) as String?) ?? '';
      final bn = ((b['member_profiles']?['display_name']) as String?) ?? '';
      return an.compareTo(bn);
    });

    for (final p in filtered) {
      final id = p['member_profile_id'].toString();
      final mp = p['member_profiles'] as Map<String, dynamic>?;
      final name = (mp?['display_name'] as String?) ?? '(no name)';
      final acc = p['acceptance']?.toString() ?? 'pending';

      final suffix = acc == 'accepted'
          ? ' ✅'
          : acc == 'declined'
          ? ' ❌'
          : ' ⏳';

      items.add(
        DropdownMenuItem<String?>(
          value: id,
          child: Text(
            '$name$suffix',
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
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

  int _playerPosition(int lineNo) => lineNo;
  int _opponentPosition(int lineNo) => 100 + lineNo;
  int get _markerPosition => 201;

  Widget _buildTeamSheetActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            OutlinedButton.icon(
              onPressed: _shareTeamSheetPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Save / Share Team Sheet PDF'),
            ),
          ],
        ),
        if (!_canAssignRinks)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'You have readonly access to team assignments.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ],
    );
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
            key: ValueKey(
              'slot-$rinkId-$position-${selectedId ?? 'none'}-$_assignmentPickerReset',
            ),
            value: selectedId,
            isDense: true,
            decoration: InputDecoration(
              labelText: 'Player',
              enabled: _canAssignRinks,
            ),
            items: _poolItems(),
            onChanged: widget.readOnly || !_canAssignRinks
                ? null
                : (v) async {
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

  Widget _matchupRow({required String rinkId, required int lineNo}) {
    final playerPos = _playerPosition(lineNo);
    final opponentPos = _opponentPosition(lineNo);

    final playerAsn = _assignmentsByRink[rinkId]?[playerPos];
    final opponentAsn = _assignmentsByRink[rinkId]?[opponentPos];

    final selectedPlayerId = playerAsn?['member_profile_id']?.toString();
    final selectedOpponentId = opponentAsn?['member_profile_id']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Position $lineNo'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                key: ValueKey(
                  'player-$rinkId-$playerPos-${selectedPlayerId ?? 'none'}-$_assignmentPickerReset',
                ),
                value: selectedPlayerId,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Player'),
                items: _poolItemsFiltered(['player']),
                onChanged: widget.readOnly || !_canAssignRinks
                    ? null
                    : (v) => _assignOrClear(
                        rinkId: rinkId,
                        position: playerPos,
                        memberProfileId: v,
                      ),
              ),
            ),
            const SizedBox(width: 8),
            // const Text('v'),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String?>(
                key: ValueKey(
                  'opponent-$rinkId-$opponentPos-${selectedOpponentId ?? 'none'}-$_assignmentPickerReset',
                ),
                value: selectedOpponentId,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Opponent'),
                items: _poolItemsFiltered(['opponent']),
                onChanged: widget.readOnly || !_canAssignRinks
                    ? null
                    : (v) => _assignOrClear(
                        rinkId: rinkId,
                        position: opponentPos,
                        memberProfileId: v,
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _markerRow({required String rinkId}) {
    final asn = _assignmentsByRink[rinkId]?[_markerPosition];
    final selectedId = asn?['member_profile_id']?.toString();

    return DropdownButtonFormField<String?>(
      key: ValueKey(
        'marker-$rinkId-${selectedId ?? 'none'}-$_assignmentPickerReset',
      ),
      value: selectedId,
      isDense: true,
      decoration: const InputDecoration(labelText: 'Marker (optional)'),
      items: _poolItemsFiltered(['marker']),
      onChanged: widget.readOnly || !_canAssignRinks
          ? null
          : (v) => _assignOrClear(
              rinkId: rinkId,
              position: _markerPosition,
              memberProfileId: v,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.readOnly || _publishedOrdinaryReadOnly
              ? 'View Teams & Positions'
              : 'Assign Teams & Positions',
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _changed),
        ),
        actions: [
          if (_publishedOrdinaryReadOnly)
            TextButton.icon(
              onPressed: () => Navigator.pop(context, _changed),
              icon: const Icon(Icons.groups),
              label: const Text('Back to Manage Team'),
            ),
          IconButton(onPressed: _loadAll, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_publishedOrdinaryReadOnly) ...[
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Published Team and RSVP composition changes must be staged and confirmed in Manage Team. Assignment editing is read-only here.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                _buildTeamSheetActions(),
                const SizedBox(height: 16),
                if (_rinks.isEmpty)
                  const Text(
                    'No teams created yet. Go back and set up teams first.',
                  )
                else
                  ..._rinks.map((r) {
                    final rinkId = r['id'].toString();
                    final order = r['fixture_rink_no'] as int;
                    final fmt = r['format'].toString();
                    final ppr = (r['players_per_rink'] is num)
                        ? (r['players_per_rink'] as num).toInt()
                        : int.tryParse(
                                r['players_per_rink']?.toString() ?? '',
                              ) ??
                              0;
                    final label = (r['home_rink_label'] as String?) ?? '';

                    final heading =
                        'Team $order • ${_formatLabel(fmt)}'
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),

                            //if (_isPreselectFixture && _isInternalFixture && ppr == 2) ...[
                            if (_isPreselectFixture && _isInternalFixture) ...[
                              for (int lineNo = 1; lineNo <= ppr; lineNo++) ...[
                                _matchupRow(rinkId: rinkId, lineNo: lineNo),
                                const SizedBox(height: 12),
                              ],
                              _markerRow(rinkId: rinkId),
                            ] else ...[
                              for (int pos = 1; pos <= ppr; pos++) ...[
                                _slotRow(
                                  rinkId: rinkId,
                                  position: pos,
                                  playersPerRink: ppr,
                                ),
                                const SizedBox(height: 8),
                              ],
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
