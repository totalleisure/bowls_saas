import {sendCompetitionMail} from '../_shared/competition_mail_transport.mjs';
import {prepareCompetitionPublicationMessage} from '../_shared/competition_publication_email.mjs';
import {prepareCompetitionDeadlineMessage} from '../_shared/competition_deadline_email.mjs';
import {createClient} from 'https://esm.sh/@supabase/supabase-js@2';
import {isVerifiedWorker} from '../process-email-queue/worker_auth.ts';
import {dispatchCompetitionPublication} from '../_shared/competition_publication_dispatch.mjs';
import {prepareCompetitionRoundReadyMessage} from '../_shared/competition_round_ready_email.mjs';
import {requireCompetitionRecipients} from '../_shared/competition_publication_email.mjs';
const headers={'Content-Type':'application/json','Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'};
const reply=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers});
const check=(r:any)=>{if(r.error)throw Error(r.error.message);return r.data;};
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return reply(200,{});
 if(req.method!=='POST')return reply(405,{error:'POST required'});
 try {
  const url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const ref=new URL(url).hostname.split('.')[0];
  if(!['egxdkaotepgfjmszxlyn','xfjelvvfoguzukgvxchh'].includes(ref))return reply(403,{error:'Unknown project'});
  const token=(req.headers.get('Authorization')||'').replace(/^Bearer /,'');
  // Scheduled worker only. No caller-supplied recipients, HTML, event IDs or user claims.
  if(!await isVerifiedWorker(token,key,url))return reply(403,{error:'Verified worker required'});
  const db=createClient(url,key,{auth:{persistSession:false}});
  const outcomes=[];
  const batch=check(await db.rpc('claim_competition_mail_batch'));
  const queues:any={
   publication:{events:'competition_publication_events',deliveries:'competition_publication_deliveries',prepare:prepareCompetitionPublicationMessage},
   round_ready:{events:'competition_round_ready_events',deliveries:'competition_round_ready_deliveries',prepare:prepareCompetitionRoundReadyMessage},
   deadline:{events:'competition_deadline_events',deliveries:'competition_deadline_deliveries',prepare:prepareCompetitionDeadlineMessage},
  };
  const events=new Map<string,any>();
  for(const item of batch) {
   const queue=queues[item.kind],delivery=item.delivery;
   if(!queue)throw Error('Unknown queue');
   try {
    if(!events.has(delivery.event_id))events.set(delivery.event_id,check(await db.from(queue.events).select('snapshot').eq('id',delivery.event_id).single()).snapshot);
    outcomes.push(...await dispatchCompetitionPublication({projectRef:ref,snapshot:events.get(delivery.event_id),deliveries:[delivery],prepareMessage:queue.prepare,
     saveMessage:async(d:any,m:any)=>check(await db.from(queue.deliveries).update({subject:m.subject,html:m.html}).eq('id',d.id).eq('status','claimed')),
     send:async(recipient:string,message:any)=>sendCompetitionMail({url,key,projectRef:ref,recipient,message}),
     finish:async(d:any,status:string,detail:any)=>check(await db.from(queue.deliveries).update({status,sent_at:status==='sent'?new Date().toISOString():null,last_error:detail?.error||null,...(status==='pending'?{next_attempt_at:new Date(Date.now()+Math.max(60,detail?.retryAfterSeconds||60)*1000).toISOString()}:{} )}).eq('id',d.id).eq('status','claimed')),
    }));
   }catch(error){
    await db.from(queue.deliveries).update({status:'uncertain',last_error:String(error).slice(0,500)}).eq('id',delivery.id).eq('status','claimed');
    outcomes.push({recipient:delivery.recipient,status:'uncertain'});
   }
  }
  return reply(200,{processed:batch.length,outcomes});
 }catch{return reply(500,{error:'Unable to process next-round messages; check delivery status before retrying'});}
});
