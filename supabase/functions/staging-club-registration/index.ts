import {clubSetupEnvironment} from '../_shared/club_setup_environment.mjs';
import {createClient} from 'npm:@supabase/supabase-js@2.49.8';
import {createHandler,matchesClubQuery} from './handler.mjs';
import {normalisePlace,looksLikeBowlsClub,googlePost,googleDetails} from './places.ts';
import {safeWebsiteReader,verifyClubWebsite} from './website.mjs';
const project=Deno.env.get('SUPABASE_URL') || '';
const environment=clubSetupEnvironment(project);
const admin=createClient(project,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '',{auth:{persistSession:false,autoRefreshToken:false}});
const googleKey=Deno.env.get('GOOGLE_PLACES_API_KEY') || '';
const hash=async(value:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))).map(v=>v.toString(16).padStart(2,'0')).join('');
const readWebsite=safeWebsiteReader({resolve:async(host:string)=>{
 const records=await Promise.allSettled([Deno.resolveDns(host,'A'),Deno.resolveDns(host,'AAAA')]);
 return records.flatMap(r=>r.status==='fulfilled'?r.value:[]);
}});
const website=(url:string,query:string)=>verifyClubWebsite({website:url,query,read:readWebsite,hash});
Deno.serve(createHandler({
 project,
 hash,
 website,
 randomCode:()=>String(100000+(crypto.getRandomValues(new Uint32Array(1))[0]%900000)),
 service:async(action:string,data:unknown)=>{
  const result=await admin.rpc('staging_registration_service',{p_action:action,p_data:data});
  if(result.error)throw new Error('Registration service unavailable');
  return result.data;
 },
 search:async(query:string)=>{
  if(!googleKey)throw new Error('Lookup unavailable');
  const textQuery=/\b(bowls|bowling)\b/i.test(query) ? query : `${query} bowls club`;
  const result=await googlePost(googleKey,{textQuery,pageSize:8,languageCode:'en',regionCode:'GB'},'places.id,places.displayName,places.formattedAddress,places.location,places.primaryType,places.types,places.businessStatus');
  return (result.places??[]).map(normalisePlace).filter(p=>p.placeId && p.businessStatus!=='CLOSED_PERMANENTLY' && looksLikeBowlsClub(p.name,p.types) && matchesClubQuery(query,p.name));
 },
 details:async(id:string,candidate:Record<string,unknown>)=>{
  if(candidate.source==='website') {
   const result=await website(String(candidate.websiteUrl),String(candidate.name));
   return result?.placeId===id ? result : null;
  }
  const p=normalisePlace(await googleDetails(googleKey,id));
  return looksLikeBowlsClub(p.name,p.types) ? p : null;
 },
 sendCode:async(email:string,code:string)=>{
  // Recipient is returned only after the database's exact staging allowlist check.
  const tenant=Deno.env.get('MS_TENANT_ID')!,client=Deno.env.get('MS_CLIENT_ID')!,secret=Deno.env.get('MS_CLIENT_SECRET')!;
  const auth=await fetch(`https://login.microsoftonline.com/${encodeURIComponent(tenant)}/oauth2/v2.0/token`,{method:'POST',signal:AbortSignal.timeout(8000),body:new URLSearchParams({client_id:client,client_secret:secret,scope:'https://graph.microsoft.com/.default',grant_type:'client_credentials'})});
  if(!auth.ok)throw new Error('Mail unavailable');
  const token=(await auth.json()).access_token;
  const sent=await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(environment.mailbox)}/sendMail`,{method:'POST',signal:AbortSignal.timeout(8000),headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({message:{subject:`Bowls App${environment.staging ? ' STAGING' : ''} — verify your club setup email`,body:{contentType:'Text',content:`Your club setup verification code is ${code}.\n\nEnter it in the ${environment.staging ? "staging " : ""}Bowls App within 10 minutes. No club has been created and no member invitations have been sent.\n\nIf you did not request this code, ignore this message. Do not share the code.`},toRecipients:[{emailAddress:{address:email}}]},saveToSentItems:true})});
  if(sent.status!==202)throw new Error('Mail delivery unconfirmed');
 },
 login:async(email:string)=>{
  // Standard Supabase one-use sign-in token, released only after our emailed challenge.
  // Existing accounts retain their password, memberships and profile.
  const result=await admin.auth.admin.generateLink({type:'magiclink',email});
  if(result.error || !result.data.properties?.hashed_token)throw new Error('Sign-in unavailable');
  const type=result.data.properties.verification_type;
  if(!['signup','magiclink'].includes(type))throw new Error('Unexpected sign-in type');
  return {hash:result.data.properties.hashed_token,type};
 },
}));
