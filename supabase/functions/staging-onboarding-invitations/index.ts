import {createClient} from 'https://esm.sh/@supabase/supabase-js@2.57.4';
import {provisionContact} from './provision.mjs';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info'};
const reply=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers:{...cors,'Content-Type':'application/json'}});
const uuid=(v:unknown)=>typeof v==='string' && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(v);
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return reply({});
 if(req.method!=='POST')return reply({error:'Method not allowed'},405);
 const url=Deno.env.get('SUPABASE_URL');
 if(!['https://egxdkaotepgfjmszxlyn.supabase.co','https://xfjelvvfoguzukgvxchh.supabase.co'].includes(url??''))return reply({error:'Unknown environment'},403);
 const token=req.headers.get('Authorization')?.match(/^Bearer\s+(\S+)$/i)?.[1];
 if(!token)return reply({error:'Please sign in'},401);
 try {
  const admin=createClient(url,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false,autoRefreshToken:false}});
  const auth=await admin.auth.getUser(token);
  if(auth.error || !auth.data.user || auth.data.user.is_anonymous)return reply({error:'Please sign in'},401);
  const raw=await req.text();if(raw.length>40000)return reply({error:'Request too large'},413);
  const body=JSON.parse(raw);
  if(!uuid(body.club_id) || body.confirm!==true || !Array.isArray(body.contact_ids) || !Array.isArray(body.membership_ids)
   || body.contact_ids.length+body.membership_ids.length>250 || ![...body.contact_ids,...body.membership_ids].every(uuid))return reply({error:'Review selected invitations first'},400);
  const caller=createClient(url,Deno.env.get('SUPABASE_ANON_KEY')!,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false,autoRefreshToken:false}});
  // A current admin check is required even when no existing memberships were selected.
  const preview=await caller.rpc('preview_staging_club_invitations',{p_club:body.club_id});
  if(preview.error)return reply({error:'Active club administrator access required'},403);
  let queued=0,already=0;const errors=[];
  if(body.membership_ids.length) {
   const result=await caller.rpc('queue_staging_club_invitations',{p_club:body.club_id,p_memberships:body.membership_ids,p_confirm:true});
   if(result.error)return reply({error:'Selected memberships require review'},400);
   queued+=result.data.queued;already+=result.data.already_prepared;
  }
  for(const id of new Set(body.contact_ids)) {
   try {const result=await provisionContact(admin,id,auth.data.user.id,body.club_id);queued+=result.queued;already+=result.already_prepared;}
   catch {errors.push({contact_id:id,message:'This contact needs review before another attempt. Any prepared account remains inactive.'});}
  }
  return reply({queued,already_prepared:already,errors,membership_activated:false});
 } catch {return reply({error:'Invitation preparation could not complete. Refresh status before retrying.'},400);}
});
