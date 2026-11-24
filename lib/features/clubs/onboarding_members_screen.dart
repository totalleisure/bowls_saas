import 'club_online_scaffold.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'onboarding_member_import.dart';
import 'onboarding_member_recognition.dart';

class OnboardingMembersScreen extends StatefulWidget {
  const OnboardingMembersScreen({
    super.key,
    required this.initial,
    required this.onSave,
    this.rehearsal = true,
    this.pickMemberFile,
    this.memberLookup,
  });
  final List<OnboardingMember> initial;
  final ValueChanged<List<OnboardingMember>> onSave;
  final bool rehearsal;
  final OnboardingMemberLookup? memberLookup;
  final Future<FilePickerResult?> Function()? pickMemberFile;
  @override
  State<OnboardingMembersScreen> createState() =>
      _OnboardingMembersScreenState();
}

class _OnboardingMembersScreenState extends State<OnboardingMembersScreen> {
  late List<OnboardingMember> _members = [...widget.initial];
  final _paste = TextEditingController();
  final _pasteKey = GlobalKey();
  final _pasteFocus = FocusNode();
  List<List<String>>? _fileRows;
  List<MemberImportRow>? _review;
  final _selected = <int>{};
  bool _busy = false;
  int _pasteRevision = 0;
  int _lookupVersion = 0;
  bool _matching = false;
  bool _matchFailed = false;
  Map<int, Map<String, dynamic>> _matches = {};
  List<Map<String, dynamic>> _knownMatches = [];

  @override
  void initState() {
    super.initState();
    _loadKnownMatches();
  }

