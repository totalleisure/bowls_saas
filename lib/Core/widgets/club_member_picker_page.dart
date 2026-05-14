import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum MemberPickerSectionFilter { mens, ladies, mixed, open }

class ClubMemberPickerMember {
  final String memberProfileId;
  final String displayName;
  final String? emailAddress;
  final String? phone;
  final String? sexAtBirth;
  final String? preferredPosition;

  const ClubMemberPickerMember({
    required this.memberProfileId,
    required this.displayName,
    this.emailAddress,
    this.phone,
    this.sexAtBirth,
    this.preferredPosition,
  });

  factory ClubMemberPickerMember.fromMap(Map<String, dynamic> map) {
    return ClubMemberPickerMember(
      memberProfileId: map['member_profile_id'].toString(),
      displayName:
          (map['picker_name'] ?? map['display_name'] ?? 'Unnamed member')
              .toString(),
      emailAddress: map['email_address']?.toString(),
      phone: map['phone']?.toString(),
      sexAtBirth: map['sex_at_birth']?.toString(),
      preferredPosition: map['preferred_position']?.toString(),
    );
  }
}

class ClubMemberPickerPage extends StatefulWidget {
  final String clubId;
  final String title;

  /// If true, the RPC derives the filter from fixtures.section when fixtureId is supplied.
  /// Use true for fixture players.
  /// Use false for marker/booker/captain/vice/etc when the picker should be open.
  final bool useFixtureSection;

  final String? fixtureId;
  final String? teamId;
  final List<String>? rsvpStatusFilter;

  final MemberPickerSectionFilter initialSectionFilter;

  final bool allowMultiple;
  final Set<String> initialSelectedIds;
  final Set<String> excludeMemberProfileIds;

  const ClubMemberPickerPage({
    super.key,
    required this.clubId,
    required this.title,
    this.useFixtureSection = true,
    this.fixtureId,
    this.teamId,
    this.rsvpStatusFilter,
    this.initialSectionFilter = MemberPickerSectionFilter.open,
    this.allowMultiple = false,
    this.initialSelectedIds = const {},
    this.excludeMemberProfileIds = const {},
  });

  @override
  State<ClubMemberPickerPage> createState() => _ClubMemberPickerPageState();
}

class _ClubMemberPickerPageState extends State<ClubMemberPickerPage> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  Timer? _debounce;

  bool _loading = true;
  String? _error;

  late MemberPickerSectionFilter _section;
  late Set<String> _selectedIds;

  List<ClubMemberPickerMember> _members = [];

  String _memberDisplayTitle(ClubMemberPickerMember member) {
    final preferred = (member.preferredPosition ?? '').trim();

    if (preferred.isEmpty) return member.displayName;

    return '${member.displayName} ($preferred)';
  }

  @override
  void initState() {
    super.initState();
    _section = widget.initialSectionFilter;
    _selectedIds = {...widget.initialSelectedIds};
    _loadMembers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String get _sectionValue {
    switch (_section) {
      case MemberPickerSectionFilter.mens:
        return 'mens';
      case MemberPickerSectionFilter.ladies:
        return 'ladies';
      case MemberPickerSectionFilter.mixed:
        return 'mixed';
      case MemberPickerSectionFilter.open:
        return 'open';
    }
  }

  String _sectionLabel(MemberPickerSectionFilter section) {
    switch (section) {
      case MemberPickerSectionFilter.mens:
        return 'Men';
      case MemberPickerSectionFilter.ladies:
        return 'Ladies';
      case MemberPickerSectionFilter.mixed:
        return 'Mixed';
      case MemberPickerSectionFilter.open:
        return 'Open';
    }
  }

  Future<void> _loadMembers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await _supabase.rpc(
        'get_club_member_picker_list',
        params: {
          'p_club_id': widget.clubId,
          'p_section': _sectionValue,
          'p_team_id': widget.teamId,
          'p_fixture_id': widget.fixtureId,
          'p_rsvp_statuses': widget.rsvpStatusFilter,
          'p_search': _searchController.text.trim(),
          'p_use_fixture_section': widget.useFixtureSection,
        },
      );

      final loaded = (rows as List)
          .map((row) => ClubMemberPickerMember.fromMap(row))
          .where(
            (member) => !widget.excludeMemberProfileIds.contains(
              member.memberProfileId,
            ),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        _members = loaded;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _loadMembers);
  }

  void _changeSection(MemberPickerSectionFilter section) {
    setState(() {
      _section = section;
    });
    _loadMembers();
  }

  void _toggleMember(String memberProfileId) {
    if (!widget.allowMultiple) {
      Navigator.of(context).pop(<String>[memberProfileId]);
      return;
    }

    setState(() {
      if (_selectedIds.contains(memberProfileId)) {
        _selectedIds.remove(memberProfileId);
      } else {
        _selectedIds.add(memberProfileId);
      }
    });
  }

  void _returnSelection() {
    Navigator.of(context).pop(_selectedIds.toList());
  }

  void _clearSelection() {
    Navigator.of(context).pop(<String>[]);
  }

  Widget _buildSectionToggle() {
    return SegmentedButton<MemberPickerSectionFilter>(
      segments: MemberPickerSectionFilter.values.map((section) {
        return ButtonSegment<MemberPickerSectionFilter>(
          value: section,
          label: Text(_sectionLabel(section)),
        );
      }).toList(),
      selected: {_section},
      onSelectionChanged: (selected) {
        _changeSection(selected.first);
      },
    );
  }

  Widget _buildList() {
    if (_members.isEmpty) {
      return const Center(child: Text('No members found.'));
    }

    return ListView.separated(
      itemCount: _members.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final member = _members[index];
        final selected = _selectedIds.contains(member.memberProfileId);

        return ListTile(
          onTap: () => _toggleMember(member.memberProfileId),
          leading: CircleAvatar(
            child: Text(
              member.displayName.isNotEmpty
                  ? member.displayName.characters.first.toUpperCase()
                  : '?',
            ),
          ),
          title: Text(_memberDisplayTitle(member)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((member.emailAddress ?? '').isNotEmpty)
                Text(member.emailAddress!),
              if ((member.phone ?? '').isNotEmpty) Text(member.phone!),
            ],
          ),
          trailing: Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: selected ? Theme.of(context).colorScheme.primary : null,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.initialSelectedIds.isNotEmpty)
            TextButton(onPressed: _clearSelection, child: const Text('Clear')),
          if (widget.allowMultiple)
            TextButton(
              onPressed: _returnSelection,
              child: const Text('Return'),
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/blank_bg_tablet_2.png', // change to your real background asset
              fit: BoxFit.cover,
              opacity: const AlwaysStoppedAnimation(0.16),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: _buildSectionToggle(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search members',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: _onSearchChanged,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                        ? Center(child: Text(_error!))
                        : _buildList(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(null),
                          child: const Text('Cancel'),
                        ),
                      ),
                      if (widget.initialSelectedIds.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _clearSelection,
                            icon: const Icon(Icons.clear),
                            label: const Text('Clear'),
                          ),
                        ),
                      ],
                      if (widget.allowMultiple) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _returnSelection,
                            icon: const Icon(Icons.check),
                            label: Text('Return ${_selectedIds.length}'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
