import 'dart:typed_data';

import 'package:bowls_saas/core/utils/date_format.dart';
import 'package:bowls_saas/services/team_sheet_builder_service.dart';
import 'package:bowls_saas/services/team_sheet_pdf.dart';
import 'package:bowls_saas/services/team_sheet_share.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TeamSheetScreen extends StatefulWidget {
  const TeamSheetScreen({
    super.key,
    required this.fixtureId,
    this.hasUnconfirmedChanges = false,
    this.dataSource,
  });

  final String fixtureId;
  final bool hasUnconfirmedChanges;
  final TeamSheetDataSource? dataSource;

  @override
  State<TeamSheetScreen> createState() => _TeamSheetScreenState();
}

class _TeamSheetScreenState extends State<TeamSheetScreen> {
  TeamSheetBuildResult? _result;
  Uint8List? _pdfBytes;
  bool _loading = true;
  bool _canManage = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _result = null;
        _pdfBytes = null;
        _canManage = false;
      });
    }

    try {
      final source =
          widget.dataSource ??
          TeamSheetBuilderService(Supabase.instance.client);
      final result = await source.buildForFixture(widget.fixtureId);

      final bytes = await buildTeamSheetPdf(result.data);
      if (!mounted) return;
      setState(() {
        _result = result;
        _pdfBytes = bytes;
        _canManage = result.canManage;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
        _result = null;
        _pdfBytes = null;
        _canManage = false;
      });
    }
  }

  String _filename() {
    final data = _result!.data;
    final date = toClubTime(data.startAt);
    final when =
        '${date.day.toString().padLeft(2, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-${date.year}';
    final club = data.clubName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '-');
    final opponent = data.opponentName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '-');
    return '$club v $opponent - $when - revision '
        '${_result!.compositionVersion}.pdf';
  }

  Future<void> _saveOrShare() async {
    final data = _result?.data;
    final bytes = _pdfBytes;
    if (data == null || bytes == null) return;
    try {
      final path = await shareTeamSheetPdf(
        bytes,
        message: '${data.clubName} v ${data.opponentName}',
        filename: _filename(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Team sheet saved: $path')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save/share failed: $error')));
    }
  }

  Future<void> _print() async {
    final bytes = _pdfBytes;
    if (bytes == null) return;
    await Printing.layoutPdf(name: _filename(), onLayout: (_) async => bytes);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final bytes = _pdfBytes;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          result == null
              ? 'Team Sheet'
              : 'Team Sheet - revision ${result.compositionVersion}',
        ),
        actions: [
          IconButton(
            key: const Key('team_sheet_refresh_action'),
            tooltip: 'Refresh authoritative team sheet',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          if (_canManage && bytes != null)
            IconButton(
              key: const Key('team_sheet_share_action'),
              tooltip: 'Save or share PDF',
              onPressed: _saveOrShare,
              icon: const Icon(Icons.ios_share),
            ),
          if (_canManage && bytes != null)
            IconButton(
              key: const Key('team_sheet_print_action'),
              tooltip: 'Print Team Sheet',
              onPressed: _print,
              icon: const Icon(Icons.print),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : Column(
              children: [
                if (widget.hasUnconfirmedChanges)
                  const MaterialBanner(
                    content: Text(
                      'Unconfirmed local changes are not included. This is '
                      'the current authoritative saved team sheet.',
                    ),
                    actions: [SizedBox.shrink()],
                  ),
                Expanded(
                  child: PdfPreview(
                    build: (_) async => bytes!,
                    pdfFileName: _filename(),
                    allowPrinting: _canManage,
                    allowSharing: _canManage,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                  ),
                ),
              ],
            ),
    );
  }
}