  Future<void> _loadKnownMatches() async {
    if (widget.memberLookup == null) return;
    try {
      final result = await widget.memberLookup!(_members);
      if (mounted) setState(() => _knownMatches = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'Existing club memberships could not be checked. Please reopen this page to retry.',
        );
      }
    }
  }

  Future<void> _matchReview(List<MemberImportRow> review) async {
    final version = ++_lookupVersion;
    _matches = {};
    _matchFailed = false;
    if (widget.memberLookup == null) return;
    setState(() => _matching = true);
    try {
      final result = await widget.memberLookup!(
        review.map((r) => r.member).toList(),
      );
      if (!mounted || version != _lookupVersion) return;
      setState(() {
        _matches = {
          for (var i = 0; i < result.length; i++) review[i].row: result[i],
        };
        for (final row in review) {
          if (_matches[row.row]?['status'] == 'ambiguous') {
            _selected.remove(row.row);
          }
        }
      });
    } catch (_) {
      if (mounted && version == _lookupVersion) {
        setState(() {
          _matchFailed = true;
          _message =
              'Existing member checks failed. Review the list again before adding anyone.';
        });
      }
    } finally {
      if (mounted && version == _lookupVersion) {
        setState(() => _matching = false);
      }
    }
  }

  String? _message;
  String? _filename;
  @override
  void dispose() {
    _paste.dispose();
    _pasteFocus.dispose();
    super.dispose();
  }

  Future<void> _template() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final data = await rootBundle.load(
        'assets/templates/Club-member-template.xlsx',
      );
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save the member spreadsheet template',
        fileName: 'Club-member-template.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        bytes: bytes,
      );
      if (path != null && !kIsWeb) {
        await File(path).writeAsBytes(bytes, flush: true);
      }
      if (mounted && path != null) {
        setState(
          () => _message =
              'Template saved. Open it in your spreadsheet app, add members on the Members sheet, '
              'save it and choose Upload member spreadsheet.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'The template could not be saved. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final revision = _pasteRevision;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result =
          await (widget.pickMemberFile?.call() ??
              FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['xlsx', 'csv'],
                withData: true,
              ));
      if (!mounted || revision != _pasteRevision) return;
      if (result == null) {
        setState(
          () => _message =
              'File selection cancelled. You can paste member rows below or choose a file.',
        );
        return;
      }
      final file = result.files.single;
      final Uint8List bytes =
          file.bytes ??
          (throw const FormatException('The file could not be read.'));
      final rows = memberSpreadsheetRows(bytes, file.name);
      final review = reviewOnboardingMembers(rows, _members);
      if (!mounted) return;
      setState(() {
        _fileRows = rows;
        _filename = file.name;
        _review = review;
        _selected.clear();
        _selected.addAll(review.where((r) => r.canImport).map((r) => r.row));
        _message = 'Review the rows below. Nothing has been imported or sent.';
      });
      await _matchReview(review);
    } catch (e) {
      if (mounted && revision == _pasteRevision) {
        setState(() {
          _review = null;
          _message = e is FormatException
              ? e.message
              : 'The workbook could not be read. Use the supplied template.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reviewPaste() async {
    _pasteRevision++;
    try {
      final rows = memberDelimitedRows(_paste.text);
      final review = reviewOnboardingMembers(rows, _members);
      setState(() {
        _fileRows = rows;
        _filename = 'Pasted members';
        _review = review;
        _selected.clear();
        _selected.addAll(review.where((r) => r.canImport).map((r) => r.row));
        _message = 'Review the rows below. Nothing has been imported or sent.';
      });
      await _matchReview(review);
    } on FormatException catch (e) {
      setState(() {
        _review = null;
        _message = e.message;
      });
    }
  }

  void _import() {
    if (_review == null || _fileRows == null || _matching || _matchFailed) {
      return;
    }
    // Recheck against the current roster immediately before applying the selected rows.
    final fresh = reviewOnboardingMembers(_fileRows!, _members);
    final updated = applyReviewedMembers(_members, fresh, _selected);
    final count = updated.length - _members.length;
    widget.onSave(updated);
    _knownMatches = [];
    setState(() {
      _members = updated;
      _review = null;
      _selected.clear();
      _message =
          '$count member${count == 1 ? '' : 's'} added to ${widget.rehearsal ? 'this rehearsal' : 'your reviewed club list'}. '
          'No invitations were sent. Your Secretary’s membership and administrator role are unchanged.';
    });
    _loadKnownMatches();
  }

  bool _canSelect(MemberImportRow row) =>
      row.canImport && _matches[row.row]?['status'] != 'ambiguous';

  int get _selectedCount => _review == null
      ? 0
      : _review!
            .where((r) => _canSelect(r) && _selected.contains(r.row))
            .length;

  String get _addLabel =>
      'Add $_selectedCount selected ${_selectedCount == 1 ? 'person' : 'people'}';

  String _rowNote(MemberImportRow row) {
    final match = _matches[row.row];
    if (row.status == MemberImportStatus.existing) {
      return '${row.member.email}\nAlready added to this setup list. No duplicate will be added.';
    }
    return '${row.member.email}\n${row.canImport && match != null && row.member.email.isNotEmpty ? recognitionNote(match) : row.note}';
  }

  void _continueWithList() {
    if (_selectedCount > 0) {
      if (_matching || _matchFailed) return;
      _import();
    }
    Navigator.of(context).pop();
  }

  Future<void> _editSource() async {
    if (_filename != 'Pasted members') {
      await _upload();
      return;
    }
    final context = _pasteKey.currentContext;
    if (context != null) {
      await Scrollable.ensureVisible(
        context,
        alignment: 0.1,
        duration: const Duration(milliseconds: 250),
      );
      if (mounted) _pasteFocus.requestFocus();
    }
  }

  Widget _reviewRow(MemberImportRow row) {
    if (!_canSelect(row)) {
      final added = row.status == MemberImportStatus.existing;
      return ListTile(
        leading: Icon(
          added ? Icons.check_circle_outline : Icons.info_outline,
          color: added
              ? const Color(0xff256849)
              : Theme.of(context).colorScheme.error,
        ),
        title: Text('Row ${row.row}: ${row.member.name}'),
        subtitle: Text(
          _matches[row.row]?['status'] == 'ambiguous' && row.canImport
              ? '${row.member.email}\n${recognitionNote(_matches[row.row]!)}'
              : _rowNote(row),
        ),
      );
    }
    return CheckboxListTile(
      value: _selected.contains(row.row),
      onChanged: _matching || _matchFailed
          ? null
          : (yes) => setState(() {
              if (yes == true) {
                _selected.add(row.row);
              } else {
                _selected.remove(row.row);
              }
            }),
      title: Text('Row ${row.row}: ${row.member.name}'),
      subtitle: Text(_rowNote(row)),
    );
  }

  @override
  Widget build(BuildContext context) => ClubOnlineScaffold(
    appBar: AppBar(title: const Text('Your members')),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          icon: const Icon(Icons.check),
          onPressed: _selectedCount > 0 && (_matching || _matchFailed)
              ? null
              : _continueWithList,
          label: Text(
            _selectedCount > 0
                ? '$_addLabel and continue'
                : 'Continue with ${_members.length} ${_members.length == 1 ? 'person' : 'people'}',
          ),
        ),
      ),
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.rehearsal
                    ? 'STAGING REHEARSAL · Member changes stay in this temporary rehearsal.'
                    : 'Build the member list for your new club. You can add people now or return to this after setup.',
              ),
              const SizedBox(height: 12),
              Text(
                widget.rehearsal
                    ? 'Your Secretary is already the first active member and administrator. '
                          'Start with just that account, or add other members below. No passwords are needed.'
                    : 'The signed-in Secretary will become the first active member and administrator. '
                          'Everyone else starts inactive. People already known at other clubs join this club as Members; their other memberships stay unchanged.',
              ),
              const SizedBox(height: 12),
              Text(
                '${_members.length} ${_members.length == 1 ? 'person is' : 'people are'} already in this setup list, including the Secretary.',
              ),
              for (var mi = 0; mi < _members.length; mi++)
                ListTile(
                  leading: Icon(
                    _members[mi].role == 'admin'
                        ? Icons.admin_panel_settings_outlined
                        : Icons.person_outline,
                  ),
                  title: Text(_members[mi].name),
                  subtitle: Text(
                    '${_members[mi].email.isEmpty ? 'No email recorded' : _members[mi].email}\n'
                    '${_members[mi].role == 'admin' ? 'Secretary · Administrator · Active' : 'Member · Inactive · Not invited'}'
                    '${mi < _knownMatches.length && _knownMatches[mi]['status'] == 'matched' ? '\nAlready belongs to: ${recognisedClubs(_knownMatches[mi]['clubs'] as List?)}' : ''}',
                  ),
                ),
              const Divider(height: 30),
              Text(
                'Add your members',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _template,
                    icon: const Icon(Icons.download),
                    label: const Text('Save spreadsheet template'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _upload,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload member spreadsheet'),
                  ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'A file window is open. Choose a file or cancel that window. '
                    'You can also paste member rows below or continue without adding members.',
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'Or paste the four columns from Excel, including their headings: '
                'First name, Surname, Email, Telephone.',
              ),
              TextField(
                key: _pasteKey,
                focusNode: _pasteFocus,
                controller: _paste,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Paste member rows',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {
                  _pasteRevision++;
                  _lookupVersion++;
                  _matching = false;
                  _matches = {};
                  _review = null;
                  _selected.clear();
                }),
              ),
              OutlinedButton(
                onPressed: _reviewPaste,
                child: const Text('Review pasted members'),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_message!),
                ),
              if (_matching)
                const Text('Checking existing members and their clubs…'),
              if (_review != null) ...[
                Text(
                  'Review before importing',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '$_filename · ${_review!.length} non-empty rows · '
                  '$_selectedCount selected to add · '
                  '${_review!.where((r) => r.status == MemberImportStatus.existing).length} already added · '
                  '${_review!.where((r) => r.status != MemberImportStatus.existing && !_canSelect(r)).length} needing attention',
                ),
                if (_review!.every(
                  (r) => r.status == MemberImportStatus.existing,
                ))
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Everyone in this file is already in your setup list. There is nothing more to import. '
                      'Use Continue below to return to club setup.',
                    ),
                  )
                else if (_review!.any(_canSelect))
                  const Text(
                    'People who can be added are ticked for you. Untick anyone you do not want. '
                    'Green ticks mean the person is already in your setup list, so they will not be added twice.',
                  )
                else
                  const Text(
                    'No new people can be added from these rows yet. Each row below explains what needs checking.',
                  ),
                for (final row in _review!) _reviewRow(row),
                if (_review!.any(
                  (r) =>
                      r.status != MemberImportStatus.existing && !_canSelect(r),
                ))
                  TextButton(
                    onPressed: _editSource,
                    child: Text(
                      _filename == 'Pasted members'
                          ? 'Edit pasted list and review again'
                          : 'Choose a corrected spreadsheet',
                    ),
                  ),
                if (_matchFailed)
                  TextButton(
                    onPressed: () => _matchReview(_review!),
                    child: const Text('Retry member checks'),
                  ),
                if (_review!.any(_canSelect))
                  FilledButton(
                    onPressed: _selectedCount == 0 || _matching || _matchFailed
                        ? null
                        : _import,
                    child: Text(_addLabel),
                  ),
              ],
              const SizedBox(height: 20),
              Card(
                color: const Color(0xffeaf1fa),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.rehearsal
                        ? 'This is a rehearsal. No accounts are created and no emails are sent.'
                        : 'What happens next?\n\n'
                              'Finish setting up your club first. Only the Secretary will be active. '
                              'Everyone else stays inactive until they accept an invitation.\n\n'
                              'When you are ready, open Members → Invite inactive members in your new club. '
                              'You choose who to invite and when. Nothing is emailed from this setup screen.',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
