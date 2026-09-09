import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  const migration =
      'supabase/migrations/20260909154718_stage_one_guest_database_authorization.sql';

  late String sql;

  setUpAll(() {
    sql = source(migration).toLowerCase();
  });

  String policy(String name, {String? nextPolicy}) {
    final start = sql.indexOf('create policy "$name"');
    expect(start, greaterThanOrEqualTo(0));
    final end = nextPolicy == null
        ? sql.length
        : sql.indexOf('create policy "$nextPolicy"', start + 1);
    expect(end, greaterThan(start));
    return sql.substring(start, end);
  }

  test('direct rink-assignment writes are closed at the table boundary', () {
    expect(
      sql,
      contains(
        'alter table public.fixture_rink_assignments enable row level security',
      ),
    );
    expect(
      sql,
      contains('revoke all on table public.fixture_rink_assignments from anon'),
    );
    expect(
      sql,
      contains(
        'revoke all on table public.fixture_rink_assignments from authenticated',
      ),
    );
    expect(
      sql,
      contains(
        'grant select on table public.fixture_rink_assignments to authenticated',
      ),
    );
    expect(
      sql,
      isNot(contains('grant insert on table public.fixture_rink_assignments')),
    );
  });

  test('authorised club reads include Guest and historical assignments', () {
    final readPolicy = policy(
      'fixture_rink_assignments select (club members)',
      nextPolicy: 'members can create member bookable fixtures',
    );
    expect(readPolicy, contains('public.is_app_superuser()'));
    expect(readPolicy, contains('cm.is_active = true'));
    expect(readPolicy, isNot(contains("cm.role::text) <> 'guest'")));
    expect(readPolicy, isNot(contains('fixture_rink_assignments.is_active')));
  });

  test('legitimate secured rink-assignment RPC remains available', () {
    final rpc = source(
      'supabase/migrations/procedures/save_fixture_rink_assignments.sql',
    ).toLowerCase();
    expect(rpc, contains('security definer'));
    expect(
      rpc,
      contains(
        'grant execute on function public.save_fixture_rink_assignments',
      ),
    );
    expect(sql, isNot(contains('save_fixture_rink_assignments(')));
  });

  test('direct member-bookable fixture insert excludes Guest only', () {
    final fixturePolicy = policy(
      'members can create member bookable fixtures',
      nextPolicy: 'rsvps insert as admin or superuser',
    );
    expect(fixturePolicy, contains('cm.is_active = true'));
    expect(fixturePolicy, contains("lower(cm.role::text) <> 'guest'"));
    expect(fixturePolicy, contains('ct.bookable_by_members = true'));
    expect(fixturePolicy, contains('ct.is_active = true'));
    expect(
      fixturePolicy,
      contains('captain_member_profile_id = public.my_member_profile_id()'),
    );
    expect(
      sql,
      isNot(contains('drop policy if exists "fixtures write (admins)"')),
    );
  });

  test('Guest own RSVP insert and update are rejected', () {
    final insertPolicy = policy(
      'rsvps write own',
      nextPolicy: 'rsvps update own',
    );
    final updatePolicy = policy('rsvps update own');

    for (final ownPolicy in [insertPolicy, updatePolicy]) {
      expect(
        ownPolicy,
        contains('member_profile_id = public.my_member_profile_id()'),
      );
      expect(ownPolicy, contains('cm.is_active = true'));
      expect(ownPolicy, contains("lower(cm.role::text) <> 'guest'"));
    }
    expect(updatePolicy, contains('using ('));
    expect(updatePolicy, contains('with check ('));
  });

  test('ordinary Member RSVP insert and update semantics are preserved', () {
    final insertPolicy = policy(
      'rsvps write own',
      nextPolicy: 'rsvps update own',
    );
    final updatePolicy = policy('rsvps update own');
    expect(insertPolicy, isNot(contains("cm.role::text) = 'member'")));
    expect(updatePolicy, isNot(contains("cm.role::text) = 'member'")));
  });

  test('admin cannot create or reactivate an RSVP for a Guest', () {
    final adminPolicy = policy(
      'rsvps insert as admin or superuser',
      nextPolicy: 'rsvps write own',
    );
    expect(adminPolicy, contains("actor_cm.role = 'admin'::public.club_role"));
    expect(adminPolicy, contains('target_cm.is_active = true'));
    expect(adminPolicy, contains("lower(target_cm.role::text) <> 'guest'"));
  });

  test(
    'historical Guest RSVP reads and existing cleanup policies are retained',
    () {
      expect(sql, isNot(contains('drop policy if exists "rsvps select')));
      expect(sql, isNot(contains('delete from public.fixture_rsvps')));
      expect(sql, isNot(contains('drop policy if exists "rsvps delete')));
    },
  );
}
