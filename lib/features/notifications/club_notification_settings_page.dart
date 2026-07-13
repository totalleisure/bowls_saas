import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/notification_settings_repository.dart';

class ClubNotificationSettingsPage extends StatefulWidget {
  const ClubNotificationSettingsPage({
    super.key,
    required this.clubId,
    required this.canEdit,
  });

  final String clubId;
  final bool canEdit;

  @override
  State<ClubNotificationSettingsPage> createState() =>
      _ClubNotificationSettingsPageState();
}

class _ClubNotificationSettingsPageState
    extends State<ClubNotificationSettingsPage> {
  late final NotificationSettingsRepository _repo;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool _notifyCaptainOnAcceptanceChange = true;
  bool _notifyViceCaptainOnAcceptanceChange = false;
  bool _enableInAppNotifications = true;
  bool _enablePushNotifications = true;
  bool _enableEmailNotifications = false;
  bool _notifyOnAccepted = true;
  bool _notifyOnDeclined = true;
  bool _notifyOnChangedMind = true;

  @override
  void initState() {
    super.initState();
    _repo = NotificationSettingsRepository(Supabase.instance.client);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final row = await _repo.loadClubSettings(widget.clubId);

      if (!mounted) return;

      setState(() {
        _notifyCaptainOnAcceptanceChange =
            (row?['notify_captain_on_acceptance_change'] as bool?) ?? true;
        _notifyViceCaptainOnAcceptanceChange =
            (row?['notify_vice_captain_on_acceptance_change'] as bool?) ??
            false;
        _enableInAppNotifications =
            (row?['enable_in_app_notifications'] as bool?) ?? true;
        _enablePushNotifications =
            (row?['enable_push_notifications'] as bool?) ?? true;
        _enableEmailNotifications =
            (row?['enable_email_notifications'] as bool?) ?? false;
        _notifyOnAccepted = (row?['notify_on_accepted'] as bool?) ?? true;
        _notifyOnDeclined = (row?['notify_on_declined'] as bool?) ?? true;
        _notifyOnChangedMind =
            (row?['notify_on_changed_mind'] as bool?) ?? true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load notification settings: $e';
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    if (!widget.canEdit) return;

    setState(() => _saving = true);

    try {
      await _repo.saveClubSettings(
        clubId: widget.clubId,
        notifyCaptainOnAcceptanceChange: _notifyCaptainOnAcceptanceChange,
        notifyViceCaptainOnAcceptanceChange:
            _notifyViceCaptainOnAcceptanceChange,
        enableInAppNotifications: _enableInAppNotifications,
        enablePushNotifications: _enablePushNotifications,
        enableEmailNotifications: _enableEmailNotifications,
        notifyOnAccepted: _notifyOnAccepted,
        notifyOnDeclined: _notifyOnDeclined,
        notifyOnChangedMind: _notifyOnChangedMind,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification settings saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save settings: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: widget.canEdit ? onChanged : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text('Notification Settings')),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notification Settings')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!widget.canEdit) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Read-only view. You can see the club notification settings but cannot change them.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          Text('Recipients', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  _buildSwitchTile(
                    title: 'Notify captain',
                    subtitle:
                        'Send notifications to the fixture captain when a selected player changes response.',
                    value: _notifyCaptainOnAcceptanceChange,
                    onChanged: (v) =>
                        setState(() => _notifyCaptainOnAcceptanceChange = v),
                  ),
                  _buildSwitchTile(
                    title: 'Notify vice-captain',
                    subtitle:
                        'Also notify the vice-captain when a selected player changes response.',
                    value: _notifyViceCaptainOnAcceptanceChange,
                    onChanged: (v) => setState(
                      () => _notifyViceCaptainOnAcceptanceChange = v,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          Text('Channels', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  _buildSwitchTile(
                    title: 'In-app notifications',
                    subtitle: 'Create notifications visible inside the app.',
                    value: _enableInAppNotifications,
                    onChanged: (v) =>
                        setState(() => _enableInAppNotifications = v),
                  ),
                  _buildSwitchTile(
                    title: 'Push notifications',
                    subtitle: 'Send push notifications to devices.',
                    value: _enablePushNotifications,
                    onChanged: (v) =>
                        setState(() => _enablePushNotifications = v),
                  ),
                  _buildSwitchTile(
                    title: 'Email notifications',
                    subtitle: 'Send email notifications where supported.',
                    value: _enableEmailNotifications,
                    onChanged: (v) =>
                        setState(() => _enableEmailNotifications = v),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          Text(
            'Trigger events',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  _buildSwitchTile(
                    title: 'Player accepted',
                    subtitle: 'Notify when a selected player accepts.',
                    value: _notifyOnAccepted,
                    onChanged: (v) => setState(() => _notifyOnAccepted = v),
                  ),
                  _buildSwitchTile(
                    title: 'Player declined',
                    subtitle: 'Notify when a selected player declines.',
                    value: _notifyOnDeclined,
                    onChanged: (v) => setState(() => _notifyOnDeclined = v),
                  ),
                  _buildSwitchTile(
                    title: 'Player changed mind',
                    subtitle:
                        'Notify when a player changes from accepted to declined or vice versa.',
                    value: _notifyOnChangedMind,
                    onChanged: (v) => setState(() => _notifyOnChangedMind = v),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: (!widget.canEdit || _saving) ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
