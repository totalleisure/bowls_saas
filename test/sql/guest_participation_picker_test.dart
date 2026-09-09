import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(path).readAsStringSync();

void main() {
  const canonical =
      'supabase/migrations/procedures/get_club_member_picker_list.sql';
  const migration =
      'supabase/migrations/20260909144556_exclude_guests_from_participation_picker.sql';

  test('picker migration exactly matches its canonical definition', () {
    expect(source(migration), source(canonical));
  });

  test('participation picker includes active non-Guest memberships only', () {
    final sql = source(canonical);

    expect(sql, contains('cm.is_active = true'));
    expect(sql, contains("lower(cm.role::text) <> 'guest'"));
  });

  test('ordinary read-only member/profile sources remain Guest-aware', () {
    final membersScreen = source('lib/features/members/members_screen.dart');
    final picker = source('lib/core/widgets/club_member_picker_page.dart');

    expect(membersScreen, contains("_filterChip('guest', 'Guests')"));
    expect(picker, contains("'get_club_member_picker_list'"));
  });

  test('all current shared picker callers are participation flows', () {
    const expectedCallers = <String>[
      'lib/core/helpers/member_picker_helpers.dart',
      'lib/features/team/team_pool_screen.dart',
      'lib/features/team/manage_team_screen.dart',
      'lib/features/communications/mailing_list_members_screen.dart',
      'lib/features/fixtures/create_fixture_page.dart',
      'lib/features/fixtures/fixture_details_page.dart',
      'lib/features/fixtures/set_captain_section.dart',
    ];

    for (final path in expectedCallers) {
      expect(
        source(path),
        contains('ClubMemberPickerPage('),
        reason: '$path should remain routed through the participation picker',
      );
    }

    expect(
      source('lib/features/members/members_screen.dart'),
      isNot(contains('ClubMemberPickerPage(')),
    );
  });
}
