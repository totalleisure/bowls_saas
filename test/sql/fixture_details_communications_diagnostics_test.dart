import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  const migration =
      'supabase/migrations/20260906214500_add_fixture_manager_communications_status.sql';
  const canonical =
      'supabase/migrations/procedures/communications_fixture_manager_status.sql';

  test('Fixture Details uses its fixture-manager diagnostic RPC', () {
    final service = source('lib/services/fixture_readiness_service.dart');
    final page = source('lib/features/fixtures/fixture_details_page.dart');

    expect(service, contains("'communications_fixture_status_v2'"));
    expect(service, contains("'communications_fixture_manager_status'"));
    expect(page, contains('.checkForFixtureManager(widget.fixtureId)'));
  });

  test('inline diagnostic visibility follows fixture management roles', () {
    final page = source('lib/features/fixtures/fixture_details_page.dart');
    final getterStart = page.indexOf(
      'bool get _canViewFixtureMaintenanceStatus',
    );
    final getterEnd = page.indexOf('\n  }', getterStart);
    final getter = page.substring(getterStart, getterEnd);

    expect(getter, contains('_isSuperuser'));
    expect(getter, contains('_isClubAdmin'));
    expect(getter, contains('_isSelector'));
    expect(getter, contains('_isFixtureCaptain'));
    expect(getter, contains('_isFixtureViceCaptain'));
    expect(getter, contains('_canManageTeam'));
    expect(getter, contains('_canEditFixtureOperationalDetails'));
  });

  test('unauthorised and event views skip diagnostics', () {
    final page = source('lib/features/fixtures/fixture_details_page.dart');
    expect(
      page,
      contains(
        'if (_isEventStyleFixture || !_canViewFixtureMaintenanceStatus)',
      ),
    );
    expect(page, contains('_readiness = null'));
    expect(page, contains('_loadingReadiness = false'));
  });

  test('diagnostic failure is isolated from Fixture Details loading', () {
    final page = source('lib/features/fixtures/fixture_details_page.dart');
    final methodStart = page.indexOf('Future<void> _loadFixtureReadiness()');
    final methodEnd = page.indexOf(
      'Future<void> _refreshFixtureRecord()',
      methodStart,
    );
    final method = page.substring(methodStart, methodEnd);

    expect(method, contains('try {'));
    expect(method, contains('} catch (e) {'));
    expect(method, contains('_readiness = null'));
    expect(method, isNot(contains('rethrow')));
  });

  test('fixture-manager RPC has a fixture-scoped authorization matrix', () {
    final sql = source(canonical);

    expect(sql, contains('v_user_id uuid := auth.uid()'));
    expect(sql, contains("raise exception 'Authentication required.'"));
    expect(sql, contains('from public.fixtures f'));
    expect(sql, contains('where f.id = p_fixture_id'));
    expect(sql, contains('from public.app_superusers'));
    expect(sql, contains('from public.club_memberships'));
    expect(sql, contains('cm.club_id = v_club_id'));
    expect(sql, contains('cm.is_active = true'));
    expect(sql, contains("in ('admin', 'selector')"));
    expect(sql, contains('v_member_profile_id = v_captain_id'));
    expect(sql, contains('v_member_profile_id = v_vice_captain_id'));
    expect(sql, contains("raise exception 'Fixture manager access required.'"));
  });

  test('fixture-manager RPC is secured and exposes only one fixture status', () {
    final sql = source(canonical);

    expect(sql, contains('security definer'));
    expect(sql, contains('set search_path = pg_catalog, public, auth'));
    expect(
      sql,
      contains(
        'revoke all on function public.communications_fixture_manager_status(uuid)',
      ),
    );
    expect(sql, contains('from public, anon, authenticated'));
    expect(
      sql,
      contains(
        'grant execute on function public.communications_fixture_manager_status(uuid)',
      ),
    );
    expect(sql, contains('to authenticated'));
    expect(
      sql,
      contains('from public.communications_fixture_status(p_fixture_id)'),
    );
    expect(sql, isNot(contains('communications_fixture_status_v2(')));
    expect(sql, isNot(contains('communications_health_detail')));
  });

  test('migration and canonical fixture-manager definition match exactly', () {
    final migrationSql = source(migration).replaceAll('\r\n', '\n').trim();
    final canonicalSql = source(canonical).replaceAll('\r\n', '\n').trim();
    expect(migrationSql, canonicalSql);
  });
}
