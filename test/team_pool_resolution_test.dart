import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/team/team_composition_staging.dart';
Map<String,dynamic> member(String id, String acceptance, [String role='player']) =>
 {'member_profile_id':id,'is_selected':true,'role':role,'acceptance':acceptance};
void main() {
 test('fully positioned players and existing reserves need no allocation dialogue', () {
  final selected=[member('a','accepted'),member('b','pending'),member('r','pending','reserve')];
  expect(unpositionedSelectedPlayers(selected:selected,assignments:[{'member_profile_id':'a'},{'member_profile_id':'b'}]),isEmpty);
 });
 test('replacement removes displaced decliner but preserves accepted player and reserve', () {
  final selected=[member('decliner','declined'),member('accepted','accepted'),member('reserve','pending','reserve')];
  final removed=removeUnpositionedDecliners(selected:selected,assignments:[{'member_profile_id':'accepted'}]);
  expect(removed,{'decliner'});
  expect(selected.map((m)=>m['member_profile_id']),['accepted','reserve']);
  expect(selected.first['acceptance'],'accepted');
 });
 test('declined player stays positioned until captain replaces them', () {
  final selected=[member('d','declined')];
  expect(removeUnpositionedDecliners(selected:selected,assignments:[{'member_profile_id':'d'}]),isEmpty);
  expect(selected,hasLength(1));
 });
 test('all unassigned players resolved together; existing reserves and acceptance retained', () {
  final selected=[member('a','accepted'),member('b','pending'),member('r','accepted','reserve'),member('p','accepted')];
  final unresolved=unpositionedSelectedPlayers(selected:selected,assignments:[{'member_profile_id':'p'}]);
  expect(unresolved.map((m)=>m['member_profile_id']),['a','b']);
  resolveUnpositionedPlayers(selected:selected,memberIds:{'a','b'},makeReserves:true);
  expect(selected.map((m)=>m['role']),['reserve','reserve','reserve','player']);
  expect(selected.first['acceptance'],'accepted');
  resolveUnpositionedPlayers(selected:selected,memberIds:{'a','b'},makeReserves:false);
  expect(selected.map((m)=>m['member_profile_id']),['r','p']);
 });
}
