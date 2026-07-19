import 'permission_models.dart';

FixturePermissions resolveFixturePermissions({
  required ClubCapabilities clubCaps,
  required bool isSuperuser,
  required bool isClubAdmin,
  required FixtureResolvedRoles roles,
  required FixtureStateContext fixture,
}) {
  final isAdmin = isSuperuser || isClubAdmin;
  final elevatedTeamAccess = isAdmin || roles.hasOperationalLeadership;

  return FixturePermissions(
    canView: true,
    canCreateFixture: clubCaps.canCreateFixture,
    canEditFixture: isAdmin || elevatedTeamAccess,
    canDeleteFixture: clubCaps.canDeleteFixture,
    canPublishFixture: clubCaps.canPublishFixture || elevatedTeamAccess,
    canManageTeam: elevatedTeamAccess,
    canAssignCaptaincy: clubCaps.canAssignCaptaincy,
    canAssignRinks: elevatedTeamAccess,
    canRsvp: fixture.isRsvpFixture,
  );
}
