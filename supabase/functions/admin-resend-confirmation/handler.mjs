const headers = {'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
const reply = (body,status=200) => new Response(JSON.stringify(body),{status,headers});
const uuid = v => typeof v==='string' && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(v);
const read = async query => { const r=await query; if(r.error) throw Error('Database unavailable');return r.data; };

export async function handleConfirmation(req, admin, now=()=>Date.now()) {
  if(req.method==='OPTIONS') return new Response('ok',{headers});
  if(req.method!=='POST') return reply({error:'Method not allowed'},405);
  const token=req.headers.get('Authorization')?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if(!token) return reply({error:'Please sign in.'},401);
  try {
    const caller=await admin.auth.getUser(token);
    if(caller.error||!caller.data.user) return reply({error:'Please sign in again.'},401);
    const raw=await req.text();if(raw.length>4096) return reply({error:'Request too large.'},413);
    let body;try{body=JSON.parse(raw);}catch{return reply({error:'Invalid request.'},400);}
    if(!uuid(body?.club_id)||!uuid(body?.member_profile_id)||!['status','resend'].includes(body?.action))
      return reply({error:'Select a member and a valid action.'},400);
    const callerId=caller.data.user.id;
    const superuser=await read(admin.from('app_superusers').select('user_id').eq('user_id',callerId).maybeSingle());
    if(!superuser){
      const profile=await read(admin.from('member_profiles').select('id').eq('user_id',callerId).maybeSingle());
      const permission=profile && await read(admin.from('club_memberships').select('id')
        .eq('club_id',body.club_id).eq('member_profile_id',profile.id).eq('role','admin').eq('is_active',true).maybeSingle());
      if(!permission) return reply({error:'Active club administrator access required.'},403);
    }
    const membership=await read(admin.from('club_memberships').select('id')
      .eq('club_id',body.club_id).eq('member_profile_id',body.member_profile_id).eq('is_active',true).maybeSingle());
    if(!membership) return reply({error:'Select an active member of this club.'},403);
    const target=await read(admin.from('member_profiles').select('user_id,email_address,is_captain_managed')
      .eq('id',body.member_profile_id).maybeSingle());
    if(!target?.user_id || target.is_captain_managed) return reply({eligible:false,reason:'no_login'});
    if(!superuser && target.user_id!==callerId){
      const privileged=await read(admin.from('app_superusers').select('user_id').eq('user_id',target.user_id).maybeSingle());
      const roles=await read(admin.from('club_memberships').select('club_id')
        .eq('member_profile_id',body.member_profile_id).eq('role','admin').eq('is_active',true));
      if(privileged || roles.some(r=>r.club_id!==body.club_id)) return reply({error:'A platform administrator must assist this administrator account.'},403);
    }
    const account=await admin.auth.admin.getUserById(target.user_id);
    const user=account.data?.user;
    if(account.error||!user?.email) return reply({error:'Login account could not be found.'},400);
    const address=user.email.trim().toLowerCase();
    if(address!==target.email_address?.trim().toLowerCase()) return reply({error:'Login and member email addresses differ. Refresh the member record before continuing.'},409);
    if(user.email_confirmed_at) return reply({eligible:false,reason:'confirmed',email:address});
    if(body.action==='status') return reply({eligible:true,email:address});
    if(body.expected_email!==address) return reply({error:'The login email has changed. Refresh the member record before sending.'},409);
    const previous=Date.parse(user.confirmation_sent_at??'');
    if(Number.isFinite(previous)&&now()-previous<60000) return reply({error:'A confirmation email was sent recently. Please wait a minute before trying again.'},429);
    // Use the normal Auth confirmation flow, templates and delivery settings.
    // No password changes, direct email confirmation or token generation.
    const sent=await admin.auth.resend({type:'signup',email:address});
    if(sent.error) return reply({error:sent.error.status===429?'Please wait a minute before resending.':'The confirmation email could not be sent. Please try again.'},sent.error.status===429?429:502);
    const verified=await admin.auth.admin.getUserById(target.user_id);
    const stamp=verified.data?.user?.confirmation_sent_at;
    if(verified.error||!stamp||!Number.isFinite(Date.parse(stamp))||Date.parse(stamp)<=previous)
      return reply({error:'Unable to verify the resend. Refresh the member record before trying again.'},503);
    return reply({sent:true,email:address,sent_at:stamp});
  } catch {return reply({error:'Confirmation email service is unavailable. Please try again.'},503);}
}
