import {requireCompetitionRecipients,prepareCompetitionPublicationMessage} from './competition_publication_email.mjs';
// Each row is claimed atomically before transport. Claimed/uncertain rows are never auto-retried.
export async function dispatchCompetitionPublication({projectRef,snapshot,deliveries,saveMessage,send,finish,prepareMessage=prepareCompetitionPublicationMessage}) {
 if(!['egxdkaotepgfjmszxlyn','xfjelvvfoguzukgvxchh'].includes(projectRef))throw new Error('Unknown competition project');
 if(deliveries.length)requireCompetitionRecipients(projectRef,deliveries.map(d=>d.recipient));
 if(deliveries.some(d=>d.status!=='claimed'))throw new Error('Only atomically claimed publication deliveries may be sent');
 const outcomes=[];
 for(const delivery of deliveries) {
  let phase='prepare';
  try {
   const message=prepareMessage(snapshot,delivery,{projectRef});
   phase='save';
   await saveMessage(delivery,message);
   phase='transport';
   await send(delivery.recipient,message);
   phase='acknowledge';
   await finish(delivery,'sent');
   outcomes.push({recipient:delivery.recipient,status:'sent'});
  } catch (error) {
   const status=phase==='transport' && error?.retryable===true && (delivery.attempt_count||0)<5?'pending':'uncertain';
   const detail={error:`${phase}: ${error?.message||'Unknown error'}`.slice(0,500),retryAfterSeconds:error?.retryAfterSeconds||60};
   try { await finish(delivery,status,detail); } catch { /* Claimed/uncertain rows are never auto-retried. */ }
   outcomes.push({recipient:delivery.recipient,status});
  }
 }
 return outcomes;
}
