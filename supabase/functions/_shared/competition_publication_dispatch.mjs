import {requireCompetitionRecipients,prepareCompetitionPublicationMessage} from './competition_publication_email.mjs';
// Each row is claimed atomically before transport. Claimed/uncertain rows are never auto-retried.
export async function dispatchCompetitionPublication({projectRef,snapshot,deliveries,saveMessage,send,finish,prepareMessage=prepareCompetitionPublicationMessage}) {
 if(!['egxdkaotepgfjmszxlyn','xfjelvvfoguzukgvxchh'].includes(projectRef))throw new Error('Unknown competition project');
 if(deliveries.length)requireCompetitionRecipients(projectRef,deliveries.map(d=>d.recipient));
 if(deliveries.some(d=>d.status!=='claimed'))throw new Error('Only atomically claimed publication deliveries may be sent');
 const outcomes=[];
 for(const delivery of deliveries) {
  try {
   const message=prepareMessage(snapshot,delivery,{projectRef});
   await saveMessage(delivery,message);
   await send(delivery.recipient,message);
   await finish(delivery,'sent');
   outcomes.push({recipient:delivery.recipient,status:'sent'});
  } catch {
   try { await finish(delivery,'uncertain'); } catch { /* A claimed row is also unconfirmed and must not be retried. */ }
   outcomes.push({recipient:delivery.recipient,status:'uncertain'});
  }
 }
 return outcomes;
}
