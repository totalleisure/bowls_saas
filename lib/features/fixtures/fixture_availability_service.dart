import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/date_format.dart';

/// Returns every changed availability response, or null when the member cancels.
/// Selections and acceptance are deliberately outside this operation.
Future<Map<String, String>?> saveFixtureAvailability(
  BuildContext context, {
  required String fixtureId,
  required String status,
  SupabaseClient? client,
}) async {
  final api = client ?? Supabase.instance.client;
  String? confirmation;
  while (context.mounted) {
    final result = Map<String, dynamic>.from(
      await api.rpc(
            'set_my_fixture_availability',
            params: {
              'p_fixture': fixtureId,
              'p_status': status,
              'p_confirmation': confirmation,
            },
          )
          as Map,
    );
    if (!context.mounted) return null;
    if (result['saved'] == true) {
      return {
        for (final row in result['changes'] as List)
          row['fixture_id'].toString(): row['status'].toString(),
      };
    }
    final chosen = Map<String, dynamic>.from(result['chosen'] as Map);
    final conflicts = (result['conflicts'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    Widget match(Map<String, dynamic> row, Color background, String heading) {
      final start = DateTime.parse(row['start_at'].toString());
      final end = DateTime.tryParse(row['end_at']?.toString() ?? '');
      return Card(
        color: background,
        surfaceTintColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                heading,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text('${row['type'] ?? 'Fixture'} · ${row['club'] ?? ''}'),
              Text(
                '${row['is_home'] == true ? 'Home' : 'Away'} · ${row['venue'] ?? ''}',
              ),
              Text(
                '${formatClubDateTime(start)}${end == null ? '' : ' – ${formatClubDateTime(end)}'}',
              ),
            ],
          ),
        ),
      );
    }

    final change = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('These matches overlap'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (confirmation != null)
                  const Text(
                    'The fixture times or availability have changed. Please check the updated details.',
                  ),
                const Text(
                  'You are already Available for the following match. Choose which availability to keep.',
                ),
                for (final row in conflicts)
                  match(row, const Color(0xffffefdc), 'Currently Available'),
                match(chosen, const Color(0xffe7f1fc), 'Your new choice'),
                const Text(
                  'Switching marks you Available for your new choice and Not available for overlapping availability requests. It does not change team selection or acceptance.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep existing availability'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Switch availability'),
          ),
        ],
      ),
    );
    if (change != true || !context.mounted) return null;
    confirmation = result['confirmation'].toString();
  }
  return null;
}
