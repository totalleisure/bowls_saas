import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String normalise(String value) => value.replaceAll('\r\n', '\n').trimRight();

bool canManageFixture({
  required bool activeMembership,
  required String role,
  bool isNamedCaptain = false,
  bool isNamedViceCaptain = false,
  bool isSuperuser = false,
}) {
  if (isSuperuser) return true;
  if (!activeMembership || role.toLowerCase() == 'guest') return false;
  return const {'admin', 'selector'}.contains(role.toLowerCase()) ||
      isNamedCaptain ||
      isNamedViceCaptain;
}

void main() {
  const root = 'supabase/migrations/procedures';
  const migration =
      'supabase/migrations/20260910022400_revoke_historical_guest_fixture_authority.sql';
  const canonicalFiles = <String>[
    '$root/can_manage_fixture.sql',
    '$root/can_manage_team_selection.sql',
    '$root/fixture_rinks_write_policies.sql',
    '$root/swap_fixture_rink_labels.sql',
    '$root/guest_fixture_write_policies.sql',
    '$root/cancel_fixture_safe.sql',
    '$root/queue_fixture_moved_notifications.sql',
    '$root/queue_fixture_opponent_changed_notifications.sql',
    '$root/publish_team_selection_safe.sql',
    '$root/queue_team_publication_communications.sql',
    '$root/process_fixture_post_publish_changes.sql',
    '$root/reconcile_preselect_communications.sql',
    '$root/enforce_non_guest_fixture_notification_actor.sql',
  ];

  test('migration exactly concatenates the canonical definitions', () {
    final expected = canonicalFiles.map(source).map(normalise).join('\n\n');
    expect(normalise(source(migration)), expected);
  });

  test('active Member captain keeps fixture write authority', () {
    expect(
      canManageFixture(
        activeMembership: true,
        role: 'member',
        isNamedCaptain: true,
      ),
      isTrue,
    );
  });

  test('historical Guest captain and vice-captain cannot write', () {
    expect(
      canManageFixture(
        activeMembership: true,
        role: 'guest',
        isNamedCaptain: true,
      ),
      isFalse,
    );
    expect(
      canManageFixture(
        activeMembership: true,
        role: 'guest',
        isNamedViceCaptain: true,
      ),
      isFalse,
    );
  });

  test('Admin and SuperUser behaviour remains available', () {
    expect(canManageFixture(activeMembership: true, role: 'admin'), isTrue);
    expect(
      canManageFixture(
        activeMembership: false,
        role: 'guest',
        isSuperuser: true,
      ),
      isTrue,
    );
  });

  test(
    'central database helper requires current active non-Guest membership',
    () {
      final sql = source('$root/can_manage_fixture.sql');
      expect(sql, contains('cm.is_active = true'));
      expect(sql, contains("lower(cm.role::text) <> 'guest'"));
      expect(
        sql,
        contains('f.captain_member_profile_id = cm.member_profile_id'),
      );
      expect(
        sql,
        contains('f.vice_captain_member_profile_id = cm.member_profile_id'),
      );
      expect(sql, contains('from public.app_superusers su'));
    },
  );

  test('fixture_rinks direct writes require the central helper', () {
    final sql = source('$root/fixture_rinks_write_policies.sql');
    expect(
      sql,
      contains('alter table public.fixture_rinks enable row level security'),
    );
    expect(
      RegExp(
        r'public\.can_manage_fixture\(fixture_id\)',
      ).allMatches(sql).length,
      4,
    );
    expect(sql, contains('fixture_rinks select (club members)'));
  });

  test('Guest cannot invoke the SECURITY DEFINER rink swap directly', () {
    final sql = source('$root/swap_fixture_rink_labels.sql');
    expect(sql, contains('public.can_manage_fixture(a_fixture_id)'));
    expect(sql, contains('public.can_manage_fixture(b_fixture_id)'));
    expect(
      sql,
      contains('You do not have permission to move these rink bookings.'),
    );
    expect(sql, contains('from public, anon'));
  });

  test('all captain-derived mutation RPCs use the central helper', () {
    for (final name in <String>[
      'cancel_fixture_safe',
      'queue_fixture_moved_notifications',
      'queue_fixture_opponent_changed_notifications',
      'process_fixture_post_publish_changes',
      'reconcile_preselect_communications',
    ]) {
      expect(
        source('$root/$name.sql'),
        contains('public.can_manage_fixture(p_fixture_id)'),
        reason: name,
      );
    }

    for (final name in <String>[
      'publish_team_selection_safe',
      'queue_team_publication_communications',
    ]) {
      expect(
        source('$root/$name.sql'),
        contains('public.can_manage_team_selection(p_fixture_id)'),
        reason: '$name must preserve the existing team-selection role model',
      );
    }
  });

  test('Guest historical team response cannot be reactivated or changed', () {
    final sql = source('$root/guest_fixture_write_policies.sql');
    expect(sql, contains('team_selection_members confirm own'));
    expect(
      RegExp("lower\\(cm\\.role::text\\) <> 'guest'").allMatches(sql).length,
      2,
    );
  });

  test(
    'fixture communications reject a current Guest actor at table boundary',
    () {
      final sql = source(
        '$root/enforce_non_guest_fixture_notification_actor.sql',
      );
      expect(sql, contains('before insert'));
      expect(sql, contains('new.fixture_id is not null'));
      expect(sql, contains('cm.is_active = true'));
      expect(sql, contains("lower(cm.role::text) <> 'guest'"));
    },
  );

  test(
    'Flutter keeps historical captain display but gates every write capability',
    () {
      final access = source('lib/features/clubs/club_access.dart');
      final details = source('lib/features/fixtures/fixture_details_page.dart');

      expect(access, contains('bool get canWrite'));
      expect(access, contains("membershipRole != 'guest'"));
      expect(details, contains('captainId == _currentMemberId'));
      expect(
        details,
        isNot(contains("captainId == _currentMemberId && !_isGuest")),
      );
      expect(
        details,
        contains('final canManageTeam =\n          access.canWrite &&'),
      );
      expect(
        details,
        contains(
          'final canRespondToTeamSelection = _canWrite && myTeamSelection != null;',
        ),
      );
      expect(details, contains('bool get _canEditFixtureOperationalDetails'));
      expect(details, contains('return _canWrite &&'));
    },
  );
}
