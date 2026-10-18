const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const reply = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
});
const uuid = v => typeof v === 'string' && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(v);
const read = async q => { const r = await q; if (r.error) throw Error('Database request failed'); return r.data; };
export async function handleEnableLogin(req, admin) {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Method not allowed' }, 405);
  const token = req.headers.get('Authorization')?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!token) return reply({ error: 'Please sign in.' }, 401);
  try {
    const caller = await admin.auth.getUser(token);
    if (caller.error || !caller.data.user) return reply({ error: 'Please sign in again.' }, 401);
    const raw = await req.text();
    if (raw.length > 4096) return reply({ error: 'Request too large.' }, 413);
    let b; try { b = JSON.parse(raw); } catch { return reply({ error: 'Invalid request.' }, 400); }
    const email = typeof b?.email === 'string' ? b.email.trim().toLowerCase() : '';
    if (!uuid(b?.club_id) || !uuid(b?.member_profile_id) || email.length > 254 ||
        !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return reply({ error: 'Enter a valid, unique email address.' }, 400);
    const actor = caller.data.user.id;
    const superuser = await read(admin.from('app_superusers').select('user_id').eq('user_id', actor).maybeSingle());
    if (!superuser) {
      const profile = await read(admin.from('member_profiles').select('id').eq('user_id', actor).maybeSingle());
      const permission = profile && await read(admin.from('club_memberships').select('id')
        .eq('club_id', b.club_id).eq('member_profile_id', profile.id).eq('role', 'admin').eq('is_active', true).maybeSingle());
      if (!permission) return reply({ error: 'Active club administrator access required.' }, 403);
    }
    const membership = await read(admin.from('club_memberships').select('id').eq('club_id', b.club_id)
      .eq('member_profile_id', b.member_profile_id).eq('is_active', true).maybeSingle());
    if (!membership) return reply({ error: 'Select an active member of this club.' }, 403);
    const target = await read(admin.from('member_profiles').select('id,user_id,is_captain_managed,email_address,display_name')
      .eq('id', b.member_profile_id).maybeSingle());
    if (!target) return reply({ error: 'Member not found.' }, 404);
    let expectedUserId = target.user_id;
    if (target.user_id) {
      // Only retry this conversion; never change or merge an existing account.
      const existing = await admin.auth.admin.getUserById(target.user_id);
      if (existing.error || existing.data.user?.app_metadata?.captain_managed_profile_id !== target.id ||
          existing.data.user.email?.toLowerCase() !== email) {
        return reply({ error: 'This member already has a login. Use their existing account settings.' }, 409);
      }
    } else {
      if (!target.is_captain_managed) return reply({ error: 'Select a captain-managed member.' }, 400);
      const created = await admin.auth.admin.createUser({
        email, password: crypto.randomUUID() + crypto.randomUUID(), email_confirm: false,
        app_metadata: { captain_managed_profile_id: target.id, enabled_by_admin: actor, enabled_for_club: b.club_id },
        user_metadata: { display_name: target.display_name },
      });
      if (created.error || !created.data.user) return reply({ error:
        'Login could not be created. The email may already be in use, or the member may have changed. Refresh and check before retrying.' }, 409);
      expectedUserId = created.data.user.id;
    }
    // Auth may attach trusted app_metadata after inserting its user row.
    // Only report success once the existing profile has actually been linked.
    const linked = await read(admin.from('member_profiles').select('user_id,is_captain_managed')
      .eq('id', target.id).maybeSingle());
    if (!linked?.user_id || linked.user_id !== expectedUserId || linked.is_captain_managed) {
      return reply({ error: 'The login was created but membership linking needs attention. Please contact your administrator; do not register another account.' }, 409);
    }
    // Request the code only when the member opens the password-setup screen.
    return reply({ enabled: true, email, setup_sent: false });
  } catch {
    return reply({ error: 'Unable to confirm app access. Refresh the member before trying again.' }, 500);
  }
}
