import 'package:supabase_flutter/supabase_flutter.dart';

typedef CompetitionRow = Map<String, dynamic>;

class CompetitionData {
  final CompetitionRow competition;
  final List<CompetitionRow> entries, rounds, matches;
  final Set<String> enteredMemberIds;
  const CompetitionData(
    this.competition,
    this.entries,
    this.rounds,
    this.matches, [
    this.enteredMemberIds = const {},
  ]);

  // A saved draw position is authoritative, regardless of transport row order.
  List<CompetitionRow> get orderedEntries {
    final result = [...entries];
    if (result.every((entry) => entry['entry_order'] is num)) {
      result.sort(
        (a, b) => (a['entry_order'] as num).compareTo(b['entry_order'] as num),
      );
    }
    return result;
  }

  List<CompetitionRow> get orderedRounds => [...rounds]
    ..sort(
      (a, b) => (a['round_number'] as num).compareTo(b['round_number'] as num),
    );

  List<CompetitionRow> matchesForRound(String roundId) =>
      matches.where((m) => m['round_id'] == roundId).toList()..sort(
        (a, b) =>
            (a['match_number'] as num).compareTo(b['match_number'] as num),
      );

  bool get usesIndividualHandicaps =>
      (competition['settings'] as Map?)?['handicap_mode'] == 'team_difference';

  String playerLabel(String name, Object? handicap) =>
      usesIndividualHandicaps ? '$name (Hcp ${handicap ?? "not set"})' : name;

  String entrant(String? id) {
    final entry = entries.where((e) => e['id'] == id).firstOrNull;
    if (entry == null) return 'Awaiting entrant';
    final name = entry['name'].toString();
    if (!usesIndividualHandicaps) return name;
    final members = (entry['handicap_members'] as List?) ?? const [];
    // Keep the saved playing order, including Lead / Skip order for pairs.
    final labels = name
        .split(' / ')
        .map((part) {
          final member = members
              .cast<Map>()
              .where(
                (m) =>
                    m['name'].toString().toLowerCase() ==
                    part.trim().toLowerCase(),
              )
              .firstOrNull;
          return members.isEmpty
              ? part
              : playerLabel(part, member?['individual_handicap']);
        })
        .join(' / ');
    return '$labels [Hcp ${entry['handicap'] ?? "not set"}]';
  }

  String? startingScores(CompetitionRow match) {
    if (!usesIndividualHandicaps) return null;
    final a = entries
        .where((e) => e['id'] == match['side_a_entry_id'])
        .firstOrNull?['handicap'];
    final b = entries
        .where((e) => e['id'] == match['side_b_entry_id'])
        .firstOrNull?['handicap'];
    if (a is! num || b is! num) return null;
    return 'Starting scores: ${b > a ? b - a : 0}–${a > b ? a - b : 0}';
  }

  String side(CompetitionRow match, String side) {
    final id = match['side_${side}_entry_id'] as String?;
    if (id != null) return entrant(id);
    if (match['side_${side}_kind'] == 'bye') return 'Bye';
    final source = matches
        .where((m) => m['id'] == match['side_${side}_source_id'])
        .firstOrNull;
    if (source == null) return 'Awaiting entrant';
    return 'Winner of ${reference(source)}';
  }

  String reference(CompetitionRow match) {
    final round = rounds.where((r) => r['id'] == match['round_id']).firstOrNull;
    return '${round?['name'] ?? 'Round'} ${match['match_number']}';
  }

  String status(CompetitionRow match, {DateTime? now}) {
    final label = switch (match['status']) {
      'bye' => 'Bye',
      'completed' =>
        match['result_kind'] == 'walkover' ? 'Walkover (W/O)' : 'Completed',
      'result_pending' => 'Result pending confirmation',
      _ => match['fixture_id'] != null ? 'Fixture arranged' : 'To be arranged',
    };
    final round = rounds.where((r) => r['id'] == match['round_id']).firstOrNull;
    final deadline = DateTime.tryParse('${round?['play_by']}');
    final today = now ?? DateTime.now();
    if (deadline != null &&
        deadline.isBefore(DateTime(today.year, today.month, today.day)) &&
        !['bye', 'completed'].contains(match['status'])) {
      return '$label · Overdue';
    }
    return label;
  }
}

