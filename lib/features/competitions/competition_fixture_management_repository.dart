import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/date_format.dart';
import 'competition_repository.dart';
import 'competition_arrangement_repository.dart';

class CompetitionFixtureManagementRepository
    extends CompetitionArrangementRepository {
  final String fixtureId;
  CompetitionFixtureManagementRepository(SupabaseClient client, this.fixtureId)
    : super(client);

  Future<CompetitionRow> load() async => Map<String, dynamic>.from(
    await client.rpc(
          'competition_fixture_management_state',
          params: {'p_fixture_id': fixtureId},
        )
        as Map,
  );
  @override
  Future<List<CompetitionRow>> availability(
    String greenId,
    DateTime start,
    DateTime end,
  ) async => List<CompetitionRow>.from(
    await client.rpc(
      'get_green_rink_availability',
      params: {
        'p_green_area_id': greenId,
        'p_start_at': clubTimeToUtc(start).toIso8601String(),
        'p_end_at': clubTimeToUtc(end).toIso8601String(),
        'p_exclude_fixture_id': fixtureId,
      },
    ),
  );
  Future<void> changeBooking(
    CompetitionBookingChoice choice,
    CompetitionRow expected,
    List<String?> expectedLabels,
  ) async {
    await client.rpc(
      'change_competition_fixture_booking',
      params: {
        'p_fixture_id': fixtureId,
        'p_green_area_id': choice.green['id'],
        'p_start_at': clubTimeToUtc(choice.start).toIso8601String(),
        'p_end_at': clubTimeToUtc(choice.end).toIso8601String(),
        'p_rink_labels': choice.rinkLabels,
        'p_orientation': choice.orientation,
        'p_expected_start_at': expected['start_at'],
        'p_expected_end_at': expected['end_at'],
        'p_expected_green_area_id': expected['green_area_id'],
        'p_expected_rink_labels': expectedLabels,
      },
    );
  }

  Future<void> setMarker(
    CompetitionRow rink,
    bool required,
    String? memberId,
  ) async {
    await client.rpc(
      'set_competition_fixture_marker',
      params: {
        'p_fixture_id': fixtureId,
        'p_fixture_rink_id': rink['id'],
        'p_required': required,
        'p_marker_member_id': memberId,
        'p_expected_required': rink['marker_required'],
        'p_expected_marker_member_id': rink['marker_member_id'],
      },
    );
  }
}
