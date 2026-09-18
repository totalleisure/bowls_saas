import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// Use the HTTP transport already supplied by the locked Supabase dependency.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:bowls_saas/features/admin/email_queue_processor.dart';

void main() {
  late SupabaseClient client;
  tearDown(() async => client.dispose());

  SupabaseClient fakeClient(
    List<String> ids,
    Future<http.Response> Function(String id) send,
  ) {
    return SupabaseClient(
      'https://example.invalid',
      'test-key',
      httpClient: MockClient((request) async {
        if (request.url.path == '/rest/v1/email_queue') {
          expect(request.method, 'GET');
          expect(request.url.queryParameters['select'], 'id');
          expect(request.url.queryParameters['status'], 'eq.pending');
          expect(
            request.url.queryParameters['order'],
            'created_at.asc.nullslast',
          );
          expect(request.url.queryParameters['limit'], '50');
          return http.Response(
            jsonEncode(ids.map((id) => {'id': id}).toList()),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        expect(request.url.path, '/functions/v1/process-email-queue');
        expect(request.method.toUpperCase(), 'POST');
        final body = jsonDecode(request.body) as Map;
        expect(body.keys, ['email_queue_id']);
        return send(body['email_queue_id'] as String);
      }),
    );
  }

  http.Response result(int sent, int failed) => http.Response(
    jsonEncode({'success': true, 'processed': sent, 'failed': failed}),
    200,
    headers: {'content-type': 'application/json'},
  );

  test(
    'sends each pending ID once and reports sent, failed and skipped rows',
    () async {
      final calls = <String>[];
      client = fakeClient(['first', 'second', 'already-processed'], (id) async {
        calls.add(id);
        return switch (id) {
          'first' => result(1, 0),
          'second' => result(0, 1),
          _ => result(0, 0),
        };
      });
      expect(await processPendingEmails(client), (sent: 1, failed: 1));
      expect(calls, ['first', 'second', 'already-processed']);
    },
  );

  test('empty queue never invokes email sending', () async {
    client = fakeClient([], (_) async => throw StateError('Unexpected send'));
    expect(await processPendingEmails(client), (sent: 0, failed: 0));
  });

  test(
    'stops on rejected request without retrying or sending later rows',
    () async {
      final calls = <String>[];
      client = fakeClient(['first', 'rejected', 'later'], (id) async {
        calls.add(id);
        return id == 'first'
            ? result(1, 0)
            : http.Response(
                '{"error":"Forbidden"}',
                403,
                headers: {'content-type': 'application/json'},
              );
      });
      await expectLater(
        processPendingEmails(client),
        throwsA(isA<FunctionException>()),
      );
      expect(calls, ['first', 'rejected']);
    },
  );

  test(
    'malformed success response is not reported as a successful run',
    () async {
      client = fakeClient(
        ['first'],
        (_) async => http.Response(
          '{"success":true}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      await expectLater(processPendingEmails(client), throwsStateError);
    },
  );
}
