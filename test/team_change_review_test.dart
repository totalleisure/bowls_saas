import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/team/team_composition_staging.dart';

void main() {
  Map<String, dynamic> team(String id, int number) => {'id':id,'fixture_rink_no':number,'format':'triples','players_per_rink':3,'home_rink_label':'R$number'};
  final before = <String, dynamic>{
    'rinks':[team('a',1),team('b',2)],
    'members':[{'member_profile_id':'person','role':'player'}],
    'assignments':[{'member_profile_id':'person','fixture_rink_id':'b','position':1}],
  };
  for (final outcome in ['reserve','removed','reassigned']) {
    test('withdrawn team $outcome has exactly one final recipient', () {
      final after = <String,dynamic>{
        'rinks':[team('a',1)],
        'members': outcome=='removed' ? [] : [{'member_profile_id':'person','role':outcome=='reserve'?'reserve':'player'}],
        'assignments':outcome=='reassigned' ? [{'member_profile_id':'person','fixture_rink_id':'a','position':2}] : [],
      };
      final review=buildTeamChangeReview(before:before,after:after,names:{'person':'Wayne'});
      expect(review.recipients,1);
      expect(review.teams,['Team 2 withdrawn']);
      expect(review.players.single,contains('Team withdrawn message'));
      expect(review.players.single.contains('updated teamsheet'),outcome!='removed');
      expect(review.players.single,contains(outcome=='reserve'?'Reserve':outcome=='removed'?'Removed from selection':'Team 1, Two'));
    });
  }
  test('ordinary position move is shown without notification', () {
    final after={...before,'assignments':[{'member_profile_id':'person','fixture_rink_id':'b','position':3}]};
    final review=buildTeamChangeReview(before:before,after:after,names:{'person':'Wayne'});
    expect(review.recipients,0);
    expect(review.players.single,contains('Skip'));
    expect(review.players.single,contains('No automatic message'));
  });
  test('new reserve receives status message; empty new team has none', () {
    final after={...before,'members':[{'member_profile_id':'person','role':'reserve'}],'assignments':[]};
    final review=buildTeamChangeReview(before:before,after:after,names:{'person':'Wayne'});
    expect(review.recipients,1);
    expect(review.players.single,contains('Player-status message + updated teamsheet'));
    final empty=buildTeamChangeReview(before:before,after:{...before,'rinks':[team('a',1),team('b',2),team('c',3)]},names:{});
    expect(empty.recipients,0);
    expect(empty.teams.single,contains('Team 3 added'));
  });
}
