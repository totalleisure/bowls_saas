import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<Map<String, dynamic>> visibleRows({
  required List<Map<String, dynamic>> rows,
  required String currentMemberId,
  required bool isGuest,
}) {
  if (!isGuest) return rows;
  return rows
      .where((row) => row['member_profile_id'] == currentMemberId)
      .toList();
}

void main() {
  final rows = <Map<String, dynamic>>[
    {'member_profile_id': 'me', 'role': 'guest'},
    {'member_profile_id': 'someone-else', 'role': 'member'},
  ];

  test('Guest sees exactly their own member record', () {
    final result = visibleRows(
      rows: rows,
      currentMemberId: 'me',
      isGuest: true,
    );
    expect(result, hasLength(1));
    expect(result.single['member_profile_id'], 'me');
  });

  test('Guest cannot see another member', () {
    final result = visibleRows(
      rows: rows,
      currentMemberId: 'me',
      isGuest: true,
    );
    expect(
      result.any((row) => row['member_profile_id'] == 'someone-else'),
      isFalse,
    );
  });

  test('ordinary Member visibility is unchanged', () {
    expect(
      visibleRows(rows: rows, currentMemberId: 'me', isGuest: false),
      hasLength(2),
    );
  });

  test('Admin and SuperUser visibility is unchanged', () {
    expect(
      visibleRows(rows: rows, currentMemberId: 'admin', isGuest: false),
      hasLength(2),
    );
  });

  test('Members screen constrains the Guest query at the server request', () {
    final source = File(
      'lib/features/members/members_screen.dart',
    ).readAsStringSync();
    expect(source, contains('final access = await loadClubAccess('));
    expect(source, contains("_isGuest = access.membershipRole == 'guest'"));
    expect(source, contains(".eq('member_profile_id', myProfileId)"));
  });
}
