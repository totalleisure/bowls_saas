List<Map<String, dynamic>> buildConfirmedTeamMembers(
  Iterable<Map<String, dynamic>> selected,
) {
  return selected
      .where((row) {
        final role = (row['role'] ?? '').toString().toLowerCase();
        return row['is_selected'] == true &&
            (role == 'player' || role == 'reserve');
      })
      .map(
        (row) => {
          'member_profile_id': row['member_profile_id']?.toString(),
          'role': (row['role'] ?? '').toString().toLowerCase(),
          'is_selected': true,
        },
      )
      .toList();
}

void stageSelectedMemberRoleChange({
  required List<Map<String, dynamic>> selected,
  required Map<String, Map<int, Map<String, dynamic>>> assignmentsByRink,
  required String memberProfileId,
  required String newRole,
}) {
  final normalizedRole = newRole.toLowerCase().trim();

  for (final row in selected) {
    if (row['member_profile_id']?.toString() == memberProfileId) {
      row['role'] = normalizedRole;
      row['is_selected'] = true;
      break;
    }
  }

  if (normalizedRole == 'reserve') {
    for (final byPosition in assignmentsByRink.values) {
      byPosition.removeWhere(
        (_, row) => row['member_profile_id']?.toString() == memberProfileId,
      );
    }
    assignmentsByRink.removeWhere((_, byPosition) => byPosition.isEmpty);
  }
}

List<Map<String, dynamic>> buildConfirmedTeamRinks(
  Iterable<Map<String, dynamic>> rinks,
) {
  final result = rinks.map((r) => <String, dynamic>{
    'id': r['id'],
    'fixture_rink_no': r['fixture_rink_no'],
    'format': r['format'],
    'players_per_rink': r['players_per_rink'],
    'home_rink_label': (r['home_rink_label']?.toString().trim() ?? '').isEmpty
        ? null : r['home_rink_label'].toString().trim(),
  }).toList();
  result.sort((a, b) => a['id'].toString().compareTo(b['id'].toString()));
  return result;
}

/// Edit the local composition only. Removed slots remain selected/unpositioned.
void stageTeamStructureChange({
  required List<Map<String, dynamic>> rinks,
  required Map<String, Map<int, Map<String, dynamic>>> assignmentsByRink,
  required String rinkId,
  required String action,
  required String format,
  String? homeRinkLabel,
}) {
  const sizes = {'singles': 1, 'pairs': 2, 'aussie_pairs': 2, 'triples': 3, 'rinks': 4, 'fours': 4};
  final size = sizes[format];
  final index = rinks.indexWhere((r) => r['id'] == rinkId);
  if (!['add', 'update', 'delete'].contains(action) ||
      (action != 'delete' && size == null) ||
      (action != 'add' && index < 0) || (action == 'add' && index >= 0)) {
    throw StateError('Invalid team setup.');
  }
  if (action == 'delete' && rinks.length <= 1) {
    throw StateError('Keep at least one team.');
  }
  final physical = homeRinkLabel?.trim();
  if (action != 'delete' && physical != null && physical.isNotEmpty &&
      rinks.any((r) => r['id'] != rinkId && r['home_rink_label'] == physical)) {
    throw StateError('That physical rink is already assigned to another team.');
  }
  if (action == 'delete') {
    rinks.removeAt(index);
    assignmentsByRink.remove(rinkId);
    for (var i = 0; i < rinks.length; i++) {
      rinks[i]['fixture_rink_no'] = i + 1;
    }
    return;
  }
  if (action == 'add') {
    rinks.add({'id': rinkId, 'fixture_rink_no': rinks.length + 1,
      'format': format, 'players_per_rink': size, 'home_rink_label': physical});
    return;
  }
  final oldSize = (rinks[index]['players_per_rink'] as num).toInt();
  if (oldSize != size) {
    final old = assignmentsByRink[rinkId] ?? <int, Map<String, dynamic>>{};
    final next = <int, Map<String, dynamic>>{};
    // Retain lead and skip, then fit existing middle positions. The admin
    // can override this arrangement before the single confirmation.
    if (old[1] != null) next[1] = old[1]!;
    if (oldSize > 1 && size! > 1 && old[oldSize] != null) next[size] = old[oldSize]!;
    final middle = (oldSize - 2).clamp(0, 2) < (size! - 2).clamp(0, 2)
        ? (oldSize - 2).clamp(0, 2) : (size - 2).clamp(0, 2);
    for (var i = 1; i <= middle; i++) {
      final source = size < oldSize ? oldSize - middle + i - 1 : i + 1;
      if (old[source] != null) next[i + 1] = old[source]!;
    }
    assignmentsByRink[rinkId] = next;
  }
  rinks[index] = {...rinks[index], 'format': format,
    'players_per_rink': size, 'home_rink_label': physical};
}

/// Only previously positioned players require resolution; existing pool players
/// may legitimately remain unallocated.
List<Map<String, dynamic>> unresolvedDisplacedPlayers({
  required Set<String> originallyPositioned,
  required Iterable<Map<String, dynamic>> selected,
  required Iterable<Map<String, dynamic>> assignments,
}) {
  final positioned = assignments.map((a) => a['member_profile_id']?.toString()).toSet();
  return selected.where((m) => m['is_selected'] == true &&
      m['role'] == 'player' && originallyPositioned.contains(m['member_profile_id']?.toString()) &&
      !positioned.contains(m['member_profile_id']?.toString())).toList();
}

