const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const reply = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...cors, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
});
const uuid = (v) => typeof v === 'string' && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(v);
const data = async (query) => {
  const result = await query;
  if (result.error) throw new Error('Database request failed');
  return result.data;
};

export async function handleReset(req, admin) {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Method not allowed' }, 405);
  const token = req.headers.get('Authorization')?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!token) return reply({ error: 'Please sign in.' }, 401);
  try {
    const caller = await admin.auth.getUser(token);
    if (caller.error || !caller.data.user) return reply({ error: 'Please sign in again.' }, 401);
    const raw = await req.text();
    if (raw.length > 4096) return reply({ error: 'Request too large.' }, 413);
    let body;
    try { body = JSON.parse(raw); } catch { return reply({ error: 'Invalid request.' }, 400); }
    if (!uuid(body?.club_id) || !uuid(body?.member_profile_id) ||
        typeof body?.password !== 'string' || body.password.length < 8 ||
        body.password.length > 128 || !body.password.trim()) {
      return reply({ error: 'Select a member and enter a password of 8–128 characters.' }, 400);
    }
    const callerId = caller.data.user.id;
    const superuser = await data(admin.from('app_superusers').select('user_id').eq('user_id', callerId).maybeSingle());
    if (!superuser) {
      const profile = await data(admin.from('member_profiles').select('id').eq('user_id', callerId).maybeSingle());
      const permission = profile && await data(admin.from('club_memberships').select('id')
        .eq('club_id', body.club_id).eq('member_profile_id', profile.id)
        .eq('role', 'admin').eq('is_active', true).maybeSingle());
      if (!permission) return reply({ error: 'Active club administrator access required.' }, 403);
    }
    const membership = await data(admin.from('club_memberships').select('id')
      .eq('club_id', body.club_id).eq('member_profile_id', body.member_profile_id).eq('is_active', true).maybeSingle());
    if (!membership) return reply({ error: 'Select an active member of this club.' }, 403);
    const target = await data(admin.from('member_profiles').select('user_id').eq('id', body.member_profile_id).maybeSingle());
    if (!target?.user_id) return reply({ error: 'This member has no linked login account.' }, 400);
    // A club admin must not take over a platform administrator or an admin
    // from another club by changing their global account password.
    if (!superuser && target.user_id !== callerId) {
      const privileged = await data(admin.from('app_superusers').select('user_id').eq('user_id', target.user_id).maybeSingle());
      const adminRoles = await data(admin.from('club_memberships').select('club_id')
        .eq('member_profile_id', body.member_profile_id).eq('role', 'admin').eq('is_active', true));
      if (privileged || adminRoles.some((r) => r.club_id !== body.club_id)) {
        return reply({ error: 'A platform administrator must reset this administrator account.' }, 403);
      }
    }
    const account = await admin.auth.admin.getUserById(target.user_id);
    if (account.error || !account.data.user?.email) return reply({ error: 'Login account could not be found.' }, 400);
    const changed = await admin.auth.admin.updateUserById(target.user_id, { password: body.password });
    if (changed.error) return reply({ error: 'Password was not changed. Check the password meets the account requirements and try again.' }, 400);
    // Never log, persist, or return the password. Auth records the admin update.
    return reply({ reset: true, email: account.data.user.email });
  } catch {
    return reply({ error: 'Password reset could not be completed. Please try again.' }, 500);
  }
}
