import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/auth/account_username_service.dart';

void main() {
  test('username normalization and format agree with server restrictions', () {
    expect(AccountUsernameService.normalize('  Alex.Bowler  '), 'alex.bowler');
    for (final value in ['alex', 'a_b', 'alex.bowler', 'a-b']) {
      expect(AccountUsernameService.valid(value), isTrue);
    }
    for (final value in [
      '',
      'ab',
      '.alex',
      'Alex',
      'a@example.com',
      'áléx',
      'admin',
      'a' * 31,
    ]) {
      expect(AccountUsernameService.valid(value), isFalse, reason: value);
    }
  });
}
