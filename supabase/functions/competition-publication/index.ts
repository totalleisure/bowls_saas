import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { assembleCompetitionEmail, competitionPublicationHtml, requireCompetitionRecipients, requireCompetitionTestRecipients, COMPETITION_TEST_RECIPIENTS } from "../_shared/competition_publication_email.mjs";
import { dispatchCompetitionPublication } from "../_shared/competition_publication_dispatch.mjs";
const headers={"Content-Type":"application/json","Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers});
const check=(r:any)=>{if(r.error)throw new Error(r.error.message);return r.data;};
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS')return reply(200,{});
 if(req.method!=='POST')return reply(405,{error:'POST required'});
 try {
  const url=Deno.env.get('SUPABASE_URL')!;
  const ref=new URL(url).hostname.split('.')[0];
  if(!['egxdkaotepgfjmszxlyn','xfjelvvfoguzukgvxchh'].includes(ref))return reply(403,{error:'Unknown project'});
  const db=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
  const token=(req.headers.get('Authorization')||'').replace(/^Bearer /,'');
  const body=await req.json();
  const auth=await db.auth.getUser(token);if(auth.error||!auth.data.user)return reply(401,{error:'Sign in required'});
  const actor=auth.data.user.id;
  const clubId=body.clubId;
  const memberProfiles=check(await db.from('member_profiles').select('id').eq('user_id',actor));
  const actorProfile=memberProfiles[0]?.id;
  const superuser=check(await db.from('app_superusers').select('user_id').eq('user_id',actor));
  const memberships=actorProfile?check(await db.from('club_memberships').select('id').eq('club_id',clubId).eq('member_profile_id',actorProfile).eq('is_active',true).eq('role','admin')):[];
  if(!superuser.length&&!memberships.length)return reply(403,{error:'Club Admin access required'});
  if(['publication_status','publish'].includes(body.action)) {
   if(!body.competitionId)return reply(400,{error:'Select a competition'});
   check(await db.from('club_competitions').select('id').eq('id',body.competitionId).eq('club_id',clubId).single());
   if(body.action==='publish')check(await db.rpc('prepare_competition_publication',{p_competition_id:body.competitionId,p_actor_user_id:actor}));
   let summary=check(await db.rpc('competition_publication_summary',{p_competition_id:body.competitionId,p_actor_user_id:actor}));
   let outcomes:any[]=[];
   if(body.action!=='publication_status'&&summary.event_id) {
    const event=check(await db.from('competition_publication_events').select('snapshot').eq('id',summary.event_id).single());
    const deliveries=check(await db.rpc('claim_competition_publication_deliveries',{p_event_id:summary.event_id,p_actor_user_id:actor}));
    outcomes=await dispatchCompetitionPublication({projectRef:ref,snapshot:event.snapshot,deliveries,
     saveMessage:async(delivery:any,message:any)=>check(await db.from('competition_publication_deliveries').update({subject:message.subject,html:message.html}).eq('id',delivery.id).eq('status','claimed')),
     send:async(recipient:string,message:any)=>{
      requireCompetitionRecipients(ref,[recipient]);
      const response=await fetch(url+'/functions/v1/send-graph-email',{method:'POST',headers:{Authorization:'Bearer '+Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),'Content-Type':'application/json'},body:JSON.stringify({to:[recipient],subject:(ref==='egxdkaotepgfjmszxlyn'?'[STAGING TEST] ':'')+message.subject,html:message.html})});
      if(!response.ok)throw new Error('Email transport did not confirm delivery');
     },
     finish:async(delivery:any,status:string)=>check(await db.from('competition_publication_deliveries').update({status,sent_at:status==='sent'?new Date().toISOString():null}).eq('id',delivery.id).eq('status','claimed')),
    });
    summary=check(await db.rpc('competition_publication_summary',{p_competition_id:body.competitionId,p_actor_user_id:actor}));
   }
   return reply(200,{...summary,outcomes,stagingOnly:ref==='egxdkaotepgfjmszxlyn'});
  }
  if(body.action==='send_test') {
   const recipients=requireCompetitionTestRecipients('egxdkaotepgfjmszxlyn',body.recipients);
   const preview=check(await db.from('competition_publication_previews').select('*').eq('id',body.previewId).eq('club_id',clubId).eq('actor_user_id',actor).single());
   if(Date.parse(preview.expires_at)<Date.now())return reply(409,{error:'Preview expired; create a fresh preview'});
   const outcomes=[];
   for(const recipient of recipients) {
    const claim=await db.from('competition_publication_test_deliveries').insert({preview_id:preview.id,recipient,actor_user_id:actor}).select('id').single();
    if(claim.error) {outcomes.push({recipient,status:'already_attempted'});continue;}
    try {
     const response=await fetch(url+'/functions/v1/send-graph-email',{method:'POST',headers:{Authorization:'Bearer '+Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),'Content-Type':'application/json'},body:JSON.stringify({to:[recipient],subject:(ref==='egxdkaotepgfjmszxlyn'?'[STAGING TEST] ':'[TEST COPY] ')+preview.subject,html:preview.html})});
     if(!response.ok)throw new Error('Transport did not confirm delivery');
     check(await db.from('competition_publication_test_deliveries').update({status:'sent'}).eq('id',claim.data.id));outcomes.push({recipient,status:'sent'});
    }catch{await db.from('competition_publication_test_deliveries').update({status:'uncertain'}).eq('id',claim.data.id);outcomes.push({recipient,status:'uncertain_do_not_retry'});}
   }
   return reply(200,{outcomes});
  }
  if(body.action!=='preview')return reply(400,{error:'Unknown action'});
  const memberId=body.memberId||actorProfile;
  check(await db.from('club_memberships').select('member_profile_id').eq('club_id',clubId).eq('member_profile_id',memberId).eq('is_active',true).single());
  const profile=check(await db.from('member_profiles').select('id,first_name,last_name').eq('id',memberId).single());
  const club=check(await db.from('clubs').select('name').eq('id',clubId).single());
  let competitionQuery=db.from('club_competitions').select('*').eq('club_id',clubId).order('name');
  if(body.competitionId)competitionQuery=competitionQuery.eq('id',body.competitionId);
  const competitions=check(await competitionQuery);
  const ids=competitions.map((x:any)=>x.id);
  async function rows(table:string){if(!ids.length)return [];const all:any[]=[];for(let offset=0;;offset+=500){const batch=check(await db.from(table).select('*').in('competition_id',ids).order(table==='competition_entry_members'?'member_profile_id':'id').range(offset,offset+499));all.push(...batch);if(batch.length<500)return all;}}
  const [entries,entryMembers,rounds,matches]=await Promise.all(['competition_entries','competition_entry_members','competition_rounds','competition_draw_matches'].map(rows));
  const profileIds=[...new Set(entryMembers.map((x:any)=>x.member_profile_id))];const profiles:any[]=[];
  for(let i=0;i<profileIds.length;i+=100)profiles.push(...check(await db.from('member_profiles').select('id,first_name,last_name,email_address,phone').in('id',profileIds.slice(i,i+100))));
  const content=assembleCompetitionEmail({clubName:club.name,profile,competitions,entries,entryMembers,rounds,matches,profiles});
  if(!content.entries.length)return reply(400,{error:'This member has no competition entries'});
  const subject=body.competitionId&&competitions[0]?competitions[0].name+' — your entry':club.name+' — your competition entries';const html=competitionPublicationHtml(content);
  const preview=check(await db.from('competition_publication_previews').insert({club_id:clubId,actor_user_id:actor,represented_member_id:memberId,subject,html,content}).select('id,expires_at').single());
  return reply(200,{...preview,subject,html,content,testRecipients:COMPETITION_TEST_RECIPIENTS,stagingOnly:ref==='egxdkaotepgfjmszxlyn'});
 }catch(error){return reply(400,{error:error instanceof Error?error.message:'Unable to prepare competition message'});}
});
