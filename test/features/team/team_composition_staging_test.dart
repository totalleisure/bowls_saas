import 'package:bowls_saas/features/team/team_composition_staging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('positioned published player remains selected when made reserve', () {
    const memberId = 'wayne-symmetry';
    final selected = <Map<String, dynamic>>[
      {
        'member_profile_id': memberId,
        'role': 'player',
        'is_selected': true,
        'acceptance': 'accepted',
      },
    ];
    final assignments = <String, Map<int, Map<String, dynamic>>>{
      'rink-1': {
        3: {'member_profile_id': memberId},
      },
    };

    stageSelectedMemberRoleChange(
      selected: selected,
      assignmentsByRink: assignments,
      memberProfileId: memberId,
      newRole: 'reserve',
    );

    expect(selected.single['role'], 'reserve');
    expect(selected.single['is_selected'], isTrue);
    expect(assignments, isEmpty);
    expect(buildConfirmedTeamMembers(selected), [
      {'member_profile_id': memberId, 'role': 'reserve', 'is_selected': true},
    ]);
  });
}
