import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  const migration =
      'supabase/migrations/20260905134032_phase_three_safe_fixture_communications_control.sql';

  test('control-centre RPCs require a signed-in superuser', () {
    final sql = source(migration);
    expect(sql, contains('communications_require_superuser'));
    expect(sql, contains('auth.uid() is null'));
    expect(sql, contains('from public.app_superusers'));
    expect(sql, contains('Superuser access required.'));
    expect(sql, contains('from public, anon, authenticated'));
  });

  test('publication repair is additive and never processes a queue', () {
    final sql = source(
      'supabase/migrations/procedures/repair_fixture_publication_communications.sql',
    );
    expect(sql, isNot(contains('delete from public.notification_queue')));
    expect(sql, isNot(contains('delete from public.app_notifications')));
    expect(sql, isNot(contains('delete from public.email_queue')));
    expect(sql, isNot(contains('process_notification_queue(')));
    expect(sql, contains('reconcile_preselect_communications'));
    expect(sql, contains('queue_team_publication_communications'));
  });

  test('notification preparation is restricted to one fixture', () {
    final sql = source(
      'supabase/migrations/procedures/process_fixture_notification_queue.sql',
    );
    expect(sql, contains('nq.fixture_id = p_fixture_id'));
    expect(sql, contains("nq.status = 'pending'"));
    expect(sql, contains("'app.notification_queue_ids'"));
  });

  test('retry does not revive missing or stale Team Sheet failures', () {
    final sql = source(
      'supabase/migrations/procedures/retry_fixture_failed_emails.sql',
    );
    expect(sql, contains('eq.fixture_id = p_fixture_id'));
    expect(
      sql,
      contains("'Required Team Sheet attachment is missing or stale.'"),
    );
    expect(sql, contains('is distinct from'));
  });

  test('status validates pending Team Sheets before fixture processing', () {
    final sql = source(
      'supabase/migrations/procedures/communications_fixture_status_v2.sql',
    );
    expect(sql, contains('v_pending_sheet_failures'));
    expect(sql, contains("nq.payload->>'team_sheet_required' = 'true'"));
    expect(sql, contains("nq.payload->'attachments'"));
    expect(sql, contains("like 'JVBERi%'"));
    expect(sql, contains("'compositionVersion'"));
    expect(
      sql.indexOf('elsif v_pending_notifications > 0'),
      lessThan(
        sql.indexOf(
          'elsif v_app_actual < v_app_expected or v_email_actual < v_email_expected',
        ),
      ),
    );
  });

  test('screen does not invoke global queue processing', () {
    final dart = source(
      'lib/features/communications/communications_control_centre.dart',
    );
    expect(dart, contains("'process_fixture_notification_queue'"));
    expect(dart, isNot(contains("'process_notification_queue'")));
    expect(dart, contains("body: {'email_queue_id': id}"));
    expect(dart, isNot(contains("body: {'limit': 200}")));
    expect(dart, isNot(contains("'repair_preselect_communications'")));
  });

  test('health detail derives recipients from authoritative composition', () {
    final sql = source(
      'supabase/migrations/procedures/communications_health_detail_v2.sql',
    );
    expect(sql, contains('preselect_assignments as'));
    expect(sql, contains('ordinary_players as'));
    expect(sql, contains('ordinary_reserves as'));
    expect(sql, contains('marker_volunteers as'));
    expect(sql, contains('not exists ('));
    expect(
      sql,
      contains(
        "jsonb_array_length(coalesce(mail.attachments, '[]'::jsonb)) = 1",
      ),
    );
    expect(sql, contains("like 'JVBERi%'"));
    expect(sql, contains("'compositionVersion' = v_composition_version::text"));
    expect(sql, contains("mail.status = 'sent'"));
  });

  test('email processor permits user calls only for one row', () {
    final edge = source('supabase/functions/process-email-queue/index.ts');
    expect(edge, contains('isServiceRoleCall'));
    expect(edge, contains('!requestedEmailQueueId || !bearer'));
    expect(edge, contains('supabase.auth.getUser'));
    expect(edge, contains('Superuser access required.'));
  });

  test('governing migration contains every canonical Phase III definition', () {
    final sql =
        (source(migration) +
                source(
                  'supabase/migrations/20260905141355_correct_phase_three_notification_team_sheet_status.sql',
                ) +
                source(
                  'supabase/migrations/20260905141607_preserve_valid_historical_team_sheet_revisions.sql',
                ))
            .replaceAll('\r\n', '\n');
    const canonical = <String>[
      'communications_require_superuser.sql',
      'queue_team_publication_communications.sql',
      'communications_health_check_v2.sql',
      'communications_health_detail_v2.sql',
      'communications_fixture_status_v2.sql',
      'repair_fixture_publication_communications.sql',
      'process_fixture_notification_queue.sql',
      'retry_fixture_failed_emails.sql',
    ];
    for (final name in canonical) {
      final definition = source(
        'supabase/migrations/procedures/$name',
      ).replaceAll('\r\n', '\n').trim();
      expect(sql, contains(definition), reason: '$name differs from migration');
    }
  });
}