class CompetitionRepository {
  final SupabaseClient client;
  CompetitionRepository(this.client);

  Future<void> update(
    String id,
    String name,
    String season,
    CompetitionRow settings, {
    String? fixtureTypeId,
  }) async {
    await client.rpc(
      'update_club_competition',
      params: {
        'p_competition_id': id,
        'p_name': name,
        'p_season': season,
        'p_settings': settings,
        if (fixtureTypeId != null) 'p_fixture_type_id': fixtureTypeId,
      },
    );
  }

  Future<List<CompetitionRow>> fixtureTypes(String clubId) async => await client
      .from('competition_types')
      .select('id,name')
      .eq('club_id', clubId)
      .order('name');

  Future<void> removeEntry(String id) async {
    await client.rpc('remove_competition_entry', params: {'p_entry_id': id});
  }

  Future<CompetitionRow> addPreliminary({
    required String matchId,
    required String entryId,
    required String sourceId,
    required List<String> members,
    required String? playBy,
    required String reason,
  }) async => Map<String, dynamic>.from(
    await client.rpc(
          'add_competition_preliminary',
          params: {
            'p_match_id': matchId,
            'p_entry_id': entryId,
            'p_expected_source_id': sourceId,
            'p_members': members,
            'p_play_by': playBy,
            'p_reason': reason,
          },
        )
        as Map,
  );

  Future<void> discardDraftDraw(String id) async {
    await client.rpc(
      'discard_unused_competition_draw',
      params: {'p_competition_id': id},
    );
  }

  Future<List<CompetitionRow>> list(String clubId) async => await client
      .from('club_competitions')
      .select()
      .eq('club_id', clubId)
      .order('season', ascending: false)
      .order('name');

  Future<List<CompetitionRow>> myEntries(
    String memberId,
    List<String> competitionIds,
  ) async {
    if (memberId.isEmpty || competitionIds.isEmpty) return [];
    return await client
        .from('competition_entry_members')
        .select('competition_id,entry_id,competition_entries(name)')
        .eq('member_profile_id', memberId)
        .inFilter('competition_id', competitionIds);
  }

  Future<CompetitionData> load(String clubId, String id) async {
    final competition = await client
        .from('club_competitions')
        .select(
          '*,fixture_type:competition_types!club_competitions_fixture_type_id_fkey(id,name,colour_scheme:fixture_colour_schemes(background_hex,foreground_hex))',
        )
        .eq('club_id', clubId)
        .eq('id', id)
        .single();
    final entries = await client
        .from('competition_entries')
        .select()
        .eq('competition_id', id)
        .order('entry_order');
    final rounds = await client
        .from('competition_rounds')
        .select()
        .eq('competition_id', id)
        .order('round_number');
    final matches = await client
        .from('competition_draw_matches')
        .select()
        .eq('competition_id', id)
        .order('match_number');
    final memberIds = <String>{};
    for (var offset = 0; ; offset += 500) {
      final page = await client
          .from('competition_entry_members')
          .select(
            (competition['settings'] as Map?)?['handicap_mode'] ==
                    'team_difference'
                ? 'member_profile_id,entry_id,individual_handicap,member:member_profiles(first_name,last_name)'
                : 'member_profile_id',
          )
          .eq('competition_id', id)
          .order('member_profile_id')
          .range(offset, offset + 499);
      memberIds.addAll(page.map((m) => m['member_profile_id'].toString()));
      for (final member in page) {
        final profile = member['member'] as Map?;
        if (profile == null) continue;
        final entry = entries
            .where((e) => e['id'] == member['entry_id'])
            .firstOrNull;
        if (entry == null) continue;
        (entry['handicap_members'] ??= <Map<String, dynamic>>[]).add({
          'name': '${profile['first_name'] ?? ''} ${profile['last_name'] ?? ''}'
              .trim(),
          'individual_handicap': member['individual_handicap'],
        });
      }
      if (page.length < 500) break;
    }
    return CompetitionData(competition, entries, rounds, matches, memberIds);
  }

