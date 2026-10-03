class RepeatFixtureSelectionSetup {
  const RepeatFixtureSelectionSetup({
    required this.createTeamSelection,
    required this.rinkAssignments,
    required this.teamSelectionMembers,
  });

  final bool createTeamSelection;
  final List<Map<String, dynamic>> rinkAssignments;
  final List<Map<String, dynamic>> teamSelectionMembers;
}

/// Builds only the blank selection structure needed by a repeated fixture.
/// Person identities and selection responses are deliberately never accepted.
RepeatFixtureSelectionSetup buildRepeatFixtureSelectionSetup({
  required bool isPreselect,
  required int rinkCount,
  required bool Function(int teamNo) markerRequiredForTeam,
  required bool Function(int teamNo) markerRequestedForTeam,
}) {
  if (!isPreselect) {
    return const RepeatFixtureSelectionSetup(
      createTeamSelection: false,
      rinkAssignments: [],
      teamSelectionMembers: [],
    );
  }

  final markerSlots = <Map<String, dynamic>>[];
  for (var teamNo = 1; teamNo <= rinkCount; teamNo++) {
    final markerRequired = markerRequiredForTeam(teamNo);
    final requestMarker = markerRequestedForTeam(teamNo);
    if (markerRequired || requestMarker) {
      markerSlots.add({
        'team_no': teamNo,
        'position': 201,
        'marker_required': markerRequired,
        'request_marker': requestMarker,
      });
    }
  }

  return RepeatFixtureSelectionSetup(
    createTeamSelection: true,
    rinkAssignments: markerSlots,
    teamSelectionMembers: const [],
  );
}