class TeamChangeReview {
  final List<String> teams;
  final List<String> players;
  final int recipients;
  const TeamChangeReview(this.teams, this.players, this.recipients);
}

TeamChangeReview buildTeamChangeReview({
  required Map<String, dynamic> before,
  required Map<String, dynamic> after,
  required Map<String, String> names,
}) {
  Map<String, Map<String, dynamic>> indexed(String key, String id, Map<String, dynamic> source) => {
    for (final row in (source[key] as List? ?? [])) row[id].toString(): Map<String, dynamic>.from(row as Map),
  };
  final oldTeams = indexed('rinks', 'id', before);
  final teams = indexed('rinks', 'id', after);
  final oldMembers = indexed('members', 'member_profile_id', before);
  final members = indexed('members', 'member_profile_id', after);
  final oldPositions = indexed('assignments', 'member_profile_id', before);
  final positions = indexed('assignments', 'member_profile_id', after);
  final teamLines = <String>[];
  String setup(Map<String, dynamic> t) => '${t['format']} (${t['players_per_rink']} players), '
      '${(t['home_rink_label'] ?? '').toString().isEmpty ? 'rink not assigned' : t['home_rink_label']}';
  for (final entry in oldTeams.entries) {
    if (!teams.containsKey(entry.key)) teamLines.add('Team ${entry.value['fixture_rink_no']} withdrawn');
  }
  for (final entry in teams.entries) {
    final old = oldTeams[entry.key];
    final t = entry.value;
    if (old == null) {
      teamLines.add('Team ${t['fixture_rink_no']} added: ${setup(t)}');
    } else if (['fixture_rink_no', 'format', 'players_per_rink', 'home_rink_label'].any((key) => old[key] != t[key])) {
      teamLines.add('Team ${old['fixture_rink_no']}: ${setup(old)} → '
          '${old['fixture_rink_no'] != t['fixture_rink_no'] ? 'Team ${t['fixture_rink_no']}, ' : ''}${setup(t)}');
    }
  }
  final playerLines = <String>[];
  var recipients = 0;
  for (final id in {...oldMembers.keys, ...members.keys}) {
    final old = oldMembers[id];
    final member = members[id];
    final previous = oldPositions[id];
    final position = positions[id];
    final wasPositioned = old?['role'] == 'player' && previous != null;
    final isPositioned = member?['role'] == 'player' && position != null;
    final withdrawn = wasPositioned && !teams.containsKey(previous['fixture_rink_id'].toString());
    final removed = old != null && member == null;
    final newReserve = member?['role'] == 'reserve' && old?['role'] != 'reserve';
    final newlyPositioned = isPositioned && !wasPositioned;
    final moved = previous?['fixture_rink_id'] != position?['fixture_rink_id'] || previous?['position'] != position?['position'];
    if (!withdrawn && !removed && !newReserve && !newlyPositioned && !moved && old?['role'] == member?['role']) continue;
    final sends = withdrawn || removed || newReserve || newlyPositioned;
    if (sends) recipients++;
    String outcome;
    if (member == null) {
      outcome = 'Removed from selection';
    } else if (member['role'] == 'reserve') {
      outcome = 'Reserve';
    } else if (position != null) {
      final team = teams[position['fixture_rink_id'].toString()]!;
      final number = position['position'];
      final size = team['players_per_rink'];
      final label = size == 1 ? 'Player' : number == 1 ? 'Lead' : number == size ? 'Skip' : number == 2 ? 'Two' : 'Three';
      outcome = 'Team ${team['fixture_rink_no']}, $label';
    } else {
      outcome = 'Player, awaiting a position';
    }
    final message = !sends ? 'No automatic message' :
        '${withdrawn ? 'Team withdrawn message' : 'Player-status message'}${member == null ? '' : ' + updated teamsheet'}';
    playerLines.add('${names[id] ?? 'Unnamed player'} → $outcome\n$message');
  }
  return TeamChangeReview(teamLines, playerLines, recipients);
}

/// Every selected player needs a position or an explicit reserve/removal choice.
List<Map<String, dynamic>> unpositionedSelectedPlayers({
  required Iterable<Map<String, dynamic>> selected,
  required Iterable<Map<String, dynamic>> assignments,
}) {
  final positioned = assignments.map((a) => a['member_profile_id']?.toString()).toSet();
  return selected.where((m) => m['is_selected'] == true && m['role'] == 'player' &&
    !positioned.contains(m['member_profile_id']?.toString())).toList();
}

Set<String> removeUnpositionedDecliners({required List<Map<String, dynamic>> selected,
  required Iterable<Map<String, dynamic>> assignments}) {
  final ids = unpositionedSelectedPlayers(selected: selected, assignments: assignments)
    .where((m) => m['acceptance'] == 'declined').map((m) => m['member_profile_id'].toString()).toSet();
  selected.removeWhere((m) => ids.contains(m['member_profile_id']));
  return ids;
}

void resolveUnpositionedPlayers({required List<Map<String, dynamic>> selected,
  required Set<String> memberIds, required bool makeReserves}) {
  if (!makeReserves) {
    selected.removeWhere((m) => memberIds.contains(m['member_profile_id']));
  } else {
    for (final member in selected) {
      if (memberIds.contains(member['member_profile_id'])) member['role'] = 'reserve';
    }
  }
}
