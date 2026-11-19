import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/core/widgets/club_member_picker_page.dart';
import 'package:bowls_saas/features/competitions/competition_repository.dart';
import 'package:bowls_saas/features/competitions/screens/competition_season_screen.dart';
import 'package:bowls_saas/features/competitions/screens/competition_replace_player_screen.dart';
import 'competition_player_result_screen_test.dart' show ResultRepository;

class ReplacementRepository extends ResultRepository {
  Map<String, dynamic>? saved;
  @override
  Future<List<CompetitionRow>> entryHandicaps(String id) async => [
    {
      'member_profile_id': 'two',
      'individual_handicap': 12,
      'member': {'first_name': 'Partner', 'last_name': ''},
    },
    {
      'member_profile_id': 'one',
      'individual_handicap': 12,
      'member': {'first_name': 'Alex', 'last_name': ''},
    },
  ];
  @override
  Future<CompetitionRow> replacePlayer({
    required CompetitionRow entry,
    required List<String> expectedMembers,
    required String outgoingId,
    required String incomingId,
    required int? handicap,
    required String reason,
  }) async {
    saved = {
      'entry': entry['id'],
      'members': expectedMembers,
      'outgoing': outgoingId,
      'incoming': incomingId,
      'handicap': handicap,
      'reason': reason,
    };
    return {'entry_id': entry['id'], 'emails_queued': 3, 'fixtures_updated': 0};
  }
}

void main() {
  test(
    'Entry replacement guards preserve played histories, including walkovers',
    () {
      final repo = ReplacementRepository();
      expect(competitionEntryCanReplace(repo.data, 'a'), isTrue);
      repo.data.matches.first['status'] = 'bye';
      expect(competitionEntryCanReplace(repo.data, 'a'), isTrue);
      for (final status in ['completed', 'result_pending']) {
        repo.data.matches.first['status'] = status;
        expect(competitionEntryCanReplace(repo.data, 'a'), isFalse);
      }
      repo.data.matches.first.addAll({
        'status': 'to_be_arranged',
        'score_a': 1,
      });
      expect(competitionEntryCanReplace(repo.data, 'a'), isFalse);
    },
  );
  for (final confirm in [true, false]) {
    testWidgets(
      'Replacement reviews partner order, handicap, exclusion and explicit confirmation: $confirm',
      (t) async {
        final repo = ReplacementRepository();
        repo.data.competition['settings']['handicap_mode'] = 'team_difference';
        repo.data.entries.first['handicap'] = 24;
        final data = CompetitionData(
          repo.data.competition,
          repo.data.entries,
          repo.data.rounds,
          repo.data.matches,
          {'one', 'two', 'opponent'},
        );
        Set<String>? exclusions;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CompetitionReplacePlayerScreen(
                        data: data,
                        entry: data.entries.first,
                        repository: repo,
                        playerPicker: (_, ids) async {
                          exclusions = ids;
                          return const ClubMemberPickerMember(
                            memberProfileId: 'new',
                            displayName: 'Right Member',
                          );
                        },
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('Open'));
        await t.pumpAndSettle();
        await t.tap(find.byType(DropdownButtonFormField<String>));
        await t.pumpAndSettle();
        await t.tap(find.text('Alex').last);
        await t.pumpAndSettle();
        await t.tap(find.text('Choose replacement player'));
        await t.pumpAndSettle();
        await t.enterText(find.byType(TextField).first, '2');
        await t.enterText(find.byType(TextField).last, 'Wrong player selected');
        await t.ensureVisible(find.text('Review replacement'));
        await t.tap(find.text('Review replacement'));
        await t.pumpAndSettle();
        expect(find.textContaining('Right Member / Partner'), findsOneWidget);
        expect(
          find.textContaining('New combined handicap: 14'),
          findsOneWidget,
        );
        expect(repo.saved, isNull);
        expect(exclusions, {'one', 'two', 'opponent'});
        await t.tap(find.text(confirm ? 'Replace player' : 'Cancel'));
        await t.pumpAndSettle();
        if (confirm) {
          expect(repo.saved?['members'], ['one', 'two']);
          expect(repo.saved?['outgoing'], 'one');
          expect(repo.saved?['incoming'], 'new');
          expect(repo.saved?['handicap'], 2);
        } else {
          expect(repo.saved, isNull);
        }
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  for (final admin in [true, false]) {
    testWidgets('Replace action is Admin-only in competition entries: $admin', (
      t,
    ) async {
      final repo = ReplacementRepository();
      await t.pumpWidget(
        MaterialApp(
          home: CompetitionSeasonScreen(
            clubId: 'club',
            competitionId: 'c',
            canManage: admin,
            repository: repo,
          ),
        ),
      );
      await t.pumpAndSettle();
      if (admin) await t.tap(find.text('Entries'));
      await t.pumpAndSettle();
      expect(
        find.text('Replace player'),
        admin ? findsNWidgets(2) : findsNothing,
      );
      await t.pumpWidget(const SizedBox());
    });
  }
}
