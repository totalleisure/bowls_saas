import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/widgets/communications_fixture_selector.dart';
import '../../services/fixture_communications_service.dart';
import '../../services/fixture_readiness_service.dart';
import '../fixtures/fixture_details_page.dart';

class CommunicationsControlCentreScreen extends StatefulWidget {
  const CommunicationsControlCentreScreen({super.key, required this.clubId});

  final String clubId;

  @override
  State<CommunicationsControlCentreScreen> createState() =>
      _CommunicationsControlCentreScreenState();
}

class _CommunicationsControlCentreScreenState
    extends State<CommunicationsControlCentreScreen> {
  bool _loadingHealth = false;
  bool _busyRepair = false;
  bool _busyRebuildTeamSheets = false;
  bool _busyContinuePreparation = false;
  bool _busySendEmails = false;
  bool _busyRetryFailedEmails = false;
  bool _loadingReadiness = false;

  String? _communicationsError;
  List<Map<String, dynamic>> _healthRows = [];
  List<Map<String, dynamic>> _detailRows = [];

  String? _selectedFixtureId;
  String? _selectedFixtureLabel;
  String? _selectedSelectionStatus;
  Map<String, dynamic>? _selectedFixtureRow;
  FixtureReadinessResult? _readiness;

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

  Map<String, dynamic>? _fixtureMap(Map<String, dynamic> row) {
    final fixture = row['fixtures'];
    if (fixture is Map<String, dynamic>) return fixture;
    if (fixture is Map) return Map<String, dynamic>.from(fixture);
    return null;
  }

  String? _teamSelectionId(Map<String, dynamic>? row) {
    final id = row?['id']?.toString();
    return id == null || id.isEmpty ? null : id;
  }

  Future<void> _refreshSelectedFixture() async {
    final row = _selectedFixtureRow;
    if (row != null) {
      await _loadHealthForFixture(row);
    }
  }

  Future<void> _loadHealthForFixture(Map<String, dynamic> row) async {
    final fixture = _fixtureMap(row);
    final fixtureId = fixture?['id']?.toString();
    if (fixtureId == null || fixtureId.isEmpty) return;

    final status = row['status']?.toString() ?? '';

    setState(() {
      _selectedFixtureId = fixtureId;
      _selectedFixtureLabel = _fixtureLabel(row);
      _selectedSelectionStatus = status;
      _selectedFixtureRow = row;
      _loadingReadiness = true;
      _loadingHealth = status == 'published';
      _readiness = null;
      _healthRows = [];
      _detailRows = [];
      _communicationsError = null;
    });

    try {
      final client = Supabase.instance.client;
      final readiness = await FixtureReadinessService(client).check(fixtureId);

      List<Map<String, dynamic>> healthRows = [];
      List<Map<String, dynamic>> detailRows = [];

      if (status == 'published') {
        final summaryResult = await client.rpc(
          'communications_health_check_v2',
          params: {'p_fixture_id': fixtureId},
        );

        final detailResult = await client.rpc(
          'communications_health_detail_v2',
          params: {'p_fixture_id': fixtureId},
        );

        healthRows = List<Map<String, dynamic>>.from(summaryResult as List);
        detailRows = List<Map<String, dynamic>>.from(detailResult as List);
      }

      if (!mounted) return;
      setState(() {
        _readiness = readiness;
        _healthRows = healthRows;
        _detailRows = detailRows;
        _loadingReadiness = false;
        _loadingHealth = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingReadiness = false;
        _loadingHealth = false;
        _communicationsError = e.toString();
      });
    }
  }

  Future<void> _repairSelectedFixtureCommunications() async {
    if (_selectedFixtureId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a published fixture first.')),
      );
      return;
    }

    if (_selectedSelectionStatus != 'published') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Communications can only be repaired after publication.',
          ),
        ),
      );
      return;
    }

    final isSuperuser = await _isSuperuser();
    if (!mounted) return;
    if (!isSuperuser) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Superuser access required.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Repair communications?'),
        content: Text(
          'This will add any missing publication communications and refresh '
          'eligible unsent Team Sheet attachments for:\n\n'
          '${_selectedFixtureLabel ?? 'the selected fixture'}\n\n'
          'It will not delete communication history, process a queue, send an '
          'email, or change the team selection itself.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Repair'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busyRepair = true);

    try {
      final selectedRow = _selectedFixtureRow;
      final fixture = selectedRow == null ? null : _fixtureMap(selectedRow);
      final teamSelectionId = _teamSelectionId(selectedRow);

      if (fixture == null || teamSelectionId == null) {
        throw Exception('The selected fixture is missing publication details.');
      }

      final service = FixtureCommunicationsService(Supabase.instance.client);

      final result = await service.repairPublicationCommunications(
        fixture: fixture,
        teamSelectionId: teamSelectionId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Communications reconciled; revision '
            '${result.attachmentResult.compositionVersion} attached to '
            '${result.attachmentResult.notificationRowsUpdated} pending '
            'notification(s) and '
            '${result.attachmentResult.emailRowsUpdated} unsent email(s).',
          ),
        ),
      );

      await _refreshSelectedFixture();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Repair failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _busyRepair = false);
      }
    }
  }

  Future<void> _rebuildSelectedFixtureTeamSheets() async {
    final selectedRow = _selectedFixtureRow;
    final fixture = selectedRow == null ? null : _fixtureMap(selectedRow);
    final teamSelectionId = _teamSelectionId(selectedRow);

    if (!_isSelectedPublished || fixture == null || teamSelectionId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a published fixture first.')),
      );
      return;
    }

    if (!await _isSuperuser()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Superuser access required.')),
      );
      return;
    }

    setState(() => _busyRebuildTeamSheets = true);

    try {
      final service = FixtureCommunicationsService(Supabase.instance.client);
      final attached = await service.rebuildTeamSheetAttachment(
        fixture: fixture,
        teamSelectionId: teamSelectionId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Revision ${attached.compositionVersion} attached to '
            '${attached.notificationRowsUpdated} pending notification(s) '
            'and ${attached.emailRowsUpdated} unsent email(s).',
          ),
        ),
      );
      await _refreshSelectedFixture();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Rebuild team sheets failed: $e')));
    } finally {
      if (mounted) setState(() => _busyRebuildTeamSheets = false);
    }
  }

  Map<String, dynamic>? _healthRow(String item) {
    final wanted = item.trim().toLowerCase();
    for (final row in _healthRows) {
      if ((row['item'] ?? '').toString().trim().toLowerCase() == wanted) {
        return row;
      }
    }
    return null;
  }

  int _expected(String item) {
    final value = _healthRow(item)?['expected'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _actual(String item) {
    final value = _healthRow(item)?['actual'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String get _nextStep {
    if (_selectedFixtureId == null) return 'select';
    if (_loadingReadiness || _readiness == null) return 'loading';

    switch (_readiness!.nextAction) {
      case 'open_fixture':
        return 'open_fixture';
      case 'repair_communications':
        return 'repair';
      case 'prepare_messages':
        return 'prepare';
      case 'prepare_team_sheets':
        return 'team_sheets';
      case 'retry_failed_emails':
        return 'failed';
      case 'send_emails':
        return 'send';
      case 'complete':
        return 'healthy';
      case 'none':
      default:
        return _isSelectedPublished ? 'healthy' : 'draft';
    }
  }

  String get _nextStepTitle {
    switch (_nextStep) {
      case 'open_fixture':
        return _isSelectedPublished
            ? 'Complete the fixture setup'
            : 'Fixture still being prepared';
      case 'draft':
        return 'No communications expected yet';
      case 'repair':
        return 'Repair required';
      case 'prepare':
        return 'Continue preparation';
      case 'team_sheets':
        return 'Prepare team sheets';
      case 'failed':
        return 'Some emails failed';
      case 'send':
        return 'Ready to send';
      case 'healthy':
        return _isSelectedPublished
            ? 'Communications complete'
            : 'Ready for publication';
      case 'loading':
        return 'Checking fixture';
      default:
        return 'Select a fixture';
    }
  }

  String get _nextStepInstruction {
    if (_readiness != null && _readiness!.message.trim().isNotEmpty) {
      return _readiness!.message;
    }

    if (_loadingReadiness) {
      return 'Please wait while the fixture is checked.';
    }

    return 'Choose a fixture from the list on the left.';
  }

  Color _nextStepColor(BuildContext context) {
    switch (_nextStep) {
      case 'healthy':
        return Colors.green;
      case 'send':
      case 'prepare':
      case 'team_sheets':
        return Colors.blue;
      case 'failed':
        return Colors.red;
      case 'repair':
      case 'open_fixture':
        return Colors.orange;
      case 'draft':
        return Colors.blueGrey;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  IconData get _nextStepIcon {
    switch (_nextStep) {
      case 'healthy':
        return Icons.check_circle;
      case 'send':
        return Icons.send;
      case 'prepare':
        return Icons.hourglass_top;
      case 'team_sheets':
        return Icons.picture_as_pdf;
      case 'failed':
        return Icons.error;
      case 'repair':
        return Icons.handyman;
      case 'open_fixture':
        return Icons.edit_calendar_outlined;
      case 'draft':
        return Icons.info_outline;
      default:
        return Icons.help_outline;
    }
  }

  Future<void> _openSelectedFixture() async {
    final fixtureId = _selectedFixtureId;
    if (fixtureId == null || fixtureId.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FixtureDetailsPage(fixtureId: fixtureId),
      ),
    );

    if (!mounted) return;
    await _refreshSelectedFixture();
  }

  Future<void> _continuePreparation() async {
    final fixtureId = _selectedFixtureId;
    if (fixtureId == null) return;
    setState(() => _busyContinuePreparation = true);
    try {
      await Supabase.instance.client.rpc(
        'process_fixture_notification_queue',
        params: {'p_fixture_id': fixtureId},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Messages prepared.')));
      await _refreshSelectedFixture();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Preparation failed: $e')));
    } finally {
      if (mounted) setState(() => _busyContinuePreparation = false);
    }
  }

  Future<void> _sendPendingEmails() async {
    final fixtureId = _selectedFixtureId;
    if (fixtureId == null) return;
    setState(() => _busySendEmails = true);
    try {
      await _sendFixturePendingEmails(fixtureId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pending emails processed.')),
      );
      await _refreshSelectedFixture();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Email sending failed: $e')));
    } finally {
      if (mounted) setState(() => _busySendEmails = false);
    }
  }

  Future<void> _retryFailedEmails() async {
    final fixtureId = _selectedFixtureId;
    final selectionId = _teamSelectionId(_selectedFixtureRow);

    if (fixtureId == null || selectionId == null) return;

    setState(() => _busyRetryFailedEmails = true);
    try {
      await Supabase.instance.client.rpc(
        'retry_fixture_failed_emails',
        params: {'p_fixture_id': fixtureId},
      );
      await _sendFixturePendingEmails(fixtureId);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed emails retried.')));
      await _refreshSelectedFixture();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Retry failed: $e')));
    } finally {
      if (mounted) setState(() => _busyRetryFailedEmails = false);
    }
  }

  Future<int> _sendFixturePendingEmails(String fixtureId) async {
    final rows = await Supabase.instance.client
        .from('email_queue')
        .select('id')
        .eq('fixture_id', fixtureId)
        .eq('status', 'pending')
        .order('created_at');

    var sent = 0;
    for (final raw in List<Map<String, dynamic>>.from(rows)) {
      final id = raw['id']?.toString();
      if (id == null || id.isEmpty) continue;
      final response = await Supabase.instance.client.functions.invoke(
        'process-email-queue',
        body: {'email_queue_id': id},
      );
      final data = response.data;
      if (data is Map) {
        sent += int.tryParse(data['processed']?.toString() ?? '') ?? 0;
      }
    }
    return sent;
  }

  String _fixtureLabel(Map<String, dynamic> row) {
    final fixture = _fixtureMap(row);
    final teamName = fixture?['team_name']?.toString().trim();
    final startAt = fixture?['start_at']?.toString();

    final dateText = _formatDateTime(startAt);
    final name = teamName == null || teamName.isEmpty
        ? 'Unnamed fixture'
        : teamName;
    return dateText.isEmpty ? name : '$dateText — $name';
  }

  String _formatDateTime(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yyyy = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }

  bool get _fixtureNeedsCorrection => _readiness?.nextAction == 'open_fixture';

  bool get _isSelectedPublished => _selectedSelectionStatus == 'published';

  int get _checkCount => _healthRows
      .where(
        (row) =>
            _displayStateForRow(row) == 'attention' ||
            _displayStateForRow(row) == 'failed',
      )
      .length;

  String _overallHealthText() => _nextStepTitle;

  Color _overallHealthColor(BuildContext context) => _nextStepColor(context);

  Widget _buildControlCentreHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.support_agent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Communications Control Centre',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Check fixture communications and follow the recommended next step.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
    );
  }

  Widget _buildCommunicationsHealthCard() {
    final healthColor = _nextStepColor(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.health_and_safety),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Overview',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                if (_loadingHealth || _loadingReadiness)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_communicationsError != null) ...[
              Text(
                _communicationsError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 8),
            ],
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: healthColor.withValues(alpha: 0.6)),
                color: healthColor.withValues(alpha: 0.08),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_nextStepIcon, color: healthColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nextStepTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(_nextStepInstruction),
                        if (_readiness?.blockingIssues.isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          for (final issue in _readiness!.blockingIssues.take(
                            4,
                          ))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• '),
                                  Expanded(child: Text(issue)),
                                ],
                              ),
                            ),
                        ],
                        if (_selectedFixtureLabel != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            _selectedFixtureLabel!,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaintenanceCard() {
    final busy =
        _busyRepair ||
        _busyRebuildTeamSheets ||
        _busyContinuePreparation ||
        _busySendEmails ||
        _busyRetryFailedEmails;

    Widget? primaryAction;
    switch (_nextStep) {
      case 'open_fixture':
        primaryAction = FilledButton.icon(
          onPressed: busy ? null : _openSelectedFixture,
          icon: const Icon(Icons.edit_calendar_outlined),
          label: const Text('Open Fixture'),
        );
        break;
      case 'repair':
        primaryAction = FilledButton.icon(
          onPressed: busy ? null : _repairSelectedFixtureCommunications,
          icon: _busyRepair
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.handyman),
          label: Text(_busyRepair ? 'Repairing...' : 'Repair Communications'),
        );
        break;
      case 'prepare':
        primaryAction = FilledButton.icon(
          onPressed: busy ? null : _continuePreparation,
          icon: _busyContinuePreparation
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: Text(_busyContinuePreparation ? 'Preparing...' : 'Continue'),
        );
        break;
      case 'team_sheets':
        primaryAction = FilledButton.icon(
          onPressed: busy ? null : _rebuildSelectedFixtureTeamSheets,
          icon: _busyRebuildTeamSheets
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.picture_as_pdf),
          label: Text(
            _busyRebuildTeamSheets ? 'Preparing...' : 'Prepare Team Sheets',
          ),
        );
        break;
      case 'failed':
        primaryAction = FilledButton.icon(
          onPressed: busy ? null : _retryFailedEmails,
          icon: _busyRetryFailedEmails
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.restart_alt),
          label: Text(
            _busyRetryFailedEmails ? 'Retrying...' : 'Retry Failed Emails',
          ),
        );
        break;
      case 'send':
        primaryAction = FilledButton.icon(
          onPressed: busy ? null : _sendPendingEmails,
          icon: _busySendEmails
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          label: Text(_busySendEmails ? 'Sending...' : 'Send Emails'),
        );
        break;
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.build_circle_outlined),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'What to do next',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_nextStepInstruction),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (primaryAction != null) primaryAction,
                if (_readiness?.hasBlockingIssues == true &&
                    _nextStep != 'open_fixture')
                  OutlinedButton.icon(
                    onPressed: busy ? null : _openSelectedFixture,
                    icon: const Icon(Icons.edit_calendar_outlined),
                    label: const Text('Open Fixture'),
                  ),
                OutlinedButton.icon(
                  onPressed: _loadingHealth || _loadingReadiness || busy
                      ? null
                      : _refreshSelectedFixture,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check Again'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _displayStateForRow(Map<String, dynamic> row) {
    final item = (row['item'] ?? '').toString();
    final expected = row['expected'] is num
        ? (row['expected'] as num).toInt()
        : int.tryParse(row['expected']?.toString() ?? '') ?? 0;
    final actual = row['actual'] is num
        ? (row['actual'] as num).toInt()
        : int.tryParse(row['actual']?.toString() ?? '') ?? 0;

    if (item == 'Emails failed') {
      return actual > 0 ? 'failed' : 'ok';
    }

    if (actual >= expected) return 'ok';

    if (item == 'App notifications created' || item == 'Emails queued') {
      return _actual('Notifications queued') >=
              _expected('Notifications queued')
          ? 'pending'
          : 'attention';
    }

    if (item == 'Emails sent') {
      return _actual('Team sheets attached') >=
              _expected('Team sheets attached')
          ? 'pending'
          : 'waiting';
    }

    if (item == 'Team sheets sent') {
      return _actual('Team sheets attached') >=
              _expected('Team sheets attached')
          ? 'pending'
          : 'waiting';
    }

    if (item == 'Team sheets attached') return 'attention';

    return 'attention';
  }

  Widget _stateChip(String state) {
    late final Color color;
    late final IconData icon;
    late final String label;

    switch (state) {
      case 'ok':
        color = Colors.green;
        icon = Icons.check_circle;
        label = 'OK';
        break;
      case 'pending':
        color = Colors.blue;
        icon = Icons.schedule;
        label = 'PENDING';
        break;
      case 'waiting':
        color = Colors.blueGrey;
        icon = Icons.hourglass_empty;
        label = 'WAITING';
        break;
      case 'failed':
        color = Colors.red;
        icon = Icons.error;
        label = 'FAILED';
        break;
      default:
        color = Colors.orange;
        icon = Icons.warning_amber;
        label = 'ATTENTION';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }

  Widget _buildHealthSummaryTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Item')),
          DataColumn(label: Text('Expected'), numeric: true),
          DataColumn(label: Text('Actual'), numeric: true),
          DataColumn(label: Text('Status')),
        ],
        rows: _healthRows.map((row) {
          return DataRow(
            cells: [
              DataCell(Text(row['item']?.toString() ?? '')),
              DataCell(Text(row['expected']?.toString() ?? '')),
              DataCell(Text(row['actual']?.toString() ?? '')),
              DataCell(_stateChip(_displayStateForRow(row))),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRecipientDetailTable() {
    final playerCount = _detailRows
        .where((r) => r['category'] == 'Player')
        .length;
    final reserveCount = _detailRows
        .where((r) => r['category'] == 'Reserve')
        .length;
    final notSelectedCount = _detailRows
        .where((r) => r['category'] == 'Not Selected')
        .length;

    final pendingCount = _detailRows
        .where((r) => r['email_status'] == 'pending')
        .length;
    final sentCount = _detailRows
        .where((r) => r['email_status'] == 'sent')
        .length;
    final failedCount = _detailRows
        .where((r) => r['email_status'] == 'failed')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _miniStat('Players', playerCount),
            _miniStat('Reserves', reserveCount),
            _miniStat('Not Selected', notSelectedCount),
            _miniStat('Pending', pendingCount),
            _miniStat('Sent', sentCount),
            _miniStat('Failed', failedCount),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('')),
              DataColumn(label: Text('Member')),
              DataColumn(label: Text('Role')),
              DataColumn(label: Text('Email')),
              DataColumn(label: Text('PDF')),
            ],
            rows: _detailRows.map((row) {
              final emailStatus = (row['email_status']?.toString() ?? 'Missing')
                  .toLowerCase();
              final appStatus =
                  row['app_notification']?.toString() ?? 'Missing';
              final sheetStatus = row['team_sheet']?.toString() ?? 'Missing';

              final appOk = appStatus == 'Created';
              final sheetOk =
                  sheetStatus == 'Attached' || sheetStatus == 'Not Required';

              final bool failed = emailStatus == 'failed';
              final bool pending = emailStatus == 'pending';
              final bool sent = emailStatus == 'sent';

              final overallIcon = failed
                  ? Icons.error
                  : (!appOk || !sheetOk)
                  ? Icons.warning_amber_rounded
                  : pending
                  ? Icons.schedule
                  : Icons.check_circle;

              final overallColor = failed
                  ? Colors.red
                  : (!appOk || !sheetOk)
                  ? Colors.orange
                  : pending
                  ? Colors.blue
                  : Colors.green;

              return DataRow(
                cells: [
                  DataCell(Icon(overallIcon, color: overallColor)),
                  DataCell(Text(row['member_name']?.toString() ?? 'Unknown')),
                  DataCell(Text(row['category']?.toString() ?? '')),
                  DataCell(
                    _recipientEmailState(
                      emailStatus,
                      sent: sent,
                      pending: pending,
                      failed: failed,
                    ),
                  ),
                  DataCell(
                    sheetStatus == 'Not Required'
                        ? const Text('—')
                        : Icon(
                            sheetOk
                                ? Icons.picture_as_pdf
                                : Icons.warning_amber_rounded,
                            color: sheetOk ? Colors.green : Colors.orange,
                          ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _recipientEmailState(
    String status, {
    required bool sent,
    required bool pending,
    required bool failed,
  }) {
    final Color color;
    final IconData icon;
    final String label;

    if (sent) {
      color = Colors.green;
      icon = Icons.check_circle;
      label = 'Sent';
    } else if (pending) {
      color = Colors.blue;
      icon = Icons.schedule;
      label = 'Pending';
    } else if (failed) {
      color = Colors.red;
      icon = Icons.error;
      label = 'Failed';
    } else {
      color = Colors.orange;
      icon = Icons.warning_amber;
      label = status.isEmpty ? 'Missing' : status;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Text(label),
      ],
    );
  }

  Widget _miniStat(String label, int value) {
    return Chip(
      avatar: CircleAvatar(
        radius: 10,
        child: Text(value.toString(), style: const TextStyle(fontSize: 11)),
      ),
      label: Text(label),
    );
  }

  Widget _statusChip(String text, {required bool ok}) {
    final color = ok ? Colors.green : Colors.orange;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.warning_amber,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(text),
      ],
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
            title: const Text('Communications Control Centre'),
            actions: [
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loadingHealth ? null : _refreshSelectedFixture,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: !allowed
              ? const Center(child: Text('Superuser access required.'))
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildControlCentreHeader(),
                      const SizedBox(height: 12),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 520,
                              child: Card(
                                margin: EdgeInsets.zero,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: CommunicationsFixtureSelector(
                                    clubId: widget.clubId,
                                    selectedFixtureId: _selectedFixtureId,
                                    onSelected: _loadHealthForFixture,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildSectionTitle(
                                      'Fixture communications',
                                    ),
                                    _buildCommunicationsHealthCard(),
                                    const SizedBox(height: 12),
                                    _buildMaintenanceCard(),
                                    if (_fixtureNeedsCorrection) ...[
                                      const SizedBox(height: 12),
                                      const Card(
                                        child: Padding(
                                          padding: EdgeInsets.all(12),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.info_outline),
                                              SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  'Communication totals are hidden until the fixture setup has been corrected. Open the fixture, make the requested changes, then select Check Again.',
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                    if (_isSelectedPublished &&
                                        !_fixtureNeedsCorrection &&
                                        _healthRows.isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Health summary',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _buildHealthSummaryTable(),
                                    ],
                                    if (_isSelectedPublished &&
                                        !_fixtureNeedsCorrection &&
                                        _detailRows.isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Recipients',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _buildRecipientDetailTable(),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}
