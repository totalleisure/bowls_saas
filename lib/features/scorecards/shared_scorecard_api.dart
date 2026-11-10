import 'dart:convert';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'scorecard.dart';

typedef SharedScorecardRequest =
    Future<Map<String, dynamic>> Function(
      String name,
      Map<String, dynamic> params,
    );

/// Cloud operations never replace the scorer's local save. Failed uploads are
/// retried from that saved card, including after an offline restart.
class SharedScorecardApi {
  SharedScorecardApi({SharedScorecardRequest? request}) : _request = request;
  final SharedScorecardRequest? _request;
  static bool isShared(Scorecard card) =>
      card.fixtureLink?['sharedCardId'] != null;

  static Map<String, dynamic> confirmationMetadata(
    Map<String, dynamic> shared,
  ) {
    if (shared['competitionStatus'] != 'completed') return {};
    final document = shared['document'] as Map? ?? {};
    final a = shared['totalA'] as num?, b = shared['totalB'] as num?;
    return {
      'sharedConfirmed': true,
      if (a != null && b != null && a != b)
        'sharedWinnerName': document[a > b ? 'sideA' : 'sideB'],
    };
  }

  static String errorMessage(Object error) {
    if (error is PostgrestException) return error.message;
    if (error is StateError) return error.message.toString();
    if (error is TimeoutException) {
      return 'Connection timed out. Scores remain saved on the scoring device.';
    }
    return 'Check the connection and try again. Saved scores have not been removed.';
  }

  Future<Map<String, dynamic>> call(
    String name,
    Map<String, dynamic> params,
  ) async {
    if (_request != null) return _request(name, params);
    return Map<String, dynamic>.from(
      await Supabase.instance.client
              .rpc(name, params: params)
              .timeout(const Duration(seconds: 5))
          as Map,
    );
  }

  static Map<String, dynamic> location(Scorecard card) => {
    'p_fixture_id': card.fixtureLink!['fixtureId'],
    'p_rink_id': card.fixtureLink!['fixtureRinkId'],
  };

  static Map<String, dynamic> uploadDocument(Scorecard card) {
    final doc = jsonDecode(jsonEncode(card.toJson())) as Map<String, dynamic>;
    final link = Map<String, dynamic>.from(doc['fixtureLink'] as Map);
    link.remove('sharedWriterToken');
    link.remove('sharedCardId');
    link.remove('scorerUserId');
    link.remove('sharedConfirmed');
    link.remove('sharedWinnerName');
    link.remove('sharedCorrectionRequest');
    doc['fixtureLink'] = link;
    return doc;
  }

  Future<Map<String, dynamic>> sync(Scorecard card) =>
      call('sync_shared_scorecard', {
        ...location(card),
        'p_writer_token': card.fixtureLink!['sharedWriterToken'],
        'p_sequence': card.saveVersion,
        'p_document': uploadDocument(card),
      });

  Future<Map<String, dynamic>> reopen(Scorecard card) =>
      call('reopen_shared_scorecard', {
        ...location(card),
        'p_writer_token': card.fixtureLink!['sharedWriterToken'],
      });
}
