import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/team/acceptance_reminder_eligibility.dart';

void main() {
  for (final role in ['player', 'reserve', 'marker', 'opponent']) {
    test('pending allocated $role can receive a reminder', () {
      final row = <String, dynamic>{
        'role': role, 'acceptance': 'pending', 'is_selected': true,
      };
      expect(canRemindSelectedMember(row, isAllocated: true), isTrue);
      for (final status in ['accepted', 'declined']) {
        expect(canRemindSelectedMember({...row, 'acceptance': status},
            isAllocated: true), isFalse);
      }
      expect(canRemindSelectedMember({...row, 'is_selected': false},
          isAllocated: true), isFalse);
      expect(canRemindSelectedMember({...row, 'member_profiles': {
        'is_captain_managed': true,
      }}, isAllocated: true), isFalse);
    });
  }
  test('unallocated player cannot receive a selection reminder', () {
    expect(canRemindSelectedMember({
      'role': 'player', 'acceptance': 'pending', 'is_selected': true,
    }, isAllocated: false), isFalse);
  });
}
