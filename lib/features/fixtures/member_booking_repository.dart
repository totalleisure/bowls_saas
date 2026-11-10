import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/date_format.dart';

const memberBookingDuration = Duration(minutes: 150);

// Club wall time, independent of the device's local timezone.
DateTime memberBookingWallTime(DateTime value) => DateTime.utc(
  value.year,
  value.month,
  value.day,
  value.hour,
  value.minute,
  value.second,
  value.millisecond,
  value.microsecond,
);

List<String> memberBookingRinkLabels(Map<String, dynamic> green) {
  final count = (green['rink_count'] as num?)?.toInt() ?? 0;
  final scheme = green['scheme_type'];
  final custom = green['custom_labels'] as List? ?? const [];
  final prefix = green['scheme_prefix']?.toString() ?? '';
  final padding = (green['scheme_padding'] as num?)?.toInt() ?? 0;
  return List.generate(count, (i) {
    if (scheme == 'custom_list') {
      return i < custom.length ? custom[i].toString() : '';
    }
    if (scheme == 'alpha') return '$prefix${String.fromCharCode(65 + i)}';
    return '$prefix${(i + 1).toString().padLeft(padding, '0')}';
  }).where((s) => s.isNotEmpty).toList();
}

class MemberBookingDay {
  const MemberBookingDay(this.fixtures, this.maintenance);
  final List<Map<String, dynamic>> fixtures;
  final List<Map<String, dynamic>> maintenance;

  bool _overlaps(Map<String, dynamic> row, DateTime start, DateTime end) =>
      parseClubTime(
        row['start_at'].toString(),
      ).isBefore(memberBookingWallTime(end)) &&
      parseClubTime(
        row['end_at'].toString(),
      ).isAfter(memberBookingWallTime(start));

  /// Includes unallocated capacity reservations and maintenance, not just blocks
  /// drawn on physical rinks. Adjacent bookings can share an interval boundary.
  bool canBook(String label, DateTime start, List<String> labels) {
    start = memberBookingWallTime(start);
    final end = start.add(memberBookingDuration);
    final overlapping = fixtures
        .where((f) => _overlaps(f, start, end))
        .toList();
    final repairs = maintenance.where((m) => _overlaps(m, start, end)).toList();
    if (overlapping.any(
      (f) => (f['fixture_rinks'] as List? ?? []).any(
        (r) => r['home_rink_label']?.toString() == label,
      ),
    )) {
      return false;
    }
    final number = labels.indexOf(label) + 1;
    if (number < 1 || repairs.any((m) => m['rink_number'] == number)) {
      return false;
    }
    final points = <DateTime>{start};
    for (final row in [...overlapping, ...repairs]) {
      final at = parseClubTime(row['start_at'].toString());
      if (at.isAfter(start)) points.add(at);
    }
    for (final at in points) {
      final occupied = overlapping
          .where(
            (f) => _overlaps(f, at, at.add(const Duration(microseconds: 1))),
          )
          .fold<int>(
            0,
            (n, f) => n + ((f['rinks_required'] as num?)?.toInt() ?? 0),
          );
      final blocked = repairs
          .where(
            (m) => _overlaps(m, at, at.add(const Duration(microseconds: 1))),
          )
          .map((m) => m['rink_number'])
          .toSet()
          .length;
      if (occupied + blocked + 1 > labels.length) return false;
    }
    return true;
  }
}

class MemberBookingRepository {
  MemberBookingRepository([SupabaseClient? client])
    : client = client ?? Supabase.instance.client;
  final SupabaseClient client;

  Future<String?> venueForGreen(String greenId) async {
    final row = await client
        .from('green_areas')
        .select('venue_id')
        .eq('id', greenId)
        .maybeSingle();
    return row?['venue_id']?.toString();
  }

