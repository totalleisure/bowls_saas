import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/utils/date_format.dart';
import 'club_dashboard_screen.dart';
import 'club_welcome_screen.dart';
import '../diary/month_overview_screen.dart';
import '../diary/diary_list_screen.dart';

enum ClubStartView { dashboard, month, list }

extension ClubStartViewLabel on ClubStartView {
  String get label => switch (this) {
    ClubStartView.dashboard => 'Dashboard',
    ClubStartView.month => 'Monthly Diary',
    ClubStartView.list => 'Diary List',
  };
  String get description => switch (this) {
    ClubStartView.dashboard =>
      'Your responses, accepted fixtures and responsibilities',
    ClubStartView.month => 'Club activity in a monthly calendar',
    ClubStartView.list => 'A scrolling list of club activity',
  };
}

class ClubStartPreference {
  static String key(String userId, String clubId) =>
      'club.start.v1.$userId.$clubId';

  /// Null means the member has not explicitly chosen a supported starting view.
  static Future<ClubStartView?> loadSaved(String userId, String clubId) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(key(userId, clubId));
    for (final view in ClubStartView.values) {
      if (view.name == value) return view;
    }
    return null;
  }

  // Retain the legacy fallback for callers needing a concrete view. Club entry
  // uses loadSaved to distinguish an explicit Dashboard choice from no choice.
  static Future<ClubStartView> load(String userId, String clubId) async =>
      await loadSaved(userId, clubId) ?? ClubStartView.dashboard;

  static Future<void> clear(String userId, String clubId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(key(userId, clubId))) {
      throw StateError(
        'Your starting screen could not be saved. Please try again.',
      );
    }
  }

  static Future<void> save(
    String userId,
    String clubId,
    ClubStartView view,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key(userId, clubId), view.name)) {
      throw StateError(
        'Your starting screen could not be saved. Please try again.',
      );
    }
  }
}

Widget clubStartPage(
  ClubStartView view,
  String clubId,
  String clubName, {
  DateTime? date,
}) {
  final today = date ?? toClubTime(DateTime.now());
  return switch (view) {
    ClubStartView.dashboard => ClubDashboardScreen(
      clubId: clubId,
      clubName: clubName,
    ),
    ClubStartView.month => MonthOverviewScreen(
      clubId: clubId,
      clubName: clubName,
      initialDate: today,
      showNextMatchOnOpen: true,
    ),
    ClubStartView.list => DiaryListScreen(
      clubId: clubId,
      clubName: clubName,
      initialDate: today,
      showNextMatchOnOpen: true,
    ),
  };
}

class ClubStartScreen extends StatefulWidget {
  final String clubId;
  final String clubName;
  final String userId;
  final Widget Function(ClubStartView)? pageBuilder;
  final bool showWelcome;
  const ClubStartScreen({
    super.key,
    required this.clubId,
    required this.clubName,
    required this.userId,
    this.pageBuilder,
    this.showWelcome = false,
  });
  @override
  State<ClubStartScreen> createState() => _ClubStartScreenState();
}

class _ClubStartScreenState extends State<ClubStartScreen> {
  late Future<ClubStartView?> _choice;
  @override
  void initState() {
    super.initState();
    _choice = _loadEntryChoice();
  }

  Future<ClubStartView?> _loadEntryChoice() async {
    final choice = await ClubStartPreference.loadSaved(
      widget.userId,
      widget.clubId,
    );
    if (choice == null) {
      // Show the introduction once, even if the member leaves without choosing.
      // Preserve the application's existing Dashboard fallback for later visits.
      await ClubStartPreference.save(
        widget.userId,
        widget.clubId,
        ClubStartView.dashboard,
      );
    }
    return choice;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ClubStartView?>(
    future: _choice,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          !snapshot.hasError) {
        if (widget.showWelcome || snapshot.data == null) {
          return ClubWelcomeScreen(
            userId: widget.userId,
            clubId: widget.clubId,
            clubName: widget.clubName,
            initialChoice: snapshot.data ?? ClubStartView.dashboard,
            onOpen: (view) => Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) =>
                    widget.pageBuilder?.call(view) ??
                    clubStartPage(view, widget.clubId, widget.clubName),
              ),
            ),
          );
        }
        return widget.pageBuilder?.call(snapshot.data!) ??
            clubStartPage(snapshot.data!, widget.clubId, widget.clubName);
      }
      return Scaffold(
        appBar: AppBar(title: Text(widget.clubName)),
        body: Center(
          child: snapshot.hasError
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Could not load your starting-screen preference.',
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _choice = _loadEntryChoice()),
                      child: const Text('Retry'),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}

Future<void> chooseClubStartView(
  BuildContext context,
  String clubId, {
  String? userId,
}) async {
  final id = userId ?? Supabase.instance.client.auth.currentUser?.id;
  if (id == null) return;
  try {
    final current = await ClubStartPreference.loadSaved(id, clubId);
    if (!context.mounted) return;
    final selected = await showDialog<ClubStartView>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Starting screen'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(
              'Choose what opens when you enter this club. Saved for your account on this device.',
            ),
          ),
          for (final view in ClubStartView.values)
            ListTile(
              leading: Icon(
                view == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              title: Text(view.label),
              subtitle: Text(view.description),
              onTap: () => Navigator.of(context).pop(view),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null) return;
    await ClubStartPreference.save(id, clubId, selected);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${selected.label} will open next time you enter this club.',
          ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Your starting screen could not be saved. Please try again.',
          ),
        ),
      );
    }
  }
}

Future<void> showClubWelcome(
  BuildContext context,
  String clubId,
  String clubName, {
  String? userId,
}) async {
  final id = userId ?? Supabase.instance.client.auth.currentUser?.id;
  if (id == null || !context.mounted) return;
  await Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      builder: (_) => ClubStartScreen(
        clubId: clubId,
        clubName: clubName,
        userId: id,
        showWelcome: true,
      ),
    ),
  );
}
