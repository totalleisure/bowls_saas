const headers = {'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'",'X-Content-Type-Options':'nosniff'};
const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const reply = (body,status=200) => new Response('<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Bowls fixture</title></head><body style="font-family:system-ui;max-width:700px;margin:40px auto;padding:20px">'+body+'</body></html>',{status,headers});
async function hash(s) { return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s))), b=>b.toString(16).padStart(2,'0')).join(''); }
export async function viewFixture(req,db,now=Date.now()) {
 if(req.method!=='GET')return reply('Method not allowed',405);
 const url=new URL(req.url),code=url.searchParams.get('code')??'',token=url.searchParams.get('token')??'';
 const invalid=()=>reply('<h1>This fixture link is unavailable</h1><p>Open the Bowls App to view the latest fixture details.</p>',403);
 if(!/^BWL-[A-F0-9]{12}$/.test(code)||!/^RSP-[A-F0-9]{48}$/.test(token))return invalid();
 try {
  const {data:r,error}=await db.from('email_action_requests').select('fixture_id,team_selection_id,target_record_id,member_profile_id,status,expires_at').eq('response_code_hash',await hash(code)).eq('response_token_hash',await hash(token)).eq('response_protocol_version',2).maybeSingle();
  if(error||!r||!['pending','responded'].includes(r.status)||!(Date.parse(r.expires_at)>now))return invalid();
  const {data:member,error:me}=await db.from('team_selection_members').select('id').eq('id',r.target_record_id).eq('member_profile_id',r.member_profile_id).eq('team_selection_id',r.team_selection_id).eq('is_selected',true).maybeSingle();
  if(me||!member)return invalid();
  const {data:f,error:fe}=await db.from('fixtures').select('id,team_name,start_at,end_at,is_home,notes,cancelled_at,venue:venues!fixtures_venue_id_fkey(name,address_line1,town_city,postcode)').eq('id',r.fixture_id).maybeSingle();
  if(fe||!f)return invalid();
  const when=new Intl.DateTimeFormat('en-GB',{timeZone:'Europe/London',dateStyle:'full',timeStyle:'short'}).format(new Date(f.start_at));
  return reply(`<h1>${f.cancelled_at?'Fixture cancelled':'Rescheduled fixture'}</h1><h2>${esc(f.team_name||'Bowls fixture')}</h2><p><strong>${esc(when)}</strong></p><p>${f.is_home?'Home':'Away'}</p><p>${esc([f.venue?.name,f.venue?.address_line1,f.venue?.town_city,f.venue?.postcode].filter(Boolean).join(', '))}</p>${f.notes?`<h3>Special Instructions</h3><p style="white-space:pre-wrap">${esc(f.notes)}</p>`:''}<p>${f.cancelled_at?'This fixture is cancelled. No response is required.':'Return to the email and choose Accept or Decline, then send the prepared reply.'} Viewing this page does not change your response.</p>`);
 }catch{return reply('<h1>Unable to load fixture</h1><p>Please try again or open the Bowls App.</p>',503);}
}
