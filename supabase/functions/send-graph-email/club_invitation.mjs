const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export const STORE_LINKS = Object.freeze([
 ['Android','https://play.google.com/store/apps/details?id=totalleisuresolutions.bowls'],
 ['iPhone / iPad','https://apps.apple.com/gb/app/total-leisure-bowls/id6762380407'],
 ['Windows','https://apps.microsoft.com/detail/9P989QP14Q05'],
]);
export function initialPassword() {
 const pick = alphabet => {
  const limit=256-(256%alphabet.length);let value;
  do {value=crypto.getRandomValues(new Uint8Array(1))[0];} while(value>=limit);
  return alphabet[value%alphabet.length];
 };
 const letters='abcdefghijklmnopqrstuvwxyz',digits='0123456789';
 return pick(letters).toUpperCase()+pick(letters)+pick(letters)+Array.from({length:5},()=>pick(digits)).join('');
}
export function clubInvitationHtml(context, password = null, staging = true) {
 const club=escape(context.club), email=escape(context.email), first=escape(context.first_name || 'Member');
 const downloads=STORE_LINKS.map(([label,url])=>`<a href="${url}" style="font-size:14px;color:#194d85;text-decoration:underline">${label}</a>`).join(' &nbsp; | &nbsp; ');
 const details=password
  ? `<strong>Your initial login details</strong><p>Email: ${email}<br>Initial password: <strong style="font-family:monospace">${escape(password)}</strong></p><p>Your sign-in account is ready. There is no need to register. Keep these details private.</p>`
  : `<strong>Use your existing login</strong><p>Email: ${email}</p><p>Use your current password. No new account or password is needed.</p>`;
 const steps=password
  ? `<li>Open the staging App already installed on your development PC.</li><li>Sign in with the email address and initial password above. Do not choose Register.</li><li>In <strong>My clubs</strong>, find <strong>${club}</strong> and choose <strong>Accept invitation</strong>.</li><li>When prompted, choose <strong>Change my password</strong>, or <strong>Keep this password and continue</strong>. You can change it later in <strong>Member and Volunteer Lists → Account and Security</strong>.</li>`
  : `<li>Open the staging App and sign in as usual.</li><li>In <strong>My clubs</strong>, find <strong>${club}</strong> and choose <strong>Accept invitation</strong>.</li><li>The club will then appear alongside your other clubs.</li>`;
 const result = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;padding:24px 8px;background:#edf2f6;font-family:Arial,Helvetica,sans-serif;color:#243b4d;font-size:15px;line-height:1.65"><table role="presentation" cellspacing="0" cellpadding="0" width="100%" style="max-width:600px;margin:auto;background:white;border-radius:14px;overflow:hidden"><tr><td style="background:#194d85;border-top:6px solid #d9b85b;padding:24px 28px;color:white"><p style="font-size:13px;letter-spacing:1px;margin:0 0 8px">BOWLS ADMIN · TOTAL LEISURE · STAGING TEST</p><h1 style="font-size:27px;line-height:1.25;margin:0">${password?'Welcome to your club App':'Another club. Your existing App.'}</h1><p>${club}</p></td></tr><tr><td style="padding:26px 28px"><p>Hello ${first},</p><p>${club} has invited you to join ${password?'its Bowls App':'as a Member using your existing Bowls App account'}.</p><div style="background:#edf4fa;border-left:4px solid #194d85;padding:16px;margin:20px 0">${details}</div><h2 style="font-size:19px;color:#194d85">${password?'Get started':'Accept your club invitation'}</h2><ol style="padding-left:22px">${steps}</ol><p style="background:#faf4e4;padding:13px;border-radius:6px">Your membership stays inactive until you accept the invitation inside the App. Signing in alone or replying to this email does not activate it. Your other club memberships stay unchanged.</p><h2 style="font-size:17px;color:#194d85">Get the App</h2><p>${downloads}</p><p style="font-size:13px;background:#f1f5f9;padding:12px"><strong>Staging test:</strong> use the staging App already installed. These store links install the live production App; they are provided for reference.</p><p>Need a hand? Email <a href="mailto:wayne@totalleisure.com" style="color:#194d85">wayne@totalleisure.com</a>.</p><p>We look forward to seeing you on the green.<br><strong>Bowls Admin</strong><br>${club}</p></td></tr><tr><td style="padding:14px;background:#194d85;color:white;text-align:center;font-size:13px">Fixtures. Teams. Rink bookings.</td></tr></table></body></html>`;
 if(staging) return result;
 return result.replaceAll(" · STAGING TEST", "").replaceAll("Open the staging App already installed on your development PC.","Download and open the Bowls App using the links below.").replaceAll("Open the staging App", "Open the Bowls App").replace(/<p style="font-size:13px;background:#f1f5f9;padding:12px"><strong>Staging test:<\/strong>.*?<\/p>/, "");
}

// Credentials exist only in this invocation and the outbound email, never in queue payloads.
export async function prepareClubInvitation({queueId,to,url,key,fetcher,html}) {
 if(!queueId) return html;
 const headers={Authorization:`Bearer ${key}`,apikey:key,'Content-Type':'application/json'};
 const response=await fetcher(`${url}/rest/v1/rpc/staging_invitation_delivery_context`,{method:'POST',headers,body:JSON.stringify({p_queue:queueId,p_email:to})});
 if(!response.ok) throw new Error('Invitation eligibility could not be verified');
 const context=await response.json();
 if(!context) return html;
 let password=null;
 if(context.new_user===true) {
  const accountResponse=await fetcher(`${url}/auth/v1/admin/users/${encodeURIComponent(context.user_id)}`,{headers});
  if(!accountResponse.ok) throw new Error('New invitation account could not be checked');
  const account=await accountResponse.json();
  if(account.email?.toLowerCase()!==context.email.toLowerCase()) throw new Error('Invitation account email changed');
  if(!account.last_sign_in_at || context.reissue_initial===true) {
   password=initialPassword();
   const changed=await fetcher(`${url}/auth/v1/admin/users/${encodeURIComponent(context.user_id)}`,{method:'PUT',headers,body:JSON.stringify({password})});
   if(!changed.ok) throw new Error('Initial password could not be prepared');
   const recorded=await fetcher(`${url}/rest/v1/rpc/record_staging_initial_password`,{method:'POST',headers,body:JSON.stringify({p_queue:queueId,p_email:to})});
   if(!recorded.ok) throw new Error('Initial password choice could not be prepared');
  }
 }
 return clubInvitationHtml(context,password,url!=='https://xfjelvvfoguzukgvxchh.supabase.co');
}
