import 'permission_models.dart';

DashboardPermissions resolveDashboardPermissions({
  required bool isSuperuser,
  required bool isClubAdmin,
  required bool isSelector,
  required bool isFixtureCreator,
  required bool hasAnyFixtureLeadership,
}) {
  final isAdmin = isSuperuser || isClubAdmin;

  final isOperationalUser =
      isAdmin || isSelector || isFixtureCreator || hasAnyFixtureLeadership;

  return DashboardPermissions(
    showAdminSection: isAdmin,
    showOperationalActions: isOperationalUser,
    showManageTeamSection: isOperationalUser,
    showCreateFixture:
        isSuperuser || isClubAdmin || isSelector || isFixtureCreator,
  );
}
