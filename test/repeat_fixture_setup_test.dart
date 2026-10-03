import 'package:bowls_saas/features/fixtures/repeat_fixture_setup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ordinary repeats do not create selection data', () {
    final setup = buildRepeatFixtureSelectionSetup(
      isPreselect: false,
      rinkCount: 3,
      markerRequiredForTeam: (_) => true,
      markerRequestedForTeam: (_) => true,
    );

    expect(setup.createTeamSelection, isFalse);
    expect(setup.rinkAssignments, isEmpty);
    expect(setup.teamSelectionMembers, isEmpty);
  });

  test('Pre-Select repeats create blank slots without copying people', () {
    final setup = buildRepeatFixtureSelectionSetup(
      isPreselect: true,
      rinkCount: 3,
      markerRequiredForTeam: (teamNo) => teamNo == 1,
      markerRequestedForTeam: (teamNo) => teamNo == 2,
    );

    expect(setup.createTeamSelection, isTrue);
    expect(setup.teamSelectionMembers, isEmpty);
    expect(setup.rinkAssignments, [
      {
        'team_no': 1,
        'position': 201,
        'marker_required': true,
        'request_marker': false,
      },
      {
        'team_no': 2,
        'position': 201,
        'marker_required': false,
        'request_marker': true,
      },
    ]);
    for (final assignment in setup.rinkAssignments) {
      expect(assignment, isNot(contains('member_profile_id')));
      expect(assignment, isNot(contains('display_name')));
      expect(assignment, isNot(contains('acceptance')));
    }
  });
}
