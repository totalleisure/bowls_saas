import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  const canonical =
      'supabase/migrations/procedures/add_team_members_to_pool.sql';
  const migration =
      'supabase/migrations/20260909141245_add_team_member_pool_members.sql';

  test('migration exactly matches the canonical procedure definition', () {
    expect(source(migration), source(canonical));
  });

  test('new players are inserted active', () {
    final sql = source(canonical);

    expect(
      sql,
      contains(
        'insert into public.team_members as existing_team_member (\n'
        '      team_id,\n'
        '      member_profile_id,\n'
        '      is_active\n'
        '    )',
      ),
    );
    expect(sql, contains('requested.member_profile_id,\n      true'));
  });

  test('Guest memberships cannot be added to a team pool', () {
    final sql = source(canonical);

    expect(sql, contains('membership.is_active = true'));
    expect(sql, contains("lower(membership.role::text) <> 'guest'"));
    expect(sql, contains('membership.club_id = team.club_id'));
  });

  test('inactive historical rows are reactivated without replacement', () {
    final sql = source(canonical);

    expect(sql, contains('on conflict (team_id, member_profile_id) do update'));
    expect(sql, contains('set is_active = true'));
    expect(sql, contains('where existing_team_member.is_active = false'));

    final updateClause = sql.substring(
      sql.indexOf('on conflict (team_id, member_profile_id) do update'),
      sql.indexOf('returning existing_team_member.*'),
    );
    expect(updateClause, isNot(contains('id =')));
    expect(updateClause, isNot(contains('created_at =')));
    expect(updateClause, isNot(contains('created_by =')));
  });

  test('already-active rows are idempotent', () {
    final sql = source(canonical);

    expect(sql, contains('where existing_team_member.is_active = false'));
    expect(
      sql,
      contains(
        'where team_member.team_id = p_team_id\n'
        '    and team_member.is_active = true',
      ),
    );
    expect(
      sql,
      contains('select activated.*\n  from activated_members activated'),
    );
  });

  test(
    'mixed batches are deduplicated and handled by one atomic statement',
    () {
      final sql = source(canonical);

      expect(sql, contains('select distinct requested.member_profile_id'));
      expect(sql, contains('from unnest(coalesce(p_member_profile_ids'));
      expect(
        RegExp(r'insert into public\.team_members').allMatches(sql),
        hasLength(1),
      );
    },
  );

  test('RPC is authenticated, security invoker and RLS-backed', () {
    final sql = source(canonical);

    expect(sql, contains('security invoker'));
    expect(sql, contains('set search_path = pg_catalog, public'));
    expect(sql, contains('from public, anon'));
    expect(sql, contains('to authenticated'));
    expect(sql, isNot(contains('security definer')));
  });
}
