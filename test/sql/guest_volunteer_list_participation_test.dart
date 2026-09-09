import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  const canonical =
      'supabase/migrations/procedures/set_my_mailing_list_membership.sql';
  const migration =
      'supabase/migrations/20260909145115_exclude_guests_from_volunteer_list_participation.sql';

  test('migration exactly matches the canonical procedure definition', () {
    expect(source(migration), source(canonical));
  });

  test('Guest cannot join or leave a mailing or volunteer list', () {
    final sql = source(canonical);
    final eligibilityCheckEnd = sql.indexOf('if coalesce(p_join, false) then');

    expect(eligibilityCheckEnd, greaterThan(0));
    final eligibilityCheck = sql.substring(0, eligibilityCheckEnd);
    expect(eligibilityCheck, contains('cm.is_active = true'));
    expect(eligibilityCheck, contains("lower(cm.role::text) <> 'guest'"));
    expect(
      eligibilityCheck,
      contains('You are not eligible to join mailing or volunteer lists.'),
    );
  });
}
