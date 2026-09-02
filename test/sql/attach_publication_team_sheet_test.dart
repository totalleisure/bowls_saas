import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/procedures/attach_publication_team_sheet.sql',
    ).readAsStringSync();
  });

  test('attachment RPC is versioned, authorised and narrowly granted', () {
    expect(sql, contains('p_expected_composition_version integer'));
    expect(sql, contains('v_user_id uuid := auth.uid()'));
    expect(sql, contains('public.can_manage_team_selection(p_fixture_id)'));
    expect(sql, contains('SECURITY DEFINER'));
    expect(sql, contains('SET search_path = pg_catalog, public, auth'));
    expect(sql, contains('FOR UPDATE'));
    expect(sql, contains('FROM PUBLIC, anon'));
    expect(sql, contains('TO authenticated'));
  });

  test('updates only eligible retryable and genuinely unsent rows', () {
    expect(sql, contains("nq.status = 'pending'"));
    expect(sql, contains("nq.status = 'failed'"));
    expect(
      sql,
      contains("Required Team Sheet attachment is missing or stale."),
    );
    expect(sql, contains("eq.status IN ('pending', 'failed')"));
    expect(sql, contains('eq.sent_at IS NULL'));
    expect(sql, contains("THEN 'pending'"));
    expect(sql, contains('ELSE eq.last_error'));
    for (final eventType in [
      'team_published_player',
      'team_published_reserve',
      'team_published_captain',
      'team_published_vice',
      'fixture_selected',
      'reserve_promoted',
    ]) {
      expect(sql, contains("'$eventType'"));
    }
    expect(sql, contains("'notification_rows_updated'"));
    expect(sql, contains("'email_rows_updated'"));
  });

  test('rejects empty, invalid and excessive PDF attachments', () {
    expect(sql, contains("decode(p_attachment->>'contentBytes', 'base64')"));
    expect(
      sql,
      contains(
        "substring(v_pdf_bytes FROM 1 FOR 4) <> convert_to('%PDF', 'UTF8')",
      ),
    );
    expect(sql, contains('octet_length(v_pdf_bytes) > 2000000'));
  });

  test('retrying the same attachment is an idempotent no-op', () {
    expect(sql, contains('IS DISTINCT FROM jsonb_build_array(p_attachment)'));
    expect(sql, contains("nq.status = 'failed'"));
  });

  test('migration contains every complete canonical definition', () {
    final migration = File(
      'supabase/migrations/20260902152201_secure_versioned_team_sheet_attachments.sql',
    ).readAsStringSync().replaceAll('\r\n', '\n');
    final canonicalPaths = [
      'supabase/migrations/procedures/attach_publication_team_sheet.sql',
      'supabase/migrations/procedures/validate_required_team_sheet_email_attachment.sql',
      'supabase/migrations/procedures/queue_post_publication_player_change.sql',
      'supabase/migrations/procedures/reconcile_preselect_communications.sql',
    ];

    for (final path in canonicalPaths) {
      final canonical = File(path).readAsStringSync().replaceAll('\r\n', '\n');
      expect(migration, contains(canonical), reason: path);
    }
    expect(RegExp(r'\$function\$;').allMatches(migration).length, 4);
  });
}
