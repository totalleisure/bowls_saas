import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  const canonical =
      'supabase/migrations/procedures/create_fixture_with_setup_v2.sql';
  const migration =
      'supabase/migrations/20260908213407_exclude_guest_fixture_creation.sql';

  String ordinaryMemberBranch(String sql) {
    final start = sql.indexOf('v_is_ordinary_member_booking :=');
    final end = sql.indexOf('\n\n  v_has_permission :=', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    return sql.substring(start, end);
  }

  test('ordinary member booking explicitly excludes Guest membership', () {
    final branch = ordinaryMemberBranch(source(canonical));

    expect(branch, contains('v_fixture_type_bookable_by_members = true'));
    expect(branch, contains('cm.is_active = true'));
    expect(branch, contains("lower(cm.role::text) <> 'guest'"));
  });

  test('admin selector and superuser authorization branches are unchanged', () {
    final sql = source(canonical);

    expect(sql, contains('where su.user_id = auth.uid()'));
    expect(sql, contains("lower(cm.role::text) in ('admin', 'selector')"));
    expect(
      sql,
      contains(
        'v_has_permission :=\n'
        '    v_is_superuser\n'
        '    or v_is_active_club_fixture_creator\n'
        '    or v_is_ordinary_member_booking;',
      ),
    );
  });

  test('inactive membership remains ineligible for member booking', () {
    final branch = ordinaryMemberBranch(source(canonical));

    expect(branch, contains('cm.is_active = true'));
  });

  test('new migration exactly matches the canonical function definition', () {
    expect(source(migration), source(canonical));
  });
}
