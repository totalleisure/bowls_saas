import {clubSetupEnvironment} from '../_shared/club_setup_environment.mjs';
const cors = {'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info'};
const reply = (v,s=200) => new Response(JSON.stringify(v),{status:s,headers:{...cors,'Content-Type':'application/json','Cache-Control':'no-store'}});
const uuid = v => typeof v === 'string' && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(v);
// Google may broaden a failed name search to nearby clubs. Do not present those
// as a match for the applicant's club; use the contact route instead.
export function matchesClubQuery(query,name) {
 const words=v=>String(v||'').toLowerCase().match(/[a-z]+/g)||[];
 const ignored=new Set(['the','and','bowls','bowling','club','ltd','limited','indoor','outdoor']);
 const terms=words(query.replace(/\b\w*\d\w*\b/g,'')).filter(w=>!ignored.has(w));
 if(!terms.length)return true;
 const names=words(name).map(w=>w.replace(/s$/,''));
 return terms.filter(t=>names.includes(t.replace(/s$/,''))).length>=Math.min(2,terms.length);
}
export function createHandler({project,service,search,website,details,sendCode,login,hash,randomCode}) {
 return async req => {
  if(req.method==='OPTIONS')return reply({});
  try {clubSetupEnvironment(project);} catch {return reply({error:'Club setup is unavailable in this environment.'},403);}
  if(req.method!=='POST')return reply({error:'POST required'},405);
  try {
   const raw=await req.text(); if(raw.length>6000)return reply({error:'Request too large'},413);
   const body=JSON.parse(raw);
   if(!['search','website','send','verify'].includes(body.action))return reply({error:'Choose a setup action.'},400);
   const ip=req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
   const budget=await service('budget',{ip_hash:await hash(ip)});
   if(budget.limited)return reply({error:'Please pause and try again later, or contact Wayne for help.'},429);
   if(body.action==='search' || body.action==='website') {
    const query=String(body.query||'').trim();
    if(query.length<4 || query.length>180)return reply({error:'Enter your club name and town or postcode.'},400);
    let places;
    if(body.action==='website') {
     if(typeof body.website_url!=='string' || body.website_url.length>300)return reply({error:'Enter your club’s public HTTPS website address.'},400);
     const place=await website(body.website_url,query);
     places=place?[place]:[];
    } else { places=await search(query); }
    const state=await service('search',{places});
    return reply({places,...state});
   }
   if(!uuid(body.request_id))return reply({error:'Please search for your club again.'},400);
   if(body.action==='send') {
    if(typeof body.place_id!=='string' || !/^[a-zA-Z0-9_-]{5,200}$/.test(body.place_id))return reply({error:'Choose a Google club result.'},400);
    const email=String(body.email||'').trim().toLowerCase();
    if(!/^[^\s@<>]{1,100}@[^\s@<>]{1,150}\.[^\s@<>]+$/.test(email) || email.length>254)return reply({error:'Enter your email address.'},400);
    const first=String(body.first_name||'').trim(),last=String(body.last_name||'').trim(),phone=String(body.phone||'').trim();
    if(!first || !last || first.length>100 || last.length>100 || phone.length<6 || phone.length>40 || body.authority!==true)return reply({error:'Complete your name, telephone and authorisation confirmation.'},400);
    // Resolve only the candidate previously saved by this server. A client URL
    // or invented candidate cannot be used to request a code or authorise setup.
    const candidate=await service('candidate',{request_id:body.request_id,place_id:body.place_id});
    if(candidate.error)return reply({error:candidate.error},400);
    const place=await details(body.place_id,candidate);
    if(!place || place.businessStatus==='CLOSED_PERMANENTLY' || !place.addressLine1 || !place.postcode)return reply({contact:true,message:'We need a little help to confirm this club address. Please contact Wayne.'});
    const code=randomCode();
    const result=await service('send',{request_id:body.request_id,place,email,first_name:first,last_name:last,phone,authority:true,code_hash:await hash(body.request_id+':'+code)});
    if(result.error)return reply({error:result.error},400);
    if(result.duplicates?.length)return reply({duplicates:result.duplicates});
    await sendCode(result.email,code);
    return reply({sent:true,place,expires_minutes:10});
   }
   if(!/^\d{6}$/.test(body.code||''))return reply({error:'Enter the six-digit code from your email.'},400);
   const result=await service('verify',{request_id:body.request_id,code_hash:await hash(body.request_id+':'+body.code)});
   if(result.error)return reply({error:result.error},400);
   const signIn=await login(result.email);
   return reply({verified:true,token_hash:signIn.hash,token_type:signIn.type});
  } catch {
   // Never log the request, codes, email addresses, auth tokens or provider secrets.
   return reply({error:'We could not complete that check just now. Your details are still here. Try again or contact Wayne.'},503);
  }
 };
}
