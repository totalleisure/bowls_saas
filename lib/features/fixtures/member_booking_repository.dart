import 'fixture_type_booking_policy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/date_format.dart';
import '../clubs/club_access.dart';

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

  int availableRinks(
    DateTime start,
    List<String> labels, {
    required Duration duration,
  }) {
    final free = labels
        .where((label) => canBook(label, start, labels, duration: duration))
        .toList();
    for (var count = free.length; count > 0; count--) {
      if (canBook(
        free.first,
        start,
        labels,
        duration: duration,
        rinksRequired: count,
      ))
        return count;
    }
    return 0;
  }

  bool _overlaps(Map<String, dynamic> row, DateTime start, DateTime end) =>
      parseClubTime(
        row['start_at'].toString(),
      ).isBefore(memberBookingWallTime(end)) &&
      parseClubTime(
        row['end_at'].toString(),
      ).isAfter(memberBookingWallTime(start));

  /// Includes unallocated capacity reservations and maintenance, not just blocks
  /// drawn on physical rinks. Adjacent bookings can share an interval boundary.
  bool canBook(
    String label,
    DateTime start,
    List<String> labels, {
    Duration duration = memberBookingDuration,
    int rinksRequired = 1,
  }) {
    start = memberBookingWallTime(start);
    final end = start.add(duration);
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
      if (occupied + blocked + rinksRequired > labels.length) return false;
    }
    return true;
  }
}

class MemberBookingRepository {
  MemberBookingRepository([SupabaseClient? client])
    : client = client ?? Supabase.instance.client;
  final SupabaseClient client;

  Future<bool> canManageFixtures(String clubId) async => (await loadClubAccess(
    clubId: clubId,
    client: client,
  )).canAdminManageFixtures;

  Future<List<Map<String, dynamic>>> adminFixtureTypes(String clubId) async {
    final rows = List<Map<String, dynamic>>.from(
      await client
          .from('competition_types')
          .select(
            '*, colour_scheme:fixture_colour_schemes(background_hex, foreground_hex)',
          )
          .eq('club_id', clubId)
          .eq('is_active', true)
          .eq('uses_rinks', true)
          .order('name'),
    );
    final windows = await loadBookingWindows(client, clubId);
    return rows.map((row) => {...row, 'booking_windows': windows}).toList();
  }

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
      final access = await loadClubAccess(clubId: clubId, client: client);
      if (access.isSuperuser) return access.currentMemberId;
      throw StateError(
        'An active non-guest club membership is needed to book.',
      );
    }
    return row['id'].toString();
  }

  Future<List<Map<String, dynamic>>> fixtureTypes(String clubId) async {
    final rows = List<Map<String, dynamic>>.from(
      await client
          .from('competition_types')
          .select(
            'id, name, section, default_rinks_required, default_players_per_rink, default_format, default_duration_minutes, lock_duration, lock_format, lock_rinks, lock_participation, bookable_by_members, booking_start_times_enabled, dress_code, '
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
    if (rows.isEmpty) return rows;
    final windows = await loadBookingWindows(client, clubId);
    return rows.map((row) => {...row, 'booking_windows': windows}).toList();
  }

  Future<List<Map<String, dynamic>>> venues(String clubId) async =>
      List<Map<String, dynamic>>.from(
        await client
            .from('venues')
            .select(
              'id, name, latitude, longitude, club_start_time, club_end_time',
            )
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
    final configuredMinutes = (type['default_duration_minutes'] as num?)
        ?.toInt();
    if (configuredMinutes != null &&
        configuredMinutes > 0 &&
        configuredMinutes != memberBookingDuration.inMinutes) {
      return bookWindow(
        clubId: clubId,
        memberId: memberId,
        type: type,
        venueId: venueId,
        green: green,
        label: label,
        start: start,
        duration: Duration(minutes: configuredMinutes),
      );
    }
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

  Future<void> checkSlotWindow(
    String greenId,
    String label,
    DateTime start,
    Duration duration,
  ) async {
    if (duration == memberBookingDuration)
      return checkSlot(greenId, label, start);
    final rows = List<Map<String, dynamic>>.from(
      await client.rpc(
        'get_green_rink_availability',
        params: {
          'p_green_area_id': greenId,
          'p_start_at': clubTimeToUtc(start).toIso8601String(),
          'p_end_at': clubTimeToUtc(start.add(duration)).toIso8601String(),
          'p_exclude_fixture_id': null,
        },
      ),
    );
    final rink = rows.where((r) => r['rink_label'] == label).firstOrNull;
    if (rink == null ||
        rink['is_booked'] == true ||
        ((rink['free_capacity_rinks'] as num?)?.toInt() ?? 0) < 1)
      throw StateError(
        'That space is no longer available. Choose another rink or time.',
      );
  }

  Future<String> bookWindow({
    required String clubId,
    required String memberId,
    required Map<String, dynamic> type,
    required String venueId,
    required Map<String, dynamic> green,
    required String label,
    required DateTime start,
    required Duration duration,
  }) async {
    if (!type.containsKey('lock_duration') && duration == memberBookingDuration)
      return book(
        clubId: clubId,
        memberId: memberId,
        type: type,
        venueId: venueId,
        green: green,
        label: label,
        start: start,
      );
    await checkSlotWindow(green['id'].toString(), label, start, duration);
    final players = (type['default_players_per_rink'] as num?)?.toInt() ?? 1;
    final format =
        type['default_format'] ??
        ({1: 'singles', 2: 'pairs', 3: 'triples', 4: 'rinks'}[players] ??
            'singles');
    final id = await client.rpc(
      'create_fixture_with_booking_policy',
      params: {
        'p_participation_mode': 'preselect',
        'p_booking': {
          'p_club_id': clubId,
          'p_start_at': clubTimeToUtc(start).toIso8601String(),
          'p_end_at': clubTimeToUtc(start.add(duration)).toIso8601String(),
          'p_is_home': true,
          'p_section': type['section'] ?? 'open',
          'p_rinks_required': 1,
          'p_players_per_rink': players,
          'p_format': format,
          'p_competition_type_id': type['id'],
          'p_dress_code': type['dress_code'] ?? 'open',
          'p_team_name': type['name'],
          'p_requires_rsvp': false,
          'p_venue_id': venueId,
          'p_green_area_id': green['id'],
          'p_orientation':
              green['discipline'] == 'outdoor' &&
                  green['orientation_mode'] != 'not_applicable' &&
                  (green['allowed_orientations'] as List? ?? []).isNotEmpty
              ? (green['allowed_orientations'] as List).first
              : null,
          'p_captain_member_profile_id': memberId,
          'p_create_team_selection': true,
          'p_team_selection_status': 'published',
          'p_home_rink_labels': [
            {'team_no': 1, 'home_rink_label': label},
          ],
          'p_rink_assignments': [
            {'team_no': 1, 'member_profile_id': memberId, 'position': 1},
          ],
          'p_team_selection_members': [
            {
              'member_profile_id': memberId,
              'role': 'player',
              'is_selected': true,
              'acceptance': 'accepted',
            },
          ],
        },
      },
    );
    if (id is! String || id.isEmpty)
      throw StateError('Booking did not return a fixture.');
    return id;
  }
}
