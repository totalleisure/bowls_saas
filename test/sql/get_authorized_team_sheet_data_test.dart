import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('team-sheet RPC enforces the server-side access matrix', () {
    final sql = File(
      'supabase/migrations/procedures/get_authorized_team_sheet_data.sql',
    ).readAsStringSync();

    expect(sql, contains('SECURITY DEFINER'));
    expect(sql, contains('SET search_path = pg_catalog, public, auth'));
    expect(sql, contains('v_user_id uuid := auth.uid()'));
    expect(sql, contains("v_selection.status = 'published'"));
    expect(sql, contains('public.can_manage_team_selection(p_fixture_id)'));
    expect(sql, contains('public.my_member_profile_id()'));
    expect(sql, contains('fra.position BETWEEN 1 AND fr.players_per_rink'));
    expect(sql, contains("tsm.role = 'reserve'"));
    expect(sql, contains('ELSIF NOT v_can_manage'));
    expect(
      RegExp(
        'Not authorised to view this team sheet',
        caseSensitive: false,
      ).allMatches(sql).length,
      greaterThanOrEqualTo(3),
    );
    expect(sql, contains('FROM PUBLIC, anon'));
    expect(sql, contains('TO authenticated'));
  });

  test('migration and canonical function definitions are identical', () {
    final canonical = File(
      'supabase/migrations/procedures/get_authorized_team_sheet_data.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final migration = File(
      'supabase/migrations/20260902130351_authorize_team_sheet_reads.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(migration, canonical);
    expect(RegExp(r'\$function\$;').allMatches(migration).length, 1);
  });
}
