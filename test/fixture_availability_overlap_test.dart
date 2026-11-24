import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/fixtures/fixture_availability_service.dart';

void main() {
  late SupabaseClient api;
  final calls = <Map>[];
  var mode = 'cancel';
  final chosen = {
    'fixture_id': 'new',
    'type': 'Friendly',
    'club': 'Club',
    'venue': 'Bromley Town',
    'is_home': false,
    'start_at': '2032-05-10T11:00:00Z',
    'end_at': '2032-05-10T15:00:00Z',
  };
  final old = {
    ...chosen,
    'fixture_id': 'old',
    'venue': 'Home Green',
    'is_home': true,
  };
  setUpAll(() async {
    api = SupabaseClient(
      'https://example.invalid',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((r) async {
        final args = jsonDecode(r.body) as Map;
        calls.add(args);
        final preview =
            calls.length == 1 || (mode == 'changed' && calls.length == 2);
        final result = preview
            ? {
                'saved': false,
                'chosen': chosen,
                'conflicts': [old],
                'confirmation': calls.length == 1 ? 'token1' : 'token2',
              }
            : {
                'saved': true,
                'changes': [
                  {'fixture_id': 'new', 'status': 'yes'},
                  {'fixture_id': 'old', 'status': 'no'},
                ],
              };
        return http.Response(
          jsonEncode(result),
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => api.dispose());
  for (final scenario in ['cancel', 'switch', 'changed']) {
    testWidgets('Availability overlap choice: $scenario', (t) async {
      mode = scenario;
      calls.clear();
      Map<String, String>? saved;
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Available'),
                onPressed: () async {
                  saved = await saveFixtureAvailability(
                    context,
                    fixtureId: 'new',
                    status: 'yes',
                    client: api,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Available'));
      await t.pumpAndSettle();
      expect(find.text('These matches overlap'), findsOneWidget);
      expect(find.textContaining('Bromley Town'), findsOneWidget);
      expect(find.textContaining('Home Green'), findsOneWidget);
      if (mode == 'cancel') {
        await t.tap(find.text('Keep existing availability'));
        await t.pumpAndSettle();
        expect(saved, isNull);
        expect(calls, hasLength(1));
      } else {
        await t.tap(find.text('Switch availability'));
        await t.pumpAndSettle();
        expect(calls[1]['p_confirmation'], 'token1');
        if (mode == 'changed') {
          expect(
            find.textContaining('fixture times or availability have changed'),
            findsOneWidget,
          );
          await t.tap(find.text('Switch availability'));
          await t.pumpAndSettle();
          expect(calls[2]['p_confirmation'], 'token2');
        }
        expect(saved, {'new': 'yes', 'old': 'no'});
      }
      expect(t.takeException(), isNull);
    });
  }
}
