import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/fixtures/fixture_type_booking_policy.dart';

void main() {
  test('booking errors omit technical PostgREST wrappers and SQL codes', () {
    const error = PostgrestException(
      message: 'Booking duration cannot exceed 150 minutes.',
      code: 'P0001',
      details: 'Bad Request',
    );
    expect(
      bookingErrorMessage(error),
      'Booking duration cannot exceed 150 minutes.',
    );
    expect(
      bookingErrorMessage(Exception('Choose 09:00 or 11:30.')),
      'Choose 09:00 or 11:30.',
    );
  });

  final type = <String, dynamic>{
    'bookable_by_members': true,
    'booking_start_times_enabled': true,
    'lock_duration': true,
    'default_duration_minutes': 150,
  };
  final windows = <Map<String, dynamic>>[
    {
      'from': 540,
      'until': 840,
      'starts': [540, 690],
    },
    {
      'from': 900,
      'until': 1080,
      'starts': [900, 990],
    },
  ];
  String? check(
    int hour,
    int minute,
    int duration, {
    bool admin = false,
    bool home = true,
  }) {
    final start = DateTime(2032, 1, 17, hour, minute);
    return fixtureTypeTimingError(
      type,
      windows,
      start,
      start.add(Duration(minutes: duration)),
      privileged: admin,
      home: home,
    );
  }

  test('morning starts, shorter bookings and exclusive end boundary', () {
    expect(check(9, 0, 120), null);
    expect(check(11, 30, 150), null);
    expect(check(10, 0, 120), contains('09:00 or 11:30'));
    expect(check(14, 0, 150), null);
    expect(check(14, 15, 120), null);
  });
  test('multiple windows and start rules can be disabled per type', () {
    expect(check(15, 0, 120), null);
    expect(check(15, 30, 120), isNotNull);
    type['booking_start_times_enabled'] = false;
    expect(check(15, 30, 120), null);
    type['booking_start_times_enabled'] = true;
  });
  test(
    'duration cap, admin override, away bookings and unlocked flexibility',
    () {
      expect(check(14, 0, 151), contains('150 minutes'));
      expect(check(10, 0, 240, admin: true), null);
      expect(check(10, 0, 120, home: false), null);
      type['lock_duration'] = false;
      expect(check(14, 0, 240), null);
      type['lock_duration'] = true;
    },
  );
  test(
    'weekday starts remain free; Saturday and Sunday starts are restricted; duration cap applies every day',
    () {
      for (var day = 12; day <= 18; day++) {
        final start = DateTime(2032, 1, day, 10);
        final error = fixtureTypeTimingError(
          type,
          windows,
          start,
          start.add(const Duration(minutes: 120)),
          privileged: false,
        );
        expect(
          error == null,
          start.weekday < DateTime.saturday,
          reason: '${start.weekday}',
        );
        expect(
          fixtureTypeTimingError(
            type,
            windows,
            start,
            start.add(const Duration(minutes: 151)),
            privileged: false,
          ),
          contains('150 minutes'),
        );
      }
    },
  );
}
