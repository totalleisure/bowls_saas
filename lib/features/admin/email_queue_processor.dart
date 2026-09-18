import 'package:supabase_flutter/supabase_flutter.dart';

/// Manual processing uses the same one-row contract as Communications Control.
/// Take one bounded snapshot so newly queued mail waits for the next run.
Future<({int sent, int failed})> processPendingEmails(
  SupabaseClient client,
) async {
  final rows = await client
      .from('email_queue')
      .select('id')
      .eq('status', 'pending')
      .order('created_at', ascending: true)
      .limit(50);

  var sent = 0;
  var failed = 0;
  for (final row in rows) {
    final response = await client.functions.invoke(
      'process-email-queue',
      body: {'email_queue_id': row['id']},
    );
    final data = response.data;
    if (data is! Map ||
        data['success'] != true ||
        data['processed'] is! int ||
        data['failed'] is! int) {
      throw StateError(
        'Unexpected email processing response. Refresh the queue before retrying.',
      );
    }
    sent += data['processed'] as int;
    failed += data['failed'] as int;
  }
  return (sent: sent, failed: failed);
}
