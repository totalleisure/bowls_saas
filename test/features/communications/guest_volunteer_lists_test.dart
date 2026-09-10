import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Dashboard hides Volunteer Lists for Guest memberships', () {
    final dashboard = File(
      'lib/features/clubs/club_dashboard_screen.dart',
    ).readAsStringSync();
    final menu = File(
      'lib/features/communications/member_options_menu.dart',
    ).readAsStringSync();

    expect(dashboard, contains('allowVolunteerLists: _canWrite'));
    expect(dashboard, contains('_canWrite = access.canWrite'));
    expect(menu, contains('if (allowVolunteerLists)'));
  });

  test('ordinary members retain the Volunteer Lists menu by default', () {
    final menu = File(
      'lib/features/communications/member_options_menu.dart',
    ).readAsStringSync();

    expect(menu, contains('bool allowVolunteerLists = true'));
  });
}
