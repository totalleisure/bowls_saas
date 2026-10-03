import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/date_format.dart';

class AuditJournalScreen extends StatefulWidget {
  final String clubId;
  const AuditJournalScreen({super.key, required this.clubId});
  @override
  State<AuditJournalScreen> createState() => _AuditJournalScreenState();
}

class _AuditJournalScreenState extends State<AuditJournalScreen> {
  final _client = Supabase.instance.client;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _rows = [], _actors = [], _clubs = [];
  final Set<String> _users = {};
  String? _club, _action, _type, _origin, _outcome, _recordId;
  DateTimeRange? _dates;
  bool _busy = true, _more = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _club = widget.clubId;
    final now = toClubTime(DateTime.now());
    _dates = DateTimeRange(
      start: DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 30)),
      end: DateTime(now.year, now.month, now.day),
    );
    _init();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final options = Map<String, dynamic>.from(
        await _client.rpc('audit_filter_options') as Map,
      );
      if (!mounted) return;
      _actors = List<Map<String, dynamic>>.from(options['actors'] as List);
      _clubs = List<Map<String, dynamic>>.from(options['clubs'] as List);
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'Unable to open the journal. Superuser access and the audit database update are required.';
        });
      }
    }
  }

  Future<void> _load({bool next = false}) async {
    setState(() {
      _busy = true;
      _error = null;
      if (!next) _rows = [];
    });
    try {
      var q = _client.from('audit_journal').select();
      if (_club != null) q = q.eq('club_id', _club!);
      if (_users.isNotEmpty) q = q.inFilter('actor_user_id', _users.toList());
      if (_action != null) q = q.eq('action', _action!);
      if (_type != null) q = q.eq('record_type', _type!);
      if (_origin != null) q = q.eq('origin', _origin!);
      if (_outcome != null) q = q.eq('outcome', _outcome!);
      if (_recordId != null) q = q.eq('record_id', _recordId!);
      if (_dates != null) {
        q = q
            .gte('occurred_at', clubTimeToUtc(_dates!.start).toIso8601String())
            .lt(
              'occurred_at',
              clubTimeToUtc(
                DateTime(
                  _dates!.end.year,
                  _dates!.end.month,
                  _dates!.end.day + 1,
                ),
              ).toIso8601String(),
            );
      }
      if (_search.text.trim().isNotEmpty) {
        q = q.ilike(
          'record_label',
          '%${_search.text.trim().replaceAll('%', r'\%').replaceAll('_', r'\_')}%',
        );
      }
      final start = next ? _rows.length : 0;
      final data = await q
          .order('occurred_at', ascending: false)
          .order('id', ascending: false)
          .range(start, start + 99);
      if (mounted) {
        setState(() {
          _rows = [..._rows, ...List<Map<String, dynamic>>.from(data)];
          _more = data.length == 100;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Unable to load journal entries. Please retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickUsers() async {
    final selected = Set<String>.from(_users);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Filter by users'),
          content: SizedBox(
            width: 400,
            height: 350,
            child: ListView(
              children: _actors
                  .map(
                    (a) => CheckboxListTile(
                      title: Text(a['actor_name'].toString()),
                      value: selected.contains(a['actor_user_id']),
                      onChanged: (v) => update(() {
                        if (v == true) {
                          selected.add(a['actor_user_id'].toString());
                        } else {
                          selected.remove(a['actor_user_id']);
                        }
                      }),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Back'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      setState(() {
        _users.clear();
        _users.addAll(selected);
      });
      await _load();
    }
  }

  void _details(Map<String, dynamic> row) {
    final before = Map<String, dynamic>.from(
      (row['before_values'] as Map?) ?? {},
    );
    final after = Map<String, dynamic>.from(
      (row['after_values'] as Map?) ?? {},
    );
    final keys = {
      ...before.keys,
      ...after.keys,
    }.where((k) => before[k] != after[k]).toList()..sort();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(formatAuditRecordLabel(row['record_label'].toString())),
        content: SizedBox(
          width: 700,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText(
                  '${row['actor_name']} • ${row['action']}\nAction date and time: ${formatAuditTimestamp(row['occurred_at'].toString())}\nClub: ${row['club_name'] ?? 'Global / unassigned'}\nOrigin: ${row['origin']}\nOperation: ${row['operation_id']}\nRecord: ${row['record_id']}\nReason: ${row['reason'] ?? 'Not supplied'}',
                ),
                const Divider(),
                ...keys.map(
                  (k) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SelectableText(
                      '${k.replaceAll('_', ' ')}\nBefore: ${before[k] ?? '(blank)'}\nAfter: ${after[k] ?? '(blank)'}',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _recordId = row['record_id'].toString();
                _club = null;
                _dates = null;
                _action = null;
                _type = null;
                _origin = null;
                _outcome = null;
                _users.clear();
                _search.clear();
              });
              _load();
            },
            child: const Text('Full record history'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyLoaded() async {
    String cell(Object? value) {
      var text = value?.toString() ?? '';
      if (RegExp(r'^[=+@\-\t\r]').hasMatch(text)) text = "'$text";
      return '"${text.replaceAll('"', '""')}"';
    }

    const fields = [
      'occurred_at',
      'actor_name',
      'club_name',
      'action',
      'record_type',
      'record_label',
      'record_id',
      'origin',
      'reason',
      'operation_id',
      'outcome',
    ];
    final csv = [
      fields.map(cell).join(','),
      ..._rows.map((r) => fields.map((f) => cell(r[f])).join(',')),
    ].join('\r\n');
    await _client.rpc(
      'record_audit_export',
      params: {'p_row_count': _rows.length},
    );
    await Clipboard.setData(ClipboardData(text: csv));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_rows.length} loaded entries copied as CSV.'),
        ),
      );
    }
  }

  Widget _filter(
    String label,
    String? value,
    List<String> choices,
    void Function(String?) change,
  ) => SizedBox(
    width: 200,
    child: DropdownButtonFormField<String>(
      initialValue: value,
      key: ValueKey('$label:$value'),
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('All')),
        ...choices.map(
          (v) =>
              DropdownMenuItem(value: v, child: Text(v.replaceAll('_', ' '))),
        ),
      ],
      onChanged: _busy
          ? null
          : (v) {
              setState(() => change(v));
              _load();
            },
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Audit journal'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _busy ? null : () => _load(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        ExpansionTile(
          title: const Text('Filters'),
          children: [
            SizedBox(
              height: 280,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: 250,
                        child: DropdownButtonFormField<String>(
                          initialValue: _clubs.any((c) => c['id'] == _club)
                              ? _club
                              : null,
                          key: ValueKey('$_club:${_clubs.length}'),
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Club'),
                          items: [
                            const DropdownMenuItem<String>(
                              value: null,
                              child: Text('All clubs / global'),
                            ),
                            ..._clubs.map(
                              (c) => DropdownMenuItem(
                                value: c['id'].toString(),
                                child: Text(c['name'].toString()),
                              ),
                            ),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) {
                                  setState(() => _club = v);
                                  _load();
                                },
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final picked = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 1),
                                  ),
                                  initialDateRange: _dates,
                                );
                                if (picked != null && mounted) {
                                  setState(() => _dates = picked);
                                  await _load();
                                }
                              },
                        child: Text(
                          _dates == null
                              ? 'All dates'
                              : '${DateFormat('dd/MM/yyyy').format(_dates!.start)} – ${DateFormat('dd/MM/yyyy').format(_dates!.end)}',
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : _pickUsers,
                        child: Text(
                          _users.isEmpty
                              ? 'All users'
                              : '${_users.length} users',
                        ),
                      ),
                      _filter('Event', _action, [
                        'insert',
                        'update',
                        'delete',
                        'cancelled',
                        'rescheduled',
                        'published',
                        'publication withdrawn',
                        'archived',
                        'restored',
                        'started',
                        'finished',
                        'export requested',
                      ], (v) => _action = v),
                      _filter('Record type', _type, [
                        'fixtures',
                        'teams',
                        'team_members',
                        'team_selections',
                        'team_selection_members',
                        'fixture_rink_assignments',
                        'club_memberships',
                        'member_profiles',
                        'app_superusers',
                        'clubs',
                        'club_schedule_items',
                        'member_invitation_attempts',
                        'email_queue',
                        'feature_revision_policy',
                        'member_import',
                        'audit_journal',
                      ], (v) => _type = v),
                      _filter('Origin', _origin, [
                        'app',
                        'service',
                        'import',
                        'database maintenance',
                      ], (v) => _origin = v),
                      _filter('Outcome', _outcome, [
                        'completed',
                        'failed',
                        'started',
                        'completed with errors',
                      ], (v) => _outcome = v),
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: _search,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: 'Search fixture, team or member',
                          ),
                          onSubmitted: (_) => _load(),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() {
                                  _club = null;
                                  _dates = null;
                                  _users.clear();
                                  _action = null;
                                  _type = null;
                                  _origin = null;
                                  _outcome = null;
                                  _recordId = null;
                                  _search.clear();
                                });
                                _load();
                              },
                        child: const Text('Clear filters'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        if (_recordId != null) Text('History for $_recordId'),
        if (_busy) const LinearProgressIndicator(),
        if (!_busy && _rows.isEmpty && _error == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No entries for these filters. History starts when the audit update is installed.',
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _rows.length,
            itemBuilder: (context, i) {
              final r = _rows[i];
              return Card(
                child: ListTile(
                  title: Text(
                    '${r['action']} — ${formatAuditRecordLabel(r['record_label'].toString())}',
                  ),
                  subtitle: Text(
                    '${r['actor_name']}\nAction date and time: ${formatAuditTimestamp(r['occurred_at'].toString())}\n${r['club_name'] ?? 'Global / unassigned'} • ${r['record_type']}',
                  ),
                  isThreeLine: true,
                  onTap: () => _details(r),
                ),
              );
            },
          ),
        ),
        if (_more)
          TextButton(
            onPressed: _busy ? null : () => _load(next: true),
            child: const Text('Load next 100'),
          ),
        TextButton(
          onPressed: _busy || _rows.isEmpty
              ? null
              : () async {
                  try {
                    await _copyLoaded();
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(
                          content: Text('Export failed. Please retry.'),
                        ),
                      );
                    }
                  }
                },
          child: const Text('Copy loaded entries as CSV'),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${_rows.length} entries loaded • Times shown in UK time',
          ),
        ),
      ],
    ),
  );
}
