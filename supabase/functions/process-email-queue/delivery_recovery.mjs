import {graphToken,findSentMessages} from './delivery_policy.mjs';

export async function completeDelivery(client,email,outcome,error=null,details={},delay=0) {
  const result=await client.rpc('complete_email_delivery',{
    p_id:email.id,p_lease:email.delivery_lease ?? null,p_outcome:outcome,
    p_error:error,p_details:details,p_delay_seconds:delay,
  });
  if(result.error || (result.data!==true && email.delivery_lease)) throw new Error(result.error?.message || 'Mail lease was not completed');
  return result.data===true;
}

export async function reconcileUncertain(client,mailbox,env,diagnoseOnly=false) {
  if(!diagnoseOnly) {
    const stale=await client.rpc('recover_stale_email_deliveries');
    if(stale.error) throw new Error(stale.error.message);
  }
  let query=client.from('email_queue').select('*').eq('status','failed').eq('delivery_retry_state','uncertain');
  if(!diagnoseOnly) query=query.lte('next_attempt_at',new Date().toISOString());
  const {data:emails,error}=await query.order('last_attempt_at').limit(diagnoseOnly?20:5);
  if(error) throw new Error(error.message);
  if(!emails?.length) return [];
  let token;
  const report=[];
  const started=Date.now();
  for(const email of emails) {
    if(Date.now()-started>20000) break;
    try {
      token ||= await graphToken(env);
      const result=await findSentMessages(email,mailbox,token);
      const details={...email.delivery_last_details,reconciliation:result};
      // Several matching sent copies require human review, never another send.
      const outcome=result.matches.length===1?'reconciled_sent':result.matches.length>1?'manual_review':'not_found';
      if(!diagnoseOnly) await completeDelivery(client,email,outcome,
        outcome==='not_found'?'No matching message in a complete Sent Items scan.':
          outcome==='manual_review'?'Multiple matching sent messages; review required.':null,
        {...details,...(result.matches.length===1?{sent_at:result.matches[0].sent_at}:{} )});
      report.push({id:email.id,recipient:email.recipient_email,outcome,...result});
    } catch(error) {
      const message=error instanceof Error?error.message:String(error);
      if(!diagnoseOnly) await completeDelivery(client,email,'reconcile_error',message,email.delivery_last_details);
      report.push({id:email.id,outcome:'reconcile_error',error:message});
    }
  }
  return report;
}

export async function preflightDelivery(client,email) {
  if(email.attempts>1 && email.fixture_id && !/cancel/.test(email.event_type) && email.event_type!=='fixture_calendar_updated') {
    const {data,error}=await client.from('fixtures').select('id,start_at,cancelled_at').eq('id',email.fixture_id).maybeSingle();
    if(error) throw new Error('Fixture validity check unavailable');
    if(!data || data.cancelled_at || Date.parse(data.start_at)<=Date.now()) return 'Fixture is cancelled, missing or already started; message held for review.';
  }
  const action=email.payload?.action_block;
  if(action?.request_id) {
    const {data,error}=await client.from('email_action_requests').select('status,expires_at,source_email_queue_id')
      .eq('id',action.request_id).maybeSingle();
    if(error) throw new Error('Response request validity check unavailable');
    if(!data || data.source_email_queue_id!==email.id || data.status!=='pending' || Date.parse(data.expires_at)<=Date.now())
      return 'Response request expired, changed or already answered; message held for review.';
  }
  return null;
}

