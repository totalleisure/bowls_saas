import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/team/team_composition_staging.dart';

void main() {
  late List<Map<String, dynamic>> rinks;
  late Map<String, Map<int, Map<String, dynamic>>> assignments;
  setUp(() {
    rinks = [
      {'id': 'a', 'fixture_rink_no': 1, 'format': 'triples', 'players_per_rink': 3, 'home_rink_label': 'R4'},
      {'id': 'b', 'fixture_rink_no': 2, 'format': 'pairs', 'players_per_rink': 2, 'home_rink_label': 'R1'},
    ];
    assignments = {'a': {1: {'member_profile_id': 'lead'}, 2: {'member_profile_id': 'two'}, 3: {'member_profile_id': 'skip'}}};
  });
  void change(String action, String id, String format, [String? label]) => stageTeamStructureChange(
    rinks: rinks, assignmentsByRink: assignments, rinkId: id,
    action: action, format: format, homeRinkLabel: label);

  test('reduction preserves lead and skip for review without mutating members', () {
    final selected = ['lead', 'two', 'skip'].map((id) => <String, dynamic>{
      'member_profile_id': id, 'is_selected': true, 'role': 'player',
    }).toList();
    change('update', 'a', 'pairs', 'R4');
    expect(assignments['a']![2]!['member_profile_id'], 'skip');
    expect(assignments['a']!.length, 2);
    expect(buildConfirmedTeamMembers(selected).length, 3);
    stageSelectedMemberRoleChange(selected: selected, assignmentsByRink: assignments,
      memberProfileId: 'two', newRole: 'reserve');
    expect(selected[1]['role'], 'reserve');
    // Admin can instead retain Two and make the previous Skip the reserve.
    stageSelectedMemberRoleChange(selected: selected, assignmentsByRink: assignments,
      memberProfileId: 'two', newRole: 'player');
    stageSelectedMemberRoleChange(selected: selected, assignmentsByRink: assignments,
      memberProfileId: 'skip', newRole: 'reserve');
    assignments['a']![2] = {'member_profile_id': 'two'};
    expect(assignments['a']![2]!['member_profile_id'], 'two');
    expect(selected[2]['role'], 'reserve');
  });
  test('expansion retains skip and leaves middle vacant', () {
    assignments['b'] = {1: {'member_profile_id': 'lead'}, 2: {'member_profile_id': 'skip'}};
    change('update', 'b', 'triples', 'R1');
    expect(assignments['b']!.keys, [1, 3]);
    expect(assignments['b']![3]!['member_profile_id'], 'skip');
  });
  test('baseline snapshot survives local edits for discard and conflict detection', () {
    final baseline = buildConfirmedTeamRinks(rinks);
    change('update', 'a', 'pairs', 'R3');
    expect(baseline.first['format'], 'triples');
    expect(baseline.first['home_rink_label'], 'R4');
    expect(buildConfirmedTeamRinks(rinks), isNot(baseline));
  });
  test('add then delete draft team restores structure', () {
    final before = buildConfirmedTeamRinks(rinks);
    change('add', 'new', 'singles', 'R6');
    expect(rinks.last['fixture_rink_no'], 3);
    change('delete', 'new', 'singles');
    expect(buildConfirmedTeamRinks(rinks), before);
  });
  test('deleted team releases positions and renumbers remaining team', () {
    change('delete', 'a', 'triples');
    expect(assignments.containsKey('a'), false);
    expect(rinks.single['fixture_rink_no'], 1);
    expect(rinks.single['id'], 'b');
    expect(() => change('delete', 'b', 'pairs'), throwsStateError);
    expect(rinks.length, 1);
  });
  test('duplicate physical rink rejected before local mutation', () {
    final before = buildConfirmedTeamRinks(rinks);
    expect(() => change('update', 'a', 'pairs', 'R1'), throwsStateError);
    expect(buildConfirmedTeamRinks(rinks), before);
    expect(assignments['a']!.length, 3);
  });
}