  Future<int> addSingles(String id, List<String> members) async =>
      (await client.rpc(
            'add_competition_singles',
            params: {'p_competition_id': id, 'p_members': members},
          ))
          as int;

  Future<int> addTeams(String id, List<String> members) async =>
      (await client.rpc(
            'add_competition_teams',
            params: {'p_competition_id': id, 'p_members': members},
          ))
          as int;

  Future<void> setPaid(String entryId, bool paid) async {
    await client.rpc(
      'update_competition_entry_options',
      params: {'p_entry_id': entryId, 'p_paid': paid},
    );
  }

  Future<void> setHandicap(String entryId, num? handicap) async {
    await client.rpc(
      'update_competition_entry_options',
      params: {
        'p_entry_id': entryId,
        'p_handicap': handicap,
        'p_set_handicap': true,
      },
    );
  }

  Future<List<CompetitionRow>> entryHandicaps(
    String entryId,
  ) async => await client
      .from('competition_entry_members')
      .select(
        'member_profile_id,individual_handicap,member:member_profiles(first_name,last_name)',
      )
      .eq('entry_id', entryId);

  Future<void> setMemberHandicaps(
    String entryId,
    Map<String, int> values,
  ) async {
    await client.rpc(
      'set_competition_member_handicaps',
      params: {'p_entry_id': entryId, 'p_handicaps': values},
    );
  }

  Future<String> create(
    String clubId,
    String name,
    String season,
    CompetitionRow settings, {
    String? fixtureTypeId,
  }) async => (await client.rpc(
    'create_club_competition',
    params: {
      'p_club_id': clubId,
      'p_name': name,
      'p_season': season,
      'p_settings': settings,
      if (fixtureTypeId != null) 'p_fixture_type_id': fixtureTypeId,
    },
  )).toString();

  Future<void> addEntry(
    String id,
    String name,
    List<String> members,
    String payment,
    num? handicap,
  ) async {
    await client.rpc(
      'add_competition_entry',
      params: {
        'p_competition_id': id,
        'p_name': name,
        'p_members': members,
        'p_payment': payment,
        'p_handicap': handicap,
      },
    );
  }

  Future<void> build(String id, List<String> order) async {
    await client.rpc(
      'build_competition_draw',
      params: {'p_competition_id': id, 'p_entry_order': order},
    );
  }

  Future<void> publish(String id) async {
    await client.rpc(
      'publish_club_competition',
      params: {'p_competition_id': id},
    );
  }

  Future<void> updateRound(
    String id,
    String? deadline,
    CompetitionRow overrides,
  ) async {
    await client.rpc(
      'update_competition_round',
      params: {
        'p_round_id': id,
        'p_play_by': deadline,
        'p_rule_overrides': overrides,
      },
    );
  }

  Future<CompetitionRow?> walkoverAudit(String matchId) async => await client
      .from('competition_walkover_events')
      .select('reason,note,recorded_at')
      .eq('match_id', matchId)
      .maybeSingle();

  Future<bool> publicationEnabled(String clubId) async =>
      await client.rpc(
        'competition_release_status',
        params: {'p_club_id': clubId},
      ) ==
      true;

  Future<void> awardWalkover(
    CompetitionRow match,
    String winner,
    String reason,
    String note,
  ) async {
    await client.rpc(
      'award_competition_walkover',
      params: {
        'p_match_id': match['id'],
        'p_winner_entry_id': winner,
        'p_reason': reason,
        'p_note': note,
        'p_expected_side_a': match['side_a_entry_id'],
        'p_expected_side_b': match['side_b_entry_id'],
      },
    );
  }

  Future<void> result(
    String id,
    int scoreA,
    int scoreB,
    String winner, {
    bool confirm = false,
  }) async {
    await client.rpc(
      'record_competition_result',
      params: {
        'p_match_id': id,
        'p_score_a': scoreA,
        'p_score_b': scoreB,
        'p_winner_entry_id': winner,
        'p_confirm': confirm,
      },
    );
  }
}
