import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

String normalise(String value) => value.replaceAll('\r\n', '\n').trimRight();

void main() {
  const procedureRoot = 'supabase/migrations/procedures';
  const migration =
      'supabase/migrations/20260909234733_harden_guest_marker_and_mailing_list_participation.sql';
  const canonicalFiles = <String>[
    '$procedureRoot/queue_open_marker_request_communications.sql',
    '$procedureRoot/enforce_operational_mailing_list_member_eligibility.sql',
    '$procedureRoot/communications_health_check.sql',
    '$procedureRoot/communications_health_detail_v2.sql',
  ];

  test('migration exactly concatenates the four canonical definitions', () {
    final expected = canonicalFiles.map(source).map(normalise).join('\n\n');
    expect(normalise(source(migration)), expected);
  });

  test('marker request actor must be SuperUser or active non-Guest manager', () {
    final sql = source(canonicalFiles[0]);
    final guardEnd = sql.indexOf(
      "raise exception\n      'You do not have permission to send marker requests for this fixture.'",
    );
    expect(guardEnd, greaterThan(0));
    final guard = sql.substring(0, guardEnd);

    expect(guard, contains('from public.app_superusers su'));
    expect(guard, contains('su.user_id = auth.uid()'));
    expect(guard, contains('cm.is_active = true'));
    expect(guard, contains("lower(cm.role::text) <> 'guest'"));
    expect(guard, contains("lower(cm.role::text) in ('admin', 'selector')"));
    expect(guard, contains('f.captain_member_profile_id'));
    expect(guard, contains('f.vice_captain_member_profile_id'));
  });

  test('Guest is excluded from both marker recipient query paths', () {
    final sql = source(canonicalFiles[0]);

    expect(
      RegExp("lower\\(cm\\.role::text\\) <> 'guest'").allMatches(sql).length,
      3,
      reason: 'one actor guard plus count and insert recipient queries',
    );
    expect(
      RegExp(r'join public\.club_memberships cm').allMatches(sql).length,
      2,
      reason: 'the volunteer count and queue insertion recipient queries',
    );
  });

  test(
    'ordinary eligible marker recipients and deduplication remain intact',
    () {
      final sql = source(canonicalFiles[0]);

      expect(sql, contains('mlm.is_active = true'));
      expect(sql, contains('cm.is_active = true'));
      expect(sql, contains("lower(cm.role::text) <> 'guest'"));
      expect(sql, contains("existing.event_type = 'marker_request_opened'"));
      expect(
        sql,
        contains('existing.target_member_profile_id = mlm.member_profile_id'),
      );
      expect(
        sql,
        contains("existing.payload ->> 'marker_request_id' = mr.id::text"),
      );
    },
  );

  test('Guest self-subscription and reactivation remain blocked centrally', () {
    final sql = source('$procedureRoot/set_my_mailing_list_membership.sql');
    final branch = sql.indexOf('if coalesce(p_join, false) then');
    expect(branch, greaterThan(0));
    final eligibility = sql.substring(0, branch);

    expect(eligibility, contains('cm.is_active = true'));
    expect(eligibility, contains("lower(cm.role::text) <> 'guest'"));
  });

  test('table trigger blocks active Guest list membership from every writer', () {
    final sql = source(canonicalFiles[1]);

    expect(sql, contains('if coalesce(new.is_active, false)'));
    expect(sql, contains('cm.member_profile_id = new.member_profile_id'));
    expect(sql, contains('cm.is_active = true'));
    expect(sql, contains("lower(cm.role::text) <> 'guest'"));
    expect(
      sql,
      contains(
        'before insert or update of mailing_list_id, member_profile_id, is_active',
      ),
    );
  });

  test(
    'historical Guest list records can remain, deactivate, and be deleted',
    () {
      final sql = source(canonicalFiles[1]);

      expect(sql, isNot(contains('delete from public.mailing_list_members')));
      expect(sql, isNot(contains('update public.mailing_list_members')));
      expect(sql, isNot(contains('before delete')));
      expect(sql, contains('if coalesce(new.is_active, false)'));
    },
  );

  test(
    'admin direct upsert is guarded while historical delete remains usable',
    () {
      final dart = source(
        'lib/features/communications/mailing_list_members_screen.dart',
      );

      expect(dart, contains(".from('mailing_list_members')"));
      expect(dart, contains('.upsert('));
      expect(dart, contains('.delete()'));
    },
  );

  test('communications diagnostics use the same non-Guest recipient rule', () {
    for (final path in canonicalFiles.skip(2)) {
      final sql = source(path);
      expect(sql, contains('cm.is_active = true'), reason: path);
      expect(sql, contains("lower(cm.role::text) <> 'guest'"), reason: path);
    }
  });

  test('Stage 3 migration does not redefine Stage 2 participation RPCs', () {
    final sql = source(migration);

    for (final function in <String>[
      'confirm_team_changes',
      'set_team_selection_member_active',
      'set_team_selection_member_role',
      'save_preselect_fixture_state',
      'save_fixture_rink_assignments',
      'create_fixture_with_setup_v2',
    ]) {
      expect(
        sql,
        isNot(contains('function public.$function(')),
        reason: function,
      );
    }
  });
}
