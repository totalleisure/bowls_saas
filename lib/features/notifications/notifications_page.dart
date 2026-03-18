import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final client = Supabase.instance.client;

      final myId =
          (await client.rpc('my_member_profile_id')).toString();

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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _loading = false;
      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(child: Text('No notifications'))
              : ListView.separated(
                  itemCount: _rows.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = _rows[i];
                    final isRead = r['is_read'] == true;

                    return ListTile(
                      title: Text(
                        r['title'] ?? '',
                        style: TextStyle(
                          fontWeight:
                              isRead ? FontWeight.normal : FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(r['body'] ?? ''),
                      trailing: isRead
                          ? null
                          : const Icon(Icons.circle, size: 10),
                      onTap: () async {
                        await _markRead(r['id']);
                      },
                    );
                  },
                ),
    );
  }
}