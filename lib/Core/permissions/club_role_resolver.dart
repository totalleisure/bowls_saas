import 'permission_models.dart';

ClubCapabilities resolveClubCapabilities({
  required bool isSuperuser,
  required bool isClubAdmin,
  required bool isSelector,
  required bool isFixtureCreator,
}) {
  final canCreateFixture =
      isSuperuser || isClubAdmin || isSelector || isFixtureCreator;

  return ClubCapabilities(
    canCreateFixture: canCreateFixture,
    canAssignCaptaincy:
        isSuperuser || isClubAdmin || isSelector || isFixtureCreator,
    canPublishFixture:
        isSuperuser || isClubAdmin || isSelector || isFixtureCreator,
    canDeleteFixture: isSuperuser || isClubAdmin,
  );
}