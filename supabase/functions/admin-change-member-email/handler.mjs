const headers = { 'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Content-Type': 'application/json',
  'Cache-Control': 'no-store' };
const reply = (body, status=200) => new Response(JSON.stringify(body), {status,headers});
const uuid = v => typeof v==='string' && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(v);
const email = v => typeof v==='string' && v.trim().length<=254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v.trim());

export async function handleEmailChange(req, admin) {
  if(req.method==='OPTIONS') return new Response('ok',{headers});
  if(req.method!=='POST') return reply({error:'Method not allowed'},405);
  const token=req.headers.get('Authorization')?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if(!token) return reply({error:'Please sign in.'},401);
  try {
    const caller=await admin.auth.getUser(token);
    if(caller.error || !caller.data.user) return reply({error:'Please sign in again.'},401);
    const raw=await req.text();
    if(raw.length>4096) return reply({error:'Request too large.'},413);
    let body;try{body=JSON.parse(raw);}catch{return reply({error:'Invalid request.'},400);}
    if(!uuid(body?.club_id)||!uuid(body?.member_profile_id)||!email(body?.email)||!email(body?.expected_email))
      return reply({error:'Select a member and enter a valid email address.'},400);
    const prepared=await admin.rpc('begin_admin_member_email_change',{
      p_actor_user_id:caller.data.user.id,p_club_id:body.club_id,p_member_profile_id:body.member_profile_id,
      p_expected_email:body.expected_email.trim().toLowerCase(),p_new_email:body.email.trim().toLowerCase(),
    });
    if(prepared.error){
      const code=prepared.error.code;
      const known=['42501','22023','40001','23505','55000'].includes(code);
      return reply({error:known?prepared.error.message:'Email change could not be started. Please try again.'},
        code==='42501'?403:['40001','23505','55000'].includes(code)?409:known?400:500);
    }
    const change=prepared.data;
    if(!uuid(change?.change_id)||!uuid(change?.user_id)) return reply({error:'Email change could not be started.'},500);
    // Auth's existing email-sync trigger updates the member profile in the same
    // database transaction. No password, profile or membership is replaced.
    try {
      await admin.auth.admin.updateUserById(change.user_id,{email:change.new_email,email_confirm:true});
    } catch { /* A lost response may follow a successful Auth commit. Verify below. */ }
    const verified=await admin.rpc('finish_admin_member_email_change',{p_change_id:change.change_id});
    if(verified.error) return reply({error:'Unable to verify the email change. Refresh the member record before trying again.'},503);
    if(verified.data?.changed!==true) return reply({error:'Email was not changed. Check the address and refresh the member record.'},400);
    return reply({changed:true,email:verified.data.email});
  } catch {
    return reply({error:'Unable to confirm the email change. Refresh the member record before trying again.'},503);
  }
}
