import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = true;
  bool _refreshing = false;
  List<Map<String, dynamic>> _rows = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();

    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _load();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_refreshing) return;
    _refreshing = true;

    if (mounted) {
      setState(() => _loading = _rows.isEmpty);
    }

    try {
      final client = Supabase.instance.client;
      final myId = (await client.rpc('my_member_profile_id')).toString();

      final rows = await client
          .from('app_notifications')
          .select()
          .eq('member_profile_id', myId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _markRead(String id) async {
    final client = Supabase.instance.client;

    await client
        .from('app_notifications')
        .update({
          'is_read': true,
          'read_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id);

    _load();
  }

  String _formatNotificationCreatedAt(dynamic value) {
    if (value == null) return '';

    final dt = DateTime.tryParse(value.toString());
    if (dt == null) return '';

    final local = dt.toLocal();

    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
          ? const Center(child: Text('No notifications'))
          : ListView.separated(
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final r = _rows[i];
                final isRead = r['is_read'] == true;

                return ListTile(
                  title: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          r['title'] ?? '',
                          style: TextStyle(
                            fontWeight: isRead
                                ? FontWeight.normal
                                : FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatNotificationCreatedAt(r['created_at']),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(r['body'] ?? ''),
                  trailing: isRead ? null : const Icon(Icons.circle, size: 10),
                  onTap: () async {
                    await _markRead(r['id']);
                  },
                );
              },
            ),
    );
  }
}
