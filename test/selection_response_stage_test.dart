import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/fixtures/selection_response_stage.dart';

void main() {
  Map<String, dynamic> row(
    String response,
    String role, {
    String status = 'published',
  }) => {
    'acceptance': response,
    'role': role,
    'team_selections': {
      'status': status,
      'fixture': {'id': 'replacement'},
    },
  };
  for (final role in ['player', 'reserve']) {
    for (final response in ['pending', 'accepted', 'declined']) {
      test(
        '$role $response uses selection response, never another availability request',
        () {
          expect(publishedSelectionFixtureIds([row(response, role)]), {
            'replacement',
          });
        },
      );
    }
  }
  test(
    'available pool member has no selected row; selection later switches stages',
    () {
      expect(publishedSelectionFixtureIds([]), isEmpty);
      expect(
        publishedSelectionFixtureIds([
          row('pending', 'player', status: 'draft'),
        ]),
        isEmpty,
      );
      expect(publishedSelectionFixtureIds([row('pending', 'player')]), {
        'replacement',
      });
      expect(publishedSelectionFixtureIds([row('accepted', 'player')]), {
        'replacement',
      });
    },
  );
  test('missing nested data cannot suppress availability', () {
    expect(
      publishedSelectionFixtureIds([
        {},
        {'team_selections': null},
        {
          'team_selections': {'status': 'published', 'fixture': null},
        },
      ]),
      isEmpty,
    );
  });
}
