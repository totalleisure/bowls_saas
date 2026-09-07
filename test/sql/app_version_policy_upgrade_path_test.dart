import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const migration =
      'supabase/migrations/20260907000924_add_platform_update_destinations.sql';

  test('upgrade destination migration is nullable and non-enforcing', () {
    final sql = File(migration).readAsStringSync().toLowerCase();

    expect(sql, contains('add column if not exists update_url text'));
    expect(sql, contains('add column if not exists update_message text'));
    expect(sql, contains("'^(https|itms-apps)://'"));
    expect(sql, isNot(contains('update public.app_version_policy')));
    expect(sql, isNot(contains('minimum_build =')));
    expect(sql, isNot(contains('not null')));
  });

  test('source is prepared as tester build 17', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('version: 1.4.1+17'));
  });
}
