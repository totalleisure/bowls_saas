import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/date_format.dart';
import 'repeat_fixture_planner_page.dart';

class ExistingFixtureRepeatResult {
  const ExistingFixtureRepeatResult({
    required this.date,
    required this.success,
    required this.message,
    this.fixtureId,
  });

  final DateTime date;
  final bool success;
  final String message;
  final String? fixtureId;
}

class RepeatExistingFixtureService {
  const RepeatExistingFixtureService(this.client);

  final SupabaseClient client;

  Future<List<ExistingFixtureRepeatResult>> create({
    required String sourceFixtureId,
    required DateTime sourceStart,
    required Duration duration,
    required List<RepeatFixtureDate> dates,
    required List<String> preferredRinkLabels,
  }) async {
    final results = <ExistingFixtureRepeatResult>[];

    for (final repeatDate in dates.where((date) => date.enabled)) {
      final start = DateTime(
        repeatDate.date.year,
        repeatDate.date.month,
        repeatDate.date.day,
        sourceStart.hour,
        sourceStart.minute,
      );
      final end = start.add(duration);

      try {
        final fixtureId = await client.rpc(
          'create_repeated_fixture_from_source',
          params: {
            'p_source_fixture_id': sourceFixtureId,
            'p_start_at': clubTimeToUtc(start).toIso8601String(),
            'p_end_at': clubTimeToUtc(end).toIso8601String(),
            'p_is_home': repeatDate.isHome,
            'p_opponent_venue_id': repeatDate.opponentVenueId,
            'p_preferred_rink_labels': preferredRinkLabels,
          },
        );

        results.add(
          ExistingFixtureRepeatResult(
            date: repeatDate.date,
            success: true,
            message: 'Created successfully',
            fixtureId: fixtureId.toString(),
          ),
        );
      } catch (error) {
        results.add(
          ExistingFixtureRepeatResult(
            date: repeatDate.date,
            success: false,
            message: error.toString(),
          ),
        );
      }
    }

    return results;
  }
}
