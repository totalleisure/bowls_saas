import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class QueueAdminScreen extends StatefulWidget {
  const QueueAdminScreen({super.key});

  @override
  State<QueueAdminScreen> createState() => _QueueAdminScreenState();
}

class _QueueAdminScreenState extends State<QueueAdminScreen> {
  bool _busyNotifications = false;
  bool _busyEmails = false;
  bool _loadingStats = true;

  int _notificationPending = 0;
  int _notificationFailed = 0;
  int _emailPending = 0;
  int _emailFailed = 0;
  int _emailSent = 0;

  String? _lastNotificationError;
  String? _lastEmailError;

  bool _loadingNotificationCron = true;
  bool _notificationCronActive = false;
  bool _busyNotificationCron = false;

  bool _loadingEmailCron = true;
  bool _emailCronActive = false;
  bool _busyEmailCron = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadNotificationCronStatus();
    _loadEmailCronStatus();
  }

  Future<bool> _isSuperuser() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return false;

    final row = await client
        .from('app_superusers')
        .select('user_id')
        .eq('user_id', user.id)
        .maybeSingle();

    return row != null;
  }

  Future<void> _loadNotificationCronStatus() async {
    setState(() => _loadingNotificationCron = true);

    try {
      final result = await Supabase.instance.client.rpc(
        'get_notification_queue_cron_status',
      );

      final status = result is Map
          ? Map<String, dynamic>.from(result)
          : <String, dynamic>{};

      if (!mounted) return;

      setState(() {
        _notificationCronActive = status['active'] == true;
        _loadingNotificationCron = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loadingNotificationCron = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load automatic processing status: $e'),
        ),
      );
    }
  }

  Future<void> _loadEmailCronStatus() async {
    setState(() => _loadingEmailCron = true);

    try {
      final result = await Supabase.instance.client.rpc(
        'get_email_queue_cron_status',
      );

      final status = result is Map
          ? Map<String, dynamic>.from(result)
          : <String, dynamic>{};

      if (!mounted) return;

      setState(() {
        _emailCronActive = status['active'] == true;
        _loadingEmailCron = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loadingEmailCron = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load automatic email processing status: $e'),
        ),
      );
    }
  }

  Future<void> _setEmailCronEnabled(bool enabled) async {
    if (!await _isSuperuser()) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Superuser access required.')),
      );
      return;
    }

    setState(() => _busyEmailCron = true);

    try {
      await Supabase.instance.client.rpc(
        'set_email_queue_cron_enabled',
        params: {'p_enabled': enabled},
      );

      if (!mounted) return;

      setState(() {
        _emailCronActive = enabled;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Automatic email processing resumed.'
                : 'Automatic email processing paused.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not ${enabled ? 'resume' : 'pause'} '
            'automatic email processing: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyEmailCron = false);
      }
    }
  }

  Future<void> _setNotificationCronEnabled(bool enabled) async {
    if (!await _isSuperuser()) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Superuser access required.')),
      );
      return;
    }

    setState(() => _busyNotificationCron = true);

    try {
      await Supabase.instance.client.rpc(
        'set_notification_queue_cron_enabled',
        params: {'p_enabled': enabled},
      );

      if (!mounted) return;

      setState(() {
        _notificationCronActive = enabled;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'Automatic notification processing resumed.'
                : 'Automatic notification processing paused.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not ${enabled ? 'resume' : 'pause'} '
            'automatic processing: $e',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busyNotificationCron = false);
      }
    }
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);

    try {
      final result = await Supabase.instance.client.rpc(
        'get_queue_admin_stats',
      );

      final stats = result is Map
          ? Map<String, dynamic>.from(result)
          : <String, dynamic>{};

      if (!mounted) return;

      setState(() {
        _notificationPending =
            int.tryParse((stats['notification_pending'] ?? 0).toString()) ?? 0;

        _notificationFailed =
            int.tryParse((stats['notification_failed'] ?? 0).toString()) ?? 0;

        _emailPending =
            int.tryParse((stats['email_pending'] ?? 0).toString()) ?? 0;

        _emailFailed =
            int.tryParse((stats['email_failed'] ?? 0).toString()) ?? 0;

        _emailSent = int.tryParse((stats['email_sent'] ?? 0).toString()) ?? 0;

        _lastNotificationError = stats['last_notification_error']?.toString();

        _lastEmailError = stats['last_email_error']?.toString();

        _loadingStats = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _loadingStats = false);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load queue stats: $e')));
    }
  }

  Future<void> _processNotifications() async {
    if (!await _isSuperuser()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Superuser access required.')),
      );
      return;
    }

    setState(() => _busyNotifications = true);

    try {
      await Supabase.instance.client.rpc(
        'process_notification_queue',
        params: {'p_limit': 50},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notification queue processed.')),
      );
      await _loadStats();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to process notifications: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyNotifications = false);
    }
  }

  Future<void> _processEmails() async {
    if (!await _isSuperuser()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Superuser access required.')),
      );
      return;
    }

    setState(() => _busyEmails = true);

    try {
      await Supabase.instance.client.functions.invoke(
        'process-email-queue',
        body: {'limit': 50},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Email queue processed.')));
      await _loadStats();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to process email queue: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyEmails = false);
    }
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Icon(Icons.settings_applications_outlined),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Queue Administration',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Technical tools for processing the notification and email queues.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationQueueCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.notifications_active),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Notification Queue',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _loadingStats
                            ? 'Loading queue status...'
                            : 'Pending: $_notificationPending   '
                                  'Failed: $_notificationFailed'
                                  '${_lastNotificationError == null ? '' : '\nLast error: $_lastNotificationError'}',
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 8),

            Row(
              children: [
                Icon(
                  _notificationCronActive
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline,
                  color: _notificationCronActive ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _loadingNotificationCron
                        ? 'Checking automatic processing...'
                        : _notificationCronActive
                        ? 'Automatic processing: Running every 5 minutes'
                        : 'Automatic processing: Paused',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _notificationCronActive
                          ? Colors.green
                          : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: _busyNotifications ? null : _processNotifications,
                  icon: _busyNotifications
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: const Text('Process now'),
                ),

                OutlinedButton.icon(
                  onPressed: _loadingNotificationCron || _busyNotificationCron
                      ? null
                      : () => _setNotificationCronEnabled(
                          !_notificationCronActive,
                        ),
                  icon: _busyNotificationCron
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _notificationCronActive
                              ? Icons.pause
                              : Icons.play_arrow,
                        ),
                  label: Text(
                    _notificationCronActive
                        ? 'Pause automatic processing'
                        : 'Resume automatic processing',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailQueueCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.email_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Email Queue',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _loadingStats
                            ? 'Loading queue status...'
                            : 'Pending: $_emailPending   '
                                  'Sent: $_emailSent   '
                                  'Failed: $_emailFailed'
                                  '${_lastEmailError == null ? '' : '\nLast error: $_lastEmailError'}',
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 8),

            Row(
              children: [
                Icon(
                  _emailCronActive
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline,
                  color: _emailCronActive ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _loadingEmailCron
                        ? 'Checking automatic processing...'
                        : _emailCronActive
                        ? 'Automatic processing: Running every 5 minutes'
                        : 'Automatic processing: Paused',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _emailCronActive ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            Wrap(
              spacing: 12,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  onPressed: _busyEmails ? null : _processEmails,
                  icon: _busyEmails
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: const Text('Process now'),
                ),

                OutlinedButton.icon(
                  onPressed: _loadingEmailCron || _busyEmailCron
                      ? null
                      : () => _setEmailCronEnabled(!_emailCronActive),
                  icon: _busyEmailCron
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_emailCronActive ? Icons.pause : Icons.play_arrow),
                  label: Text(
                    _emailCronActive
                        ? 'Pause automatic processing'
                        : 'Resume automatic processing',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isSuperuser(),
      builder: (context, snapshot) {
        final allowed = snapshot.data == true;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Queue Administration'),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loadingStats ? null : _loadStats,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: !allowed
              ? const Center(child: Text('Superuser access required.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 12),
                    _buildNotificationQueueCard(),
                    const SizedBox(height: 12),
                    _buildEmailQueueCard(),
                  ],
                ),
        );
      },
    );
  }
}
