import 'permission_models.dart';

FixtureResolvedRoles resolveFixtureRoles({
  required String? fixtureCaptainId,
  required String? fixtureViceCaptainId,
  required String? teamCaptainId,
  required String? teamViceCaptainId,
  required String currentMemberId,
  required bool hasTeamAssigned,
}) {
  final isFixtureCaptain = fixtureCaptainId == currentMemberId;
  final isFixtureViceCaptain = fixtureViceCaptainId == currentMemberId;

  final isTeamCaptainForFixture =
      hasTeamAssigned && teamCaptainId == currentMemberId;

  final isTeamViceCaptainForFixture =
      hasTeamAssigned && teamViceCaptainId == currentMemberId;

  return FixtureResolvedRoles(
    isFixtureCaptain: isFixtureCaptain,
    isFixtureViceCaptain: isFixtureViceCaptain,
    isTeamCaptainForFixture: isTeamCaptainForFixture,
    isTeamViceCaptainForFixture: isTeamViceCaptainForFixture,
  );
}