  Future<String> memberId(String clubId) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('Sign in to book a rink.');
    final row = await client
        .from('member_profiles')
        .select('id, club_memberships!inner(id, role)')
        .eq('user_id', user.id)
        .eq('club_memberships.club_id', clubId)
        .eq('club_memberships.is_active', true)
        .maybeSingle();
    final memberships = row?['club_memberships'] as List? ?? [];
    if (row == null ||
        memberships.isEmpty ||
        memberships.every((m) => m['role'] == 'guest')) {
      throw StateError(
        'An active non-guest club membership is needed to book.',
      );
    }
    return row['id'].toString();
  }

  Future<List<Map<String, dynamic>>> fixtureTypes(
    String clubId,
  ) async => List<Map<String, dynamic>>.from(
    await client
        .from('competition_types')
        .select(
          'id, name, section, default_players_per_rink, dress_code, '
          'colour_scheme:fixture_colour_schemes(background_hex, foreground_hex)',
        )
        .eq('club_id', clubId)
        .eq('is_active', true)
        .eq('bookable_by_members', true)
        .eq('is_internal', true)
        .eq('uses_rinks', true)
        .eq('team_selection_enabled', true)
        .eq('selection_mode', 'preselect')
        .order('name'),
  );

  Future<List<Map<String, dynamic>>> venues(String clubId) async =>
      List<Map<String, dynamic>>.from(
        await client
            .from('venues')
            .select('id, name, latitude, longitude')
            .eq('club_id', clubId)
            .eq('is_home_venue', true)
            .order('name'),
      );

  Future<List<Map<String, dynamic>>> greens(
    String venueId,
  ) async => List<Map<String, dynamic>>.from(
    await client
        .from('green_areas')
        .select(
          'id, name, rink_count, scheme_type, scheme_prefix, scheme_padding, '
          'custom_labels, discipline, orientation_mode, allowed_orientations, '
          'is_outdoor, uses_sunset_cutoff, sunset_booking_offset_minutes',
        )
        .eq('venue_id', venueId)
        .order('name'),
  );

  Future<MemberBookingDay> day(
    String clubId,
    String greenId,
    DateTime date,
  ) async {
    final start = clubTimeToUtc(DateTime(date.year, date.month, date.day));
    final end = clubTimeToUtc(DateTime(date.year, date.month, date.day + 1));
    final rows = await Future.wait([
      client
          .from('fixtures')
          .select(
            'id, start_at, end_at, rinks_required, team_name, opponent_name, '
            'competition_types(name, is_internal, colour_scheme:fixture_colour_schemes(background_hex, foreground_hex)), '
            'fixture_rinks(home_rink_label)',
          )
          .eq('club_id', clubId)
          .eq('is_home', true)
          .eq('green_area_id', greenId)
          .isFilter('cancelled_at', null)
          .lt('start_at', end.toIso8601String())
          .gt('end_at', start.toIso8601String())
          .order('start_at'),
      client
          .from('green_rink_maintenance')
          .select('rink_number, start_at, end_at, reason')
          .eq('green_area_id', greenId)
          .eq('status', 'active')
          .lt('start_at', end.toIso8601String())
          .gt('end_at', start.toIso8601String()),
    ]);
    return MemberBookingDay(
      List<Map<String, dynamic>>.from(rows[0]),
      List<Map<String, dynamic>>.from(rows[1]),
    );
  }

  Future<void> checkSlot(String greenId, String label, DateTime start) async {
    final rows = List<Map<String, dynamic>>.from(
      await client.rpc(
        'get_green_rink_availability',
        params: {
          'p_green_area_id': greenId,
          'p_start_at': clubTimeToUtc(start).toIso8601String(),
          'p_end_at': clubTimeToUtc(
            start.add(memberBookingDuration),
          ).toIso8601String(),
          'p_exclude_fixture_id': null,
        },
      ),
    );
    final rink = rows.where((r) => r['rink_label'] == label).firstOrNull;
    if (rink == null ||
        rink['is_booked'] == true ||
        ((rink['free_capacity_rinks'] as num?)?.toInt() ?? 0) < 1) {
      throw StateError(
        'That space is no longer available. Choose another rink or time.',
      );
    }
  }

  Future<String> book({
    required String clubId,
    required String memberId,
    required Map<String, dynamic> type,
    required String venueId,
    required Map<String, dynamic> green,
    required String label,
    required DateTime start,
  }) async {
    if (clubTimeToUtc(start).isBefore(DateTime.now().toUtc())) {
      throw StateError('Choose a start time in the future.');
    }
    await checkSlot(green['id'].toString(), label, start);
    final id = await client.rpc(
      'create_member_rink_booking',
      params: {
        'p_club_id': clubId,
        'p_competition_type_id': type['id'],
        'p_green_area_id': green['id'],
        'p_start_at': clubTimeToUtc(start).toIso8601String(),
        'p_rink_label': label,
      },
    );
    if (id is! String || id.isEmpty) {
      throw StateError('Booking did not return a fixture.');
    }
    return id;
  }
}
