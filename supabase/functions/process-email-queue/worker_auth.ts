// Verify alternate worker credentials through Supabase, never by decoding JWT claims.
// This probe table grants no SELECT permission to anon/authenticated/PUBLIC.
export async function isVerifiedWorker(
  bearer: string, serviceRoleKey: string, supabaseUrl: string,
  fetcher: typeof globalThis.fetch = globalThis.fetch,
): Promise<boolean> {
  if (!bearer) return false;
  if (bearer === serviceRoleKey) return true;
  const response = await fetcher(
    `${supabaseUrl}/rest/v1/email_written_reply_settings?select=mailbox&limit=0`,
    { headers: { apikey: serviceRoleKey, Authorization: `Bearer ${bearer}` },
      signal: AbortSignal.timeout(5000) },
  );
  if (response.status === 401 || response.status === 403) return false;
  if (!response.ok) throw new Error("Worker authorization unavailable");
  const data = await response.json();
  if (!Array.isArray(data) || data.length !== 0) {
    throw new Error("Unexpected worker authorization response");
  }
  return true;
}
