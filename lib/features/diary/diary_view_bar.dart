import 'package:flutter/material.dart';
import 'month_overview_screen.dart';
import 'diary_list_screen.dart';
import 'diary_day_screen.dart';
import 'rinks_day_view.dart';

enum DiaryView { month, list, day, rinks }

class DiaryViewBar extends StatelessWidget implements PreferredSizeWidget {
  final DiaryView selected;
  final String clubId;
  final String clubName;
  final DateTime date;
  const DiaryViewBar({
    super.key,
    required this.selected,
    required this.clubId,
    required this.clubName,
    required this.date,
  });
  @override
  Size get preferredSize => const Size.fromHeight(48);
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SegmentedButton<DiaryView>(
          segments: const [
            ButtonSegment(value: DiaryView.month, label: Text('Month')),
            ButtonSegment(value: DiaryView.list, label: Text('List')),
            ButtonSegment(value: DiaryView.day, label: Text('Day')),
            ButtonSegment(value: DiaryView.rinks, label: Text('Rinks')),
          ],
          selected: {selected},
          onSelectionChanged: (selection) {
            final next = selection.single;
            if (next == selected) return;
            final Widget screen = switch (next) {
              DiaryView.month => MonthOverviewScreen(
                clubId: clubId,
                clubName: clubName,
                initialDate: date,
              ),
              DiaryView.list => DiaryListScreen(
                clubId: clubId,
                clubName: clubName,
                initialDate: date,
              ),
              DiaryView.day => DiaryDayScreen(
                clubId: clubId,
                clubName: clubName,
                date: date,
              ),
              DiaryView.rinks => RinkDayViewScreen(
                clubId: clubId,
                clubName: clubName,
                date: date,
              ),
            };
            Navigator.of(
              context,
            ).pushReplacement(MaterialPageRoute<void>(builder: (_) => screen));
          },
        ),
      ),
    ),
  );
}
