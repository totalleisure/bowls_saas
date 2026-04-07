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
    final preview =
        widget.previewText.trim().isEmpty ? 'Example Name' : widget.previewText;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose colours'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error'))
              : _rows.isEmpty
                  ? const Center(child: Text('No colour schemes found'))
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _rows.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisExtent: 125,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                      ),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        final selected = row.id == widget.initialSelectedId;

                        return InkWell(
                          onTap: () => Navigator.of(context).pop(row),
                          borderRadius: BorderRadius.circular(12),
                          child: Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: selected
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.black12,
                                width: selected ? 2 : 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    row.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  CompetitionTypeColourChip(
                                    text: preview,
                                    backgroundHex: row.backgroundHex,
                                    foregroundHex: row.foregroundHex,
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${row.backgroundHex} / ${row.foregroundHex}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}