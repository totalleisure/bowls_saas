import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  test(
    'Team, RSVP and confirmed changes rebuild the authoritative attachment',
    () {
      final manage = source('lib/features/team/manage_team_screen.dart');

      expect(manage, contains('_publishTeamSelection('));
      expect(manage, contains("'confirm_team_changes'"));
      expect(manage, contains('.rebuildTeamSheetAttachment('));
    },
  );

  test(
    'Pre-Select creation and reconciliation attach through their own route',
    () {
      final create = source('lib/features/fixtures/create_fixture_page.dart');
      final details = source('lib/features/fixtures/fixture_details_page.dart');
      final reconcile = source(
        'supabase/migrations/procedures/reconcile_preselect_communications.sql',
      );

      expect(create, contains("'repair_preselect_communications'"));
      expect(create, contains('.rebuildTeamSheetAttachmentForFixture('));
      expect(
        details,
        contains("'process_fixture_post_publish_communications'"),
      );
      expect(details, contains('.rebuildTeamSheetAttachmentForFixture('));
      expect(reconcile, contains("fra.position = 201"));
      expect(reconcile, contains("'team_sheet_required', true"));
      expect(reconcile, contains("'team_published_captain'"));
      expect(reconcile, contains("'team_published_vice'"));
    },
  );

  test('required Team Sheet emails are blocked before sending', () {
    final trigger = source(
      'supabase/migrations/procedures/validate_required_team_sheet_email_attachment.sql',
    );
    final processor = source('supabase/functions/process-email-queue/index.ts');

    expect(trigger, contains('trg_00_validate_required_team_sheet_attachment'));
    expect(
      trigger,
      contains('Required Team Sheet attachment is missing or stale.'),
    );
    expect(processor, contains('TEAM_SHEET_EVENT_TYPES'));
    expect(processor, contains('validPdfAttachment'));
    expect(processor, contains('bytes.length <= 2_000_000'));
    expect(
      processor,
      contains(
        'attachment.compositionVersion !== selection?.composition_version',
      ),
    );
    expect(processor, contains('status: "failed"'));
  });

  test(
    'old Rink Assignments screen exposes no direct publication email control',
    () {
      final rinkAssignments = source(
        'lib/features/rinks/rink_assignments_screen.dart',
      );

      expect(
        rinkAssignments,
        isNot(contains("label: const Text('Publish & Email Team Sheet')")),
      );
      expect(
        rinkAssignments,
        isNot(contains("label: const Text('Resend Team Sheet Emails')")),
      );
    },
  );

  test('Graph transport sends only Microsoft Graph attachment fields', () {
    final graph = source('supabase/functions/send-graph-email/index.ts');

    expect(graph, contains('name: a.name'));
    expect(graph, contains('contentType: a.contentType'));
    expect(graph, contains('contentBytes: a.contentBytes'));
    expect(graph, isNot(contains('compositionVersion')));
  });
}
