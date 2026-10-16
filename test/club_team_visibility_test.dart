import 'package:bowls_saas/features/clubs/club_access.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ClubAccess access(String role, {bool active = true, bool superuser = false}) =>
      ClubAccess(
        currentMemberId: 'member',
        isSuperuser: superuser,
        isClubAdmin: role == 'admin',
        isSelector: role == 'selector',
        membershipRole: role,
        hasActiveMembership: active,
      );

  test('ordinary active members can view teams without management rights', () {
    final member = access('member');
    expect(member.canViewTeams, isTrue);
    expect(member.canAdminManageFixtures, isFalse);
  });

  test('guests and inactive memberships do not gain team access', () {
    expect(access('guest').canViewTeams, isFalse);
    expect(access('member', active: false).canViewTeams, isFalse);
  });

  test('selectors, admins and superusers retain team access', () {
    expect(access('selector').canViewTeams, isTrue);
    expect(access('admin').canViewTeams, isTrue);
    expect(access('', active: false, superuser: true).canViewTeams, isTrue);
  });
}
