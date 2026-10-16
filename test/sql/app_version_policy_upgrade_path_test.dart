import 'dart:io';
import 'release_source.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const migration =
      'supabase/migrations/20260907000924_add_platform_update_destinations.sql';

  test('upgrade destination migration is nullable and non-enforcing', () {
    final sql = releaseSource(migration).toLowerCase();

    expect(sql, contains('add column if not exists update_url text'));
    expect(sql, contains('add column if not exists update_message text'));
    expect(sql, contains("'^(https|itms-apps)://'"));
    expect(sql, isNot(contains('update public.app_version_policy')));
    expect(sql, isNot(contains('minimum_build =')));
    expect(sql, isNot(contains('not null')));
  });

  test('release declares a valid version and increasing build number', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(r'^version: (\d+)\.(\d+)\.(\d+)\+(\d+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(version, isNotNull);
    // Build 17 was the historical upgrade-path baseline, not the current release.
    expect(int.parse(version!.group(4)!), greaterThan(17));
  });
}
