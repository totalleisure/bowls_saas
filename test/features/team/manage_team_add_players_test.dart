import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const path = 'lib/features/team/manage_team_screen.dart';

  String addPlayersMethod(String source) {
    final start = source.indexOf('Future<void> _addMembersFromPicker');
    final end = source.indexOf('\n  Future<void> _shareTeam', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    return source.substring(start, end);
  }

  test('Team fixtures use the atomic add-or-reactivate RPC', () {
    final method = addPlayersMethod(File(path).readAsStringSync());

    expect(method, contains("'add_team_members_to_pool'"));
    expect(method, contains("'p_team_id': teamId"));
    expect(method, contains("'p_member_profile_ids': selectedIds.toList()"));
    expect(method, isNot(contains("from('team_members').insert")));
  });

  test('existing active-player exclusion remains in place', () {
    final source = File(path).readAsStringSync();
    final start = source.indexOf(
      'Set<String> _memberIdsAlreadyInAddPeopleList',
    );
    final end = source.indexOf(
      '\n  Widget _buildIntegratedTeamAssignmentsSection',
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final exclusion = source.substring(start, end);
    expect(exclusion, contains('for (final r in _selected)'));
    expect(exclusion, contains('for (final r in _pool)'));
    expect(exclusion, contains('ids.add(id)'));
  });

  test('Team RSVP and general candidate pools exclude Guests centrally', () {
    final source = File(path).readAsStringSync();
    final start = source.indexOf('final eligibleParticipationRows');
    final end = source.indexOf('// 2) Load RSVP overlay', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final eligibility = source.substring(start, end);
    expect(eligibility, contains("'get_club_member_picker_list'"));
    expect(eligibility, contains("'p_fixture_id': fixtureId"));
    expect(eligibility, contains('eligibleParticipationIds.contains'));
  });
}
