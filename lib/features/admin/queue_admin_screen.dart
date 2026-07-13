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

  @override
  void initState() {
    super.initState();
    _loadStats();
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

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);

    try {
      final client = Supabase.instance.client;

      final notificationRows = await client
          .from('notification_queue')
          .select('status, last_error')
          .limit(500);

      final emailRows = await client
          .from('email_queue')
          .select('status, last_error')
          .limit(500);

      var notificationPending = 0;
      var notificationFailed = 0;
      String? lastNotificationError;

      for (final r in List<Map<String, dynamic>>.from(notificationRows)) {
        final status = (r['status'] ?? '').toString();
        if (status == 'pending') notificationPending++;
        if (status == 'failed') {
          notificationFailed++;
          lastNotificationError ??= r['last_error']?.toString();
        }
      }

      var emailPending = 0;
      var emailFailed = 0;
      var emailSent = 0;
      String? lastEmailError;

      for (final r in List<Map<String, dynamic>>.from(emailRows)) {
        final status = (r['status'] ?? '').toString();
        if (status == 'pending') emailPending++;
        if (status == 'failed') {
          emailFailed++;
          lastEmailError ??= r['last_error']?.toString();
        }
        if (status == 'sent') emailSent++;
      }

      if (!mounted) return;
      setState(() {
        _notificationPending = notificationPending;
        _notificationFailed = notificationFailed;
        _lastNotificationError = lastNotificationError;
        _emailPending = emailPending;
        _emailFailed = emailFailed;
        _emailSent = emailSent;
        _lastEmailError = lastEmailError;
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

  Widget _buildQueueCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool busy,
    required VoidCallback? onPressed,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: ElevatedButton(
          onPressed: busy ? null : onPressed,
          child: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Run now'),
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
                    _buildQueueCard(
                      icon: Icons.notifications_active,
                      title: 'Process Notification Queue',
                      subtitle: _loadingStats
                          ? 'Loading queue status...'
                          : 'Pending: $_notificationPending   '
                                'Failed: $_notificationFailed'
                                '${_lastNotificationError == null ? '' : '\nLast error: $_lastNotificationError'}',
                      busy: _busyNotifications,
                      onPressed: _processNotifications,
                    ),
                    const SizedBox(height: 12),
                    _buildQueueCard(
                      icon: Icons.email,
                      title: 'Process Email Queue',
                      subtitle: _loadingStats
                          ? 'Loading queue status...'
                          : 'Pending: $_emailPending   '
                                'Sent: $_emailSent   '
                                'Failed: $_emailFailed'
                                '${_lastEmailError == null ? '' : '\nLast error: $_lastEmailError'}',
                      busy: _busyEmails,
                      onPressed: _processEmails,
                    ),
                  ],
                ),
        );
      },
    );
  }
}
