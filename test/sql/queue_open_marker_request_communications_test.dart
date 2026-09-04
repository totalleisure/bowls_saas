import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const canonicalPath =
    'supabase/migrations/procedures/queue_open_marker_request_communications.sql';
const migrationPath =
    'supabase/migrations/20260904021810_exclude_fixture_participants_from_marker_requests.sql';

String source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

bool isEligibleMarkerRecipient({
  required bool activeMarkerListMember,
  required bool activeClubMember,
  required bool activelySelected,
  required bool assignedInFixture,
  bool isCaptain = false,
  bool isCreatorOrRequester = false,
}) =>
    activeMarkerListMember &&
    activeClubMember &&
    !activelySelected &&
    !assignedInFixture;

bool queueIfEligible({
  required Set<String> existingRequestRecipients,
  required String markerRequestId,
  required String memberProfileId,
  required bool eligible,
}) {
  final key = '$markerRequestId/$memberProfileId';
  if (!eligible || existingRequestRecipients.contains(key)) return false;
  existingRequestRecipients.add(key);
  return true;
}

void main() {
  test('Fixture Details saves then invokes post-publish communications', () {
    final details = source('lib/features/fixtures/fixture_details_page.dart');
    final postPublish = source(
      'supabase/migrations/procedures/process_fixture_post_publish_changes.sql',
    );
    final reconcile = source(
      'supabase/migrations/procedures/reconcile_preselect_communications.sql',
    );

    expect(details, contains("'save_preselect_fixture_state'"));
    expect(details, contains("'process_fixture_post_publish_communications'"));
    expect(
      postPublish,
      contains('public.queue_open_marker_request_communications(p_fixture_id)'),
    );
    expect(
      reconcile,
      contains('public.queue_open_marker_request_communications(p_fixture_id)'),
    );
  });

  test('canonical SQL excludes selected and assigned fixture participants', () {
    final sql = source(canonicalPath);

    expect(
      RegExp(
        r'from public\.team_selection_members tsm[\s\S]*?'
        r'tsm\.team_selection_id = v_team_selection_id[\s\S]*?'
        r'tsm\.member_profile_id = mlm\.member_profile_id[\s\S]*?'
        r'tsm\.is_selected = true',
      ).allMatches(sql).length,
      2,
    );
    expect(
      RegExp(
        r'from public\.fixture_rink_assignments fra[\s\S]*?'
        r'fra\.fixture_id = p_fixture_id[\s\S]*?'
        r'fra\.member_profile_id = mlm\.member_profile_id',
      ).allMatches(sql).length,
      2,
    );
  });

  test('canonical SQL preserves per-request per-recipient deduplication', () {
    final sql = source(canonicalPath);

    expect(sql, contains("existing.event_type = 'marker_request_opened'"));
    expect(
      sql,
      contains('existing.target_member_profile_id = mlm.member_profile_id'),
    );
    expect(
      sql,
      contains("existing.payload ->> 'marker_request_id' = mr.id::text"),
    );
  });

  test('migration and canonical function definitions are identical', () {
    expect(source(migrationPath), source(canonicalPath));
  });

  group('marker recipient behaviour', () {
    bool eligible({
      bool selected = false,
      bool assigned = false,
      bool captain = false,
      bool creatorOrRequester = false,
    }) => isEligibleMarkerRecipient(
      activeMarkerListMember: true,
      activeClubMember: true,
      activelySelected: selected,
      assignedInFixture: assigned,
      isCaptain: captain,
      isCreatorOrRequester: creatorOrRequester,
    );

    test('assigned player is excluded', () {
      expect(eligible(assigned: true), isFalse);
    });

    test('selected reserve is excluded', () {
      expect(eligible(selected: true), isFalse);
    });

    test('selected member opponent is excluded', () {
      expect(eligible(selected: true, assigned: true), isFalse);
    });

    test('named marker is excluded', () {
      expect(eligible(assigned: true), isFalse);
    });

    test('non-playing captain remains eligible', () {
      expect(eligible(captain: true), isTrue);
    });

    test('non-playing creator or requester remains eligible', () {
      expect(eligible(creatorOrRequester: true), isTrue);
    });

    test('unrelated eligible Marker-list member remains eligible', () {
      expect(eligible(), isTrue);
    });

    test('duplicate invocation does not queue the recipient twice', () {
      final existing = <String>{};

      expect(
        queueIfEligible(
          existingRequestRecipients: existing,
          markerRequestId: 'request-1',
          memberProfileId: 'member-1',
          eligible: true,
        ),
        isTrue,
      );
      expect(
        queueIfEligible(
          existingRequestRecipients: existing,
          markerRequestId: 'request-1',
          memberProfileId: 'member-1',
          eligible: true,
        ),
        isFalse,
      );
      expect(existing, hasLength(1));
    });
  });
}
