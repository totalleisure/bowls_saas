import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

String normalise(String value) => value.replaceAll('\r\n', '\n').trimRight();

void main() {
  const procedureRoot = 'supabase/migrations/procedures';
  const migration =
      'supabase/migrations/20260909233020_harden_guest_participation_rpcs.sql';
  const canonicalFiles = <String>[
    '$procedureRoot/confirm_team_changes.sql',
    '$procedureRoot/set_team_selection_member_active.sql',
    '$procedureRoot/set_team_selection_member_role.sql',
    '$procedureRoot/save_preselect_fixture_state.sql',
    '$procedureRoot/save_fixture_rink_assignments.sql',
    '$procedureRoot/create_fixture_with_setup_v2.sql',
  ];

  String canonical(String name) => source('$procedureRoot/$name.sql');

  String before(String sql, String marker) {
    final end = sql.indexOf(marker);
    expect(end, greaterThan(0));
    return sql.substring(0, end);
  }

  test('migration exactly concatenates the six canonical definitions', () {
    final expected = canonicalFiles.map(source).map(normalise).join('\n\n');
    expect(normalise(source(migration)), expected);
  });

  test('team management actors require non-Guest membership or SuperUser', () {
    for (final name in <String>[
      'confirm_team_changes',
      'set_team_selection_member_active',
      'set_team_selection_member_role',
      'save_fixture_rink_assignments',
    ]) {
      final actorGuard = before(
        canonical(name),
        "raise exception 'You do not have permission to manage this fixture.'",
      );
      expect(actorGuard, contains('public.is_app_superuser()'), reason: name);
      expect(actorGuard, contains('cm.is_active = true'), reason: name);
      expect(
        actorGuard,
        contains("lower(cm.role::text) <> 'guest'"),
        reason: name,
      );
      expect(
        actorGuard,
        contains('public.can_manage_team_selection(v_fixture_id)'),
        reason: name,
      );
      expect(actorGuard, contains('captain_member_profile_id'), reason: name);
      expect(
        actorGuard,
        contains('vice_captain_member_profile_id'),
        reason: name,
      );
    }
  });

  test('Pre-Select actors preserve SuperUser and non-Guest manager roles', () {
    final actorGuard = before(
      canonical('save_preselect_fixture_state'),
      "raise exception 'You do not have permission to maintain this fixture.'",
    );
    expect(actorGuard, contains('v_is_superuser'));
    expect(actorGuard, contains('cm.is_active = true'));
    expect(actorGuard, contains("lower(cm.role::text) <> 'guest'"));
    expect(
      actorGuard,
      contains("lower(cm.role::text) in ('admin', 'selector')"),
    );
    expect(actorGuard, contains('v_captain_member_profile_id'));
    expect(actorGuard, contains('v_vice_captain_member_profile_id'));
  });

  test('confirm changes rejects Guest player and reserve targets', () {
    final sql = canonical('confirm_team_changes');
    final targetStart = sql.indexOf(
      "as m(member_profile_id uuid, role text, is_selected boolean)\n"
      '    where not exists (',
    );
    final targetEnd = sql.indexOf(
      "raise exception 'Target member",
      targetStart,
    );
    expect(targetStart, greaterThan(0));
    expect(targetEnd, greaterThan(targetStart));
    final targetGuard = sql.substring(targetStart, targetEnd);
    expect(targetGuard, contains('cm.is_active = true'));
    expect(targetGuard, contains("lower(cm.role::text) <> 'guest'"));
    expect(sql, contains("not in ('player', 'reserve')"));
  });

  test('activation validates non-Guest before idempotent activation', () {
    final sql = canonical('set_team_selection_member_active');
    final activeStart = sql.indexOf('if p_is_selected then');
    final inactiveStart = sql.indexOf(
      'if not found or not v_member.is_selected then',
      activeStart,
    );
    expect(activeStart, greaterThan(0));
    expect(inactiveStart, greaterThan(activeStart));
    final activation = sql.substring(activeStart, inactiveStart);
    expect(activation, contains('cm.is_active = true'));
    expect(activation, contains("lower(cm.role::text) <> 'guest'"));
    expect(
      activation.indexOf("lower(cm.role::text) <> 'guest'"),
      lessThan(activation.indexOf("'action', 'no_change'")),
    );
  });

  test(
    'historical Guest deactivation remains outside target eligibility guard',
    () {
      final sql = canonical('set_team_selection_member_active');
      final inactiveStart = sql.indexOf(
        'if not found or not v_member.is_selected then',
      );
      final inactiveBranch = sql.substring(inactiveStart);
      expect(
        inactiveBranch,
        contains(
          'update public.team_selection_members set is_selected = false',
        ),
      );
      expect(
        inactiveBranch,
        contains('delete from public.fixture_rink_assignments'),
      );
      expect(
        inactiveBranch,
        isNot(contains("lower(cm.role::text) <> 'guest'")),
      );
    },
  );

  test('active player or reserve role transitions reject Guest targets', () {
    final sql = canonical('set_team_selection_member_role');
    final targetGuard = before(sql, "if v_member.role::text = v_new_role then");
    expect(targetGuard, contains('cm.is_active = true'));
    expect(targetGuard, contains("lower(cm.role::text) <> 'guest'"));
    expect(sql, contains("v_new_role not in ('player', 'reserve')"));
  });

  test('Pre-Select member players opponents and markers reject Guests', () {
    final sql = canonical('save_preselect_fixture_state');
    final targetStart = sql.indexOf(
      '-- All known people must be active members of the fixture club.',
    );
    final targetEnd = sql.indexOf(
      '-- ENSURE THE FIXTURE HAS A TEAM SELECTION',
      targetStart,
    );
    expect(targetStart, greaterThan(0));
    expect(targetEnd, greaterThan(targetStart));
    final targetGuard = sql.substring(targetStart, targetEnd);
    expect(targetGuard, contains('d.member_profile_id is not null'));
    expect(targetGuard, contains('cm.is_active = true'));
    expect(targetGuard, contains("lower(cm.role::text) <> 'guest'"));
    expect(sql, contains('between 1 and v_players_per_rink'));
    expect(sql, contains('between 101 and (100 + v_players_per_rink)'));
    expect(sql, contains("then 'marker'"));
  });

  test('Pre-Select external opponent names remain unaffected', () {
    final sql = canonical('save_preselect_fixture_state');
    expect(sql, contains('display_name text'));
    expect(sql, contains("then 'opponent'"));
    expect(sql, contains('member_profile_id is null'));
  });

  test('rink assignment targets require active non-Guest membership', () {
    final sql = canonical('save_fixture_rink_assignments');
    final targetStart = sql.indexOf(
      'if exists (',
      sql.indexOf(
        "raise exception 'Assigned member is not active in the team selection.'",
      ),
    );
    final targetEnd = sql.indexOf(
      "raise exception 'Target member",
      targetStart,
    );
    expect(targetStart, greaterThan(0));
    expect(targetEnd, greaterThan(targetStart));
    final targetGuard = sql.substring(targetStart, targetEnd);
    expect(targetGuard, contains('cm.is_active = true'));
    expect(targetGuard, contains("lower(cm.role::text) <> 'guest'"));
  });

  test('complete-state saves still remove omitted historical Guests', () {
    final preselect = canonical('save_preselect_fixture_state');
    final rinkSave = canonical('save_fixture_rink_assignments');
    final confirm = canonical('confirm_team_changes');

    expect(preselect, contains('delete from public.fixture_rink_assignments'));
    expect(rinkSave, contains('delete from public.fixture_rink_assignments'));
    expect(
      confirm,
      contains(
        'update public.team_selection_members tsm\n  set is_selected = false',
      ),
    );
  });

  test('fixture creation rejects Guest leaders and participant targets', () {
    final sql = canonical('create_fixture_with_setup_v2');
    final targetStart = sql.indexOf(
      'if p_captain_member_profile_id is not null',
    );
    final targetSection = sql.substring(
      targetStart,
      sql.indexOf('if v_is_ordinary_member_booking then', targetStart),
    );
    expect(targetSection, contains('leader.member_profile_id'));
    expect(targetSection, contains("lower(cm.role::text) <> 'guest'"));
    expect(targetSection, contains("a.item->>'member_profile_id'"));
    expect(targetSection, contains("m.item->>'member_profile_id'"));
    expect(
      RegExp(
        "lower\\(cm\\.role::text\\) <> 'guest'",
      ).allMatches(targetSection).length,
      3,
    );
  });

  test(
    'fixture creation actor and ordinary Member semantics are preserved',
    () {
      final sql = canonical('create_fixture_with_setup_v2');
      final actorSection = sql.substring(
        sql.indexOf('select public.my_member_profile_id()'),
        sql.indexOf('if p_rinks_required < 0 then'),
      );
      expect(actorSection, contains('v_is_superuser'));
      expect(
        actorSection,
        contains("lower(cm.role::text) in ('admin', 'selector')"),
      );
      expect(actorSection, contains("lower(cm.role::text) <> 'guest'"));
      expect(actorSection, isNot(contains("lower(cm.role::text) = 'member'")));
    },
  );
}
