import {requireCompetitionRecipients} from './competition_publication_email.mjs';
export async function sendCompetitionMail({url,key,projectRef,recipient,message,fetcher=globalThis.fetch}) {
 requireCompetitionRecipients(projectRef,[recipient]);
 const response=await fetcher(url+'/functions/v1/send-graph-email',{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({to:[recipient],subject:(projectRef==='egxdkaotepgfjmszxlyn'?'[STAGING TEST] ':'')+message.subject,html:message.html})});
 // Consume every response so successive sends do not retain open HTTP resources.
 const text=await response.text();
 let data={};try{data=JSON.parse(text);}catch{}
 if(!response.ok || data.success!==true) {
  const error=new Error(`Mail sender did not accept this message (HTTP ${response.status})`);
  error.retryable=response.status===429;
  error.retryAfterSeconds=Math.max(60,Number(data.retry_after_seconds)||60);
  throw error;
 }
}
