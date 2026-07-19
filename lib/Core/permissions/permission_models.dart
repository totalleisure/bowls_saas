class ClubCapabilities {
  final bool canCreateFixture;
  final bool canAssignCaptaincy;
  final bool canPublishFixture;
  final bool canDeleteFixture;

  const ClubCapabilities({
    required this.canCreateFixture,
    required this.canAssignCaptaincy,
    required this.canPublishFixture,
    required this.canDeleteFixture,
  });
}

class FixtureResolvedRoles {
  final bool isFixtureCaptain;
  final bool isFixtureViceCaptain;
  final bool isTeamCaptainForFixture;
  final bool isTeamViceCaptainForFixture;

  const FixtureResolvedRoles({
    required this.isFixtureCaptain,
    required this.isFixtureViceCaptain,
    required this.isTeamCaptainForFixture,
    required this.isTeamViceCaptainForFixture,
  });

  bool get hasOperationalLeadership =>
      isFixtureCaptain ||
      isFixtureViceCaptain ||
      isTeamCaptainForFixture ||
      isTeamViceCaptainForFixture;
}

class FixtureStateContext {
  final bool isPublished;
  final bool isTeamFixture;
  final bool isRsvpFixture;
  final bool isRsvpOpen;
  final bool hasTeamAssigned;

  const FixtureStateContext({
    required this.isPublished,
    required this.isTeamFixture,
    required this.isRsvpFixture,
    required this.isRsvpOpen,
    required this.hasTeamAssigned,
  });
}

class FixturePermissions {
  final bool canView;
  final bool canCreateFixture;
  final bool canEditFixture;
  final bool canDeleteFixture;
  final bool canPublishFixture;
  final bool canManageTeam;
  final bool canAssignCaptaincy;
  final bool canAssignRinks;
  final bool canRsvp;

  const FixturePermissions({
    required this.canView,
    required this.canCreateFixture,
    required this.canEditFixture,
    required this.canDeleteFixture,
    required this.canPublishFixture,
    required this.canManageTeam,
    required this.canAssignCaptaincy,
    required this.canAssignRinks,
    required this.canRsvp,
  });
}

class DashboardPermissions {
  final bool showAdminSection;
  final bool showOperationalActions;
  final bool showManageTeamSection;
  final bool showCreateFixture;

  const DashboardPermissions({
    required this.showAdminSection,
    required this.showOperationalActions,
    required this.showManageTeamSection,
    required this.showCreateFixture,
  });
}
