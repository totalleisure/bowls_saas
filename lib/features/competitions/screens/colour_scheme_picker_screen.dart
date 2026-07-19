import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/competition_type.dart';
import '../widgets/competition_type_colour_chip.dart';

class ColourSchemePickerScreen extends StatefulWidget {
  final String? initialSelectedId;
  final String previewText;

  const ColourSchemePickerScreen({
    super.key,
    this.initialSelectedId,
    required this.previewText,
  });

  @override
  State<ColourSchemePickerScreen> createState() =>
      _ColourSchemePickerScreenState();
}

class _ColourSchemePickerScreenState extends State<ColourSchemePickerScreen> {
  final _client = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<ColourScheme> _rows = [];

  String _sectionForSortOrder(int? sortOrder) {
    final n = sortOrder ?? 9999;

    if (n >= 100 && n < 200) return 'Ocean & Sky';
    if (n >= 200 && n < 300) return 'Greens';
    if (n >= 300 && n < 400) return 'Warm tones';
    if (n >= 400 && n < 500) return 'Purples & Pinks';
    if (n >= 500 && n < 600) return 'Classic club colours';
    if (n >= 600 && n < 700) return 'High contrast & neutrals';

    return 'Other colours';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await _client
          .from('fixture_colour_schemes')
          .select('id, name, background_hex, foreground_hex, sort_order')
          .eq('is_active', true)
          .order('sort_order', ascending: true)
          .order('name', ascending: true);

      final rows = (res as List)
          .map((e) => ColourScheme.fromMap(Map<String, dynamic>.from(e)))
          .toList();

      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.previewText.trim().isEmpty
        ? 'Example Name'
        : widget.previewText;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose colours'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : _rows.isEmpty
          ? const Center(child: Text('No colour schemes found'))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final sectionName in [
                  'Ocean & Sky',
                  'Greens',
                  'Warm tones',
                  'Purples & Pinks',
                  'Classic club colours',
                  'High contrast & neutrals',
                  'Other colours',
                ]) ...[
                  Builder(
                    builder: (context) {
                      final sectionRows = _rows
                          .where(
                            (r) =>
                                _sectionForSortOrder(r.sortOrder) ==
                                sectionName,
                          )
                          .toList();

                      if (sectionRows.isEmpty) {
                        return const SizedBox.shrink();
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                            child: Text(
                              sectionName,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: sectionRows.length,
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 190,
                                  mainAxisExtent: 104,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                ),
                            itemBuilder: (context, index) {
                              final row = sectionRows[index];
                              final selected =
                                  row.id == widget.initialSelectedId;

                              return InkWell(
                                onTap: () => Navigator.of(context).pop(row),
                                borderRadius: BorderRadius.circular(12),
                                child: Card(
                                  margin: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: selected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : Colors.black12,
                                      width: selected ? 2 : 1,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          row.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Expanded(
                                          child: CompetitionTypeColourChip(
                                            text: preview,
                                            backgroundHex: row.backgroundHex,
                                            foregroundHex: row.foregroundHex,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
    );
  }
}
