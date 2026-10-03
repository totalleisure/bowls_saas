import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/team/team_composition_staging.dart';

void main() {
  test('displaced players require resolution without blocking existing pool players', () {
    final members = <Map<String, dynamic>>[
      {'member_profile_id': 'displaced', 'role': 'player', 'is_selected': true},
      {'member_profile_id': 'pool', 'role': 'player', 'is_selected': true},
    ];
    List<Map<String, dynamic>> check([List<Map<String, dynamic>> assignments = const []]) =>
        unresolvedDisplacedPlayers(originallyPositioned: {'displaced'}, selected: members, assignments: assignments);
    expect(check().map((m) => m['member_profile_id']), ['displaced']);
    expect(check([{'member_profile_id': 'displaced'}]), isEmpty);
    members.first['role'] = 'reserve';
    expect(check(), isEmpty);
    members.first['role'] = 'player';
    members.first['is_selected'] = false;
    expect(check(), isEmpty);
  });

  test(
    'moving a player to reserve clears their position and preserves teammates',
    () {
      final members = <Map<String, dynamic>>[
        {'member_profile_id': 'alice', 'role': 'player', 'is_selected': true},
        {'member_profile_id': 'bob', 'role': 'player', 'is_selected': true},
      ];
      final positions = <String, Map<int, Map<String, dynamic>>>{
        'rink-a': {
          1: {'member_profile_id': 'alice'},
          2: {'member_profile_id': 'bob'},
        },
      };
      stageSelectedMemberRoleChange(
        selected: members,
        assignmentsByRink: positions,
        memberProfileId: 'alice',
        newRole: 'reserve',
      );
      expect(members.first['role'], 'reserve');
      expect(members.first['is_selected'], isTrue);
      expect(positions['rink-a']!.keys, [2]);
      expect(positions['rink-a']![2]!['member_profile_id'], 'bob');
      expect(buildConfirmedTeamMembers(members), [
        {'member_profile_id': 'alice', 'role': 'reserve', 'is_selected': true},
        {'member_profile_id': 'bob', 'role': 'player', 'is_selected': true},
      ]);
    },
  );

  test('returning a reserve to player does not resurrect an old position', () {
    final members = <Map<String, dynamic>>[
      {'member_profile_id': 'alice', 'role': 'player', 'is_selected': true},
    ];
    final positions = <String, Map<int, Map<String, dynamic>>>{
      'rink-a': {
        1: {'member_profile_id': 'alice'},
      },
    };
    for (final role in ['reserve', 'player']) {
      stageSelectedMemberRoleChange(
        selected: members,
        assignmentsByRink: positions,
        memberProfileId: 'alice',
        newRole: role,
      );
    }
    expect(members.single['role'], 'player');
    expect(positions, isEmpty);
    expect(
      buildConfirmedTeamMembers(members).single['member_profile_id'],
      'alice',
    );
  });

  test('confirmation excludes removed players and marker-only entries', () {
    final members = <Map<String, dynamic>>[
      {'member_profile_id': 'alice', 'role': 'player', 'is_selected': true},
      {'member_profile_id': 'bob', 'role': 'player', 'is_selected': false},
      {'member_profile_id': 'carol', 'role': 'marker', 'is_selected': true},
      {'member_profile_id': 'dave', 'role': 'reserve', 'is_selected': true},
    ];
    final confirmed = buildConfirmedTeamMembers(members);
    expect(confirmed.map((row) => row['member_profile_id']), ['alice', 'dave']);
    expect(members.length, 4);
    expect(members[1]['is_selected'], isFalse);
    expect(members[2]['role'], 'marker');
  });
}
