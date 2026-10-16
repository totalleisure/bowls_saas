import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/core/utils/fixture_countdown.dart';

void main() {
  test('14:00 BST match at 12:49 BST is one hour eleven minutes away', () {
    expect(
      fixtureCountdown(
        '2026-10-10T13:00:00Z',
        now: DateTime.parse('2026-10-10T12:49:00+01:00'),
      ),
      '1 hour 11 mins time',
    );
  });

  test('winter and explicit offset timestamps compare the same instants', () {
    expect(
      fixtureCountdown(
        '2026-12-10T14:00:00Z',
        now: DateTime.parse('2026-12-10T12:49:00Z'),
      ),
      '1 hour 11 mins time',
    );
    expect(
      fixtureCountdown(
        '2026-10-10T14:00:00+01:00',
        now: DateTime.parse('2026-10-10T11:49:00Z'),
      ),
      '1 hour 11 mins time',
    );
  });

  test('countdown follows elapsed time across both clock changes', () {
    for (final date in ['2026-03-29', '2026-10-25']) {
      expect(
        fixtureCountdown(
          '${date}T02:00:00Z',
          now: DateTime.parse('${date}T00:30:00Z'),
        ),
        '1 hour 30 mins time',
      );
    }
  });

  test('past fixtures do not show negative minutes', () {
    expect(
      fixtureCountdown(
        '2026-10-10T13:00:00Z',
        now: DateTime.parse('2026-10-10T13:01:00Z'),
      ),
      '0 mins time',
    );
  });
}
