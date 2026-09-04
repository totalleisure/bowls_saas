import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const preparePath =
    'supabase/migrations/procedures/prepare_team_selection_email_action.sql';
const applyPath =
    'supabase/migrations/procedures/apply_email_action_response.sql';
const migrationPath =
    'supabase/migrations/20260904023419_enable_member_opponent_email_actions.sql';
const savePreselectPath =
    'supabase/migrations/procedures/save_preselect_fixture_state.sql';
const reconcilePreselectPath =
    'supabase/migrations/procedures/reconcile_preselect_communications.sql';
const reselectionMigrationPath =
    'supabase/migrations/20260904024708_reset_preselect_reselection_cycle.sql';
const correctiveMigrationPath =
    'supabase/migrations/20260904024935_correct_preselect_reselection_acceptance.sql';

String source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n').trim();

bool supportsSelectionAction(String role, int position, int playersPerRink) {
  if (role == 'player') return position >= 1 && position <= playersPerRink;
  if (role == 'opponent') {
    return position >= 101 && position <= 100 + playersPerRink;
  }
  return false;
}

void main() {
  test('member opponent receives a team-selection action block', () {
    final sql = source(preparePath);

    expect(sql, contains("tsm.role::text = 'opponent'"));
    expect(
      sql,
      contains('fra.position between 101 and (100 + fr.players_per_rink)'),
    );
    expect(sql, contains("then 'team_selection'"));
  });

  test('response handler validates player and member-opponent positions', () {
    final sql = source(applyPath);

    expect(sql, contains("tsm.role::text in ('player', 'opponent')"));
    expect(sql, contains('fra.position between 1 and fr.players_per_rink'));
    expect(
      sql,
      contains('fra.position between 101 and (100 + fr.players_per_rink)'),
    );
  });

  test('only valid player and opponent positions are actionable', () {
    expect(supportsSelectionAction('player', 1, 2), isTrue);
    expect(supportsSelectionAction('player', 101, 2), isFalse);
    expect(supportsSelectionAction('opponent', 101, 2), isTrue);
    expect(supportsSelectionAction('opponent', 102, 2), isTrue);
    expect(supportsSelectionAction('opponent', 103, 2), isFalse);
    expect(supportsSelectionAction('reserve', 101, 2), isFalse);
    expect(supportsSelectionAction('marker', 201, 2), isFalse);
  });

  test('migration contains the two canonical definitions exactly', () {
    final expected = '${source(preparePath)}\n\n${source(applyPath)}';
    expect(source(migrationPath), expected);
  });

  test('confirmed inactive-to-active transition resets response state', () {
    final sql = source(savePreselectPath);

    expect(sql, contains('when existing.is_selected = false'));
    expect(sql, contains("then 'pending'::acceptance_status"));
    expect(
      RegExp(
        r'existing\.is_selected = true[\s\S]*?existing\.role = excluded\.role[\s\S]*?then existing\.responded_at',
      ).hasMatch(sql),
      isTrue,
    );
    expect(
      RegExp(
        r'existing\.is_selected = true[\s\S]*?existing\.role = excluded\.role[\s\S]*?then existing\.acceptance_by',
      ).hasMatch(sql),
      isTrue,
    );
  });

  test('confirmed re-add bypasses only the historical notification guard', () {
    final save = source(savePreselectPath);
    final reconcile = source(reconcilePreselectPath);

    expect(save, contains("'app.preselect_reselected_member_ids'"));
    expect(
      reconcile,
      contains("current_setting('app.preselect_reselected_member_ids', true)"),
    );
    expect(reconcile, contains("nq.event_type = 'fixture_selected'"));
    expect(reconcile, contains('or not exists'));
  });

  test('reselection migration contains both canonical definitions exactly', () {
    final expected =
        '${source(savePreselectPath)}\n\n${source(reconcilePreselectPath)}';
    expect(source(reselectionMigrationPath), expected);
  });

  test('corrective migration contains the canonical save function exactly', () {
    expect(source(correctiveMigrationPath), source(savePreselectPath));
  });
}
