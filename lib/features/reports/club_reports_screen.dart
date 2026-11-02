import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../clubs/club_access.dart';
import 'club_report.dart';
import 'club_usage.dart';
import 'report_excel.dart';
import 'report_workbook_refresh.dart';

class ClubReportsScreen extends StatefulWidget {
  const ClubReportsScreen({super.key, required this.clubId, this.loader});
  final String clubId;
  final Future<ClubReport> Function(DateTime, DateTime)? loader;
  @override
  State<ClubReportsScreen> createState() => _ClubReportsScreenState();
}

class _ClubReportsScreenState extends State<ClubReportsScreen>
    with ClubScreenTracking<ClubReportsScreen> {
  @override
  String get usageClubId => widget.clubId;
  @override
  String get usageScreen => 'Reports';
  late DateTimeRange _period;
  ClubReport? _report;
  bool _busy = true, _exporting = false;
  String? _error;
  String _search = '';
  bool _guestsOnly = false;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _period = DateTimeRange(
      start: today.subtract(const Duration(days: 29)),
      end: today,
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      ClubReport result;
      if (widget.loader != null) {
        result = await widget.loader!(_period.start, _period.end);
      } else {
        final access = await loadClubAccess(clubId: widget.clubId);
        if (!access.isSuperuser && !access.isClubAdmin) {
          throw StateError('Club administrator access is required.');
        }
        result = await ClubReport.load(
          Supabase.instance.client,
          widget.clubId,
          _period.start,
          _period.end,
        );
      }
      if (mounted) {
        setState(() {
          _report = result;
          _busy = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _report = null;
          _error =
              'Unable to load reports. Club administrator access and a connection are required. Please retry.';
        });
      }
    }
  }

  Future<void> _dates() async {
    final chosen = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 3),
      initialDateRange: _period,
      helpText: 'Reporting period',
    );
    if (chosen != null && mounted) {
      setState(() => _period = chosen);
      await _load();
    }
  }

  Future<void> _export({bool refreshWorkbook = false}) async {
    if (_report == null || _exporting) return;
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _exporting = true);
    try {
      // Re-authorise at export time; do not export a stale privileged snapshot.
      final fresh = widget.loader != null
          ? await widget.loader!(_period.start, _period.end)
          : await ClubReport.load(
              Supabase.instance.client,
              widget.clubId,
              _period.start,
              _period.end,
            );
      Uint8List? workbookBytes;
      if (refreshWorkbook) {
        final chosen = await FilePicker.platform.pickFiles(
          dialogTitle: 'Choose the reconciled workbook to refresh',
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          withData: true,
        );
        if (chosen == null) return;
        workbookBytes = chosen.files.single.bytes;
        if (workbookBytes == null) {
          throw const FormatException(
            'The selected workbook could not be read.',
          );
        }
      }
      final bytes = workbookBytes == null
          ? buildReportExcel(fresh)
          : refreshReportWorkbook(workbookBytes, fresh);
      final filename =
          'Club-reports-${DateFormat('yyyy-MM-dd').format(_period.end)}${refreshWorkbook ? '-refreshed' : ''}.xlsx';
      if (kIsWeb ||
          Platform.isWindows ||
          Platform.isMacOS ||
          Platform.isLinux) {
        final path = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Club reports',
          fileName: filename,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
          bytes: bytes,
        );
        if (path != null && !kIsWeb) {
          await File(path).writeAsBytes(bytes, flush: true);
        }
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                mimeType:
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                name: filename,
              ),
            ],
            fileNameOverrides: [filename],
            sharePositionOrigin: origin,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException
                  ? error.message
                  : 'The Excel report could not be saved. Close the workbook or choose a different filename, and check your connection.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _metric(String label, Object? value) => SizedBox(
    width: 205,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(label),
          ],
        ),
      ),
    ),
  );

  Widget _table(List<String> headers, List<List<String>> rows) =>
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: headers.map((s) => DataColumn(label: Text(s))).toList(),
          rows: rows
              .map(
                (r) => DataRow(cells: r.map((s) => DataCell(Text(s))).toList()),
              )
              .toList(),
        ),
      );

  Widget _membership(ClubReport r) {
    final s = r.summary;
    final rows = r.members
        .where(
          (m) =>
              (!_guestsOnly || m['member_type'] == 'guest') &&
              '${m['surname']} ${m['forename']} ${m['email']}'
                  .toLowerCase()
                  .contains(_search.toLowerCase()),
        )
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metric('Active members', s['active_members']),
            _metric('Ever signed in (active)', s['ever_signed_in']),
            _metric('No recorded sign-in (active)', s['no_recorded_sign_in']),
            _metric('Inactive members', s['inactive_members']),
            _metric(
              'Recorded explicit starting views (active)',
              s['explicit_start_choices'] ?? 0,
            ),
            _metric('Active members without email', s['without_email']),
            _metric('Active members without telephone', s['without_phone']),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Member type shows the App role. Club subscription categories are not currently stored. The Excel export includes all members and contact details, regardless of this search.',
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: FilterChip(
            label: Text('Guest App role (${r.guestMembers.length})'),
            selected: _guestsOnly,
            onSelected: (v) => setState(() => _guestsOnly = v),
          ),
        ),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search members',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _search = v),
        ),
        const SizedBox(height: 12),
        ...rows.map(
          (m) => ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${m['surname']}, ${m['forename']}'),
            subtitle: Text(
              '${m['member_type']} · ${m['active'] == true ? 'Active' : 'Inactive'}\n${m['email']}',
            ),
            isThreeLine: true,
            trailing: Text(
              m['last_sign_in'] == null
                  ? 'No sign-in\nrecorded'
                  : 'Last sign-in\n${DateFormat('dd MMM yyyy').format(DateTime.parse(m['last_sign_in']).toLocal())}',
              textAlign: TextAlign.end,
            ),
          ),
        ),
        if (rows.isEmpty) const Text('No members match this search.'),
        const SizedBox(height: 16),
        const Text(
          'Starting views show future explicit choices recorded by this App. Earlier device settings and automatic defaults are not inferred. This is the latest recorded choice, not a historical snapshot for the selected date range.',
        ),
        _table(
          ['Member', 'Explicit starting view', 'Recorded (UTC)'],
          rows
              .map(
                (m) => [
                  '${m['surname']}, ${m['forename']}',
                  m['explicit_start_view']?.toString() ??
                      m['start_view_status']?.toString() ??
                      'Not recorded',
                  m['start_view_recorded_at']?.toString() ?? '',
                ],
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _bookings(ClubReport r) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Wrap(
        children: [
          _metric(
            'Bookings created during period',
            r.summary['bookings_created'],
          ),
          _metric(
            'Fixtures scheduled in period',
            r.bookings.fold<int>(
              0,
              (n, x) => n + (x['fixtures'] as num).toInt(),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      const Text(
        'The table uses fixture dates. Created bookings use the date the booking was entered. Cancelled and archived counts can overlap. Assigned fixtures in the member export are current team/rink assignments, not attendance.',
      ),
      _table(
        ['Fixture type', 'Scheduled', 'Cancelled', 'Archived', 'Current'],
        r.bookings
            .map(
              (x) => [
                '${x['fixture_type']}',
                '${x['fixtures']}',
                '${x['cancelled']}',
                '${x['archived']}',
                '${x['current_fixtures']}',
              ],
            )
            .toList(),
      ),
    ],
  );

  Widget _usage(ClubReport r) {
    final start = DateFormat(
      'dd MMM yyyy HH:mm',
    ).format(DateTime.parse(r.data['recording_started_at']).toLocal());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metric('Recorded logins', r.summary['recorded_logins']),
            _metric('Recorded App visits', r.summary['app_visits']),
            _metric('Recorded screen views', r.summary['screen_views']),
            _metric('Recorded unique App users', r.summary['active_app_users']),
            _metric(
              'Latest sign-in falls in period (active)',
              r.summary['last_sign_in_in_period'],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Recording starts $start. Earlier login counts and screen views are unavailable, rather than zero. Logins are account-wide across Clubs. App visits count once per Club/account per App process, including a saved session. Screen views include returning to a screen. Token refresh and ordinary widget rebuilds do not count as new visits.',
        ),
        const SizedBox(height: 12),
        const Text(
          'This App records visits and screen views. Older installed versions cannot send these figures. These are not download counts or time spent. No typed text is recorded. The latest sign-in date alone cannot prove all activity during a historical period.',
        ),
        _table(
          ['Screen', 'Platform', 'Views', 'Unique members'],
          r.screens
              .map(
                (x) => [
                  '${x['screen']}',
                  '${x['platform']}',
                  '${x['views']}',
                  '${x['members']}',
                ],
              )
              .toList(),
        ),
        if (r.screens.isEmpty)
          const Text('No screen views recorded for this period.'),
        const SizedBox(height: 20),
        Text('Top Users', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          r.hasRecordedUsage
              ? 'Highest screen views, then App visits and recorded logins. Latest sign-in breaks ties. Figures cover the selected reporting period.'
              : 'Usage ranking is not yet available. This interim list shows the most recent sign-ins first, not login frequency.',
        ),
        _table(
          ['Member', 'Screen views', 'App visits', 'Logins', 'Last sign-in'],
          r.topUsers
              .map(
                (m) => [
                  '${m['surname']}, ${m['forename']}',
                  '${m['screen_views'] ?? 0}',
                  '${m['app_visits'] ?? 0}',
                  '${m['recorded_logins'] ?? 0}',
                  m['last_sign_in'] == null
                      ? 'Not recorded'
                      : DateFormat(
                          'dd MMM yyyy HH:mm',
                        ).format(DateTime.parse(m['last_sign_in']).toLocal()),
                ],
              )
              .toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Club reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh existing reconciled workbook',
            onPressed: _busy || _exporting || _report == null
                ? null
                : () => _export(refreshWorkbook: true),
            icon: const Icon(Icons.find_replace),
          ),
          IconButton(
            tooltip: 'Refresh reports',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Download Excel report',
            onPressed: _busy || _exporting || _report == null ? null : _export,
            icon: const Icon(Icons.download),
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Membership'),
            Tab(text: 'Bookings'),
            Tab(text: 'App Usage'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _busy || _exporting ? null : _dates,
                icon: const Icon(Icons.date_range),
                label: Text(
                  '${DateFormat('dd MMM yyyy').format(_period.start)} – ${DateFormat('dd MMM yyyy').format(_period.end)}',
                ),
              ),
            ),
          ),
          if (_exporting) const LinearProgressIndicator(),
          Expanded(
            child: _busy
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : TabBarView(
                    children: [
                      _membership(_report!),
                      _bookings(_report!),
                      _usage(_report!),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );
}
