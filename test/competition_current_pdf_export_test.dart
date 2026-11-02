import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bowls_saas/features/competitions/competition_draw_pdf.dart';
import 'package:bowls_saas/features/competitions/competition_repository.dart';
void main(){TestWidgetsFlutterBinding.ensureInitialized();test('Export current saved draw with the actual Club identity and badge',()async{
 final f=File('tmp/member-sync-wayne-publication-live.log');if(!f.existsSync())return;
 final text=await f.readAsString();final snapshot=jsonDecode(text.substring(text.indexOf('{'),text.lastIndexOf('}')+1))['rows'][0]['snapshot'];
 const exportDir=String.fromEnvironment('COMPETITION_PDF_EXPORT_DIR',defaultValue:'tmp/pdfs/current');await Directory(exportDir).create(recursive:true);
 for(final id in ['2b0a7ba8-b303-49bc-90a9-48b3a3987179','9a189d23-450b-4729-bffd-8d3d420538a7']){
 final comp=Map<String,dynamic>.from((snapshot['competitions']as List).firstWhere((c)=>c['id']==id));
 List<CompetitionRow> rows(String key)=>(snapshot[key]as List).where((r)=>r['competition_id']==id).map((r)=>Map<String,dynamic>.from(r)).toList();
 final data=CompetitionData(comp,rows('entries'),rows('rounds'),rows('matches'));expect(competitionUsesLewishamBadge(data),true);
 final prefix=id.startsWith('2b0')?'Mixed-Pairs':'Mens-Singles-Championship';
 for(final layout in CompetitionPrintLayout.values){
 final bytes=await buildCompetitionDrawPdf(data,layout:layout,orientation:CompetitionPrintOrientation.portrait,blankWinnerLabels:true,printRules:true,printBackground:true);
 await File('$exportDir/$prefix-${layout.name}-Portrait-Current-Badge.pdf').writeAsBytes(bytes);
 }
 }
});}
