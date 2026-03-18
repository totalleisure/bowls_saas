import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationSettingsRepository {
  NotificationSettingsRepository(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>?> loadClubSettings(String clubId) async {
    final row = await _client
        .from('club_notification_settings')
        .select()
        .eq('club_id', clubId)
        .maybeSingle();

    return row == null ? null : Map<String, dynamic>.from(row);
  }

  Future<void> saveClubSettings({
    required String clubId,
    required bool notifyCaptainOnAcceptanceChange,
    required bool notifyViceCaptainOnAcceptanceChange,
    required bool enableInAppNotifications,
    required bool enablePushNotifications,
    required bool enableEmailNotifications,
    required bool notifyOnAccepted,
    required bool notifyOnDeclined,
    required bool notifyOnChangedMind,
  }) async {
    await _client.from('club_notification_settings').upsert({
      'club_id': clubId,
      'notify_captain_on_acceptance_change':
          notifyCaptainOnAcceptanceChange,
      'notify_vice_captain_on_acceptance_change':
          notifyViceCaptainOnAcceptanceChange,
      'enable_in_app_notifications': enableInAppNotifications,
      'enable_push_notifications': enablePushNotifications,
      'enable_email_notifications': enableEmailNotifications,
      'notify_on_accepted': notifyOnAccepted,
      'notify_on_declined': notifyOnDeclined,
      'notify_on_changed_mind': notifyOnChangedMind,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'club_id');
  }
}