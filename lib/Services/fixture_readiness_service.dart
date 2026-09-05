import 'package:supabase_flutter/supabase_flutter.dart';

class FixtureReadinessResult {
  const FixtureReadinessResult({
    required this.status,
    required this.nextAction,
    required this.message,
    required this.progress,
    required this.canRepair,
    required this.canPrepare,
    required this.canSend,
    required this.canRetry,
    required this.blockingIssues,
    required this.diagnostics,
  });

  final String status;
  final String nextAction;
  final String message;
  final int progress;
  final bool canRepair;
  final bool canPrepare;
  final bool canSend;
  final bool canRetry;
  final List<String> blockingIssues;
  final Map<String, dynamic> diagnostics;

  bool get hasBlockingIssues => blockingIssues.isNotEmpty;

  factory FixtureReadinessResult.fromMap(Map<String, dynamic> map) {
    final rawIssues = map['blocking_issues'];
    final rawDiagnostics = map['diagnostics'];

    return FixtureReadinessResult(
      status: (map['status'] ?? '').toString(),
      nextAction: (map['next_action'] ?? 'none').toString(),
      message: (map['message'] ?? '').toString(),
      progress: _asInt(map['progress']),
      canRepair: map['can_repair'] == true,
      canPrepare: map['can_prepare'] == true,
      canSend: map['can_send'] == true,
      canRetry: map['can_retry'] == true,
      blockingIssues: rawIssues is List
          ? rawIssues.map((item) => item.toString()).toList()
          : const <String>[],
      diagnostics: rawDiagnostics is Map
          ? Map<String, dynamic>.from(rawDiagnostics)
          : const <String, dynamic>{},
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class FixtureReadinessService {
  FixtureReadinessService(this.client);

  final SupabaseClient client;

  Future<FixtureReadinessResult> check(String fixtureId) async {
    final result = await client.rpc(
      'communications_fixture_status_v2',
      params: {'p_fixture_id': fixtureId},
    );

    Map<String, dynamic>? row;

    if (result is List && result.isNotEmpty) {
      final first = result.first;
      if (first is Map<String, dynamic>) {
        row = first;
      } else if (first is Map) {
        row = Map<String, dynamic>.from(first);
      }
    } else if (result is Map<String, dynamic>) {
      row = result;
    } else if (result is Map) {
      row = Map<String, dynamic>.from(result);
    }

    if (row == null) {
      throw Exception('The fixture readiness check returned no result.');
    }

    return FixtureReadinessResult.fromMap(row);
  }
}
