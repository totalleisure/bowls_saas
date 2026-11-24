import { requireCompetitionRecipients } from "../_shared/competition_publication_email.mjs";
import { prepareClubInvitation } from "./club_invitation.mjs";

type MailAttachment = {
  name: string;
  contentType: string;
  contentBytes: string; // base64
  contentId?: string;
  isInline?: boolean;
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" },
  });
}

export async function handleRequest(req: Request, env: (name: string) => string | undefined, fetch: typeof globalThis.fetch = globalThis.fetch) {
  let submitted = false;
  let stage = "configuration";
  try {
    if (req.method === "OPTIONS") return json(200, { ok: true });
    if (req.method !== "POST") {
      return json(405, { error: "Method not allowed" });
    }

    const serviceKey = env("SUPABASE_SERVICE_ROLE_KEY");
    if (!serviceKey) return json(500, { error: "Missing server configuration" });
    if (req.headers.get("Authorization") !== `Bearer ${serviceKey}`) {
      return json(401, { error: "Server authorization required" });
    }

    const { to, subject, html, attachments, email_queue_id } = await req.json();

    const tenantId = env("MS_TENANT_ID");
    const clientId = env("MS_CLIENT_ID");
    const clientSecret = env("MS_CLIENT_SECRET");
    const mailbox = env("MS_MAILBOX");

    if (!tenantId || !clientId || !clientSecret || !mailbox) {
      return json(500, { error: "Missing Microsoft Graph environment variables" });
    }

    // All callers share one rolling 20-per-minute budget, including competition mail.
    const supabaseUrl = env("SUPABASE_URL");
    if (!supabaseUrl) return json(500, { error: "Missing server configuration" });
    // Staging must never submit mail to live members, including retries.
    if (!['https://egxdkaotepgfjmszxlyn.supabase.co','https://xfjelvvfoguzukgvxchh.supabase.co'].includes(supabaseUrl.replace(/\/$/, '')) ||
        mailbox.toLowerCase() !== (supabaseUrl.includes('egxdkaotepgfjmszxlyn') ? 'bowls-staging@totalleisure.com' : 'bowls@totalleisure.com')) {
      return json(403, { error: "Mail environment mismatch", send_outcome: "not_submitted" });
    }
    try {
      requireCompetitionRecipients(new URL(supabaseUrl).hostname.split(".")[0], Array.isArray(to) ? to : [to]);
    } catch {
      return json(403, { error: "Recipient is not on the staging test allowlist", send_outcome: "not_submitted" });
    }
    const slotRes = await fetch(`${supabaseUrl}/rest/v1/rpc/reserve_outbound_mail_slot`, {
      method: "POST",
      headers: { Authorization: `Bearer ${serviceKey}`, apikey: serviceKey, "Content-Type": "application/json" },
      body: "{}",
    });
    const slot = await slotRes.json();
    if (!slotRes.ok) return json(503, { error: "Mail rate limiter unavailable", stage: "rate_limit", send_outcome: "not_submitted" });
    if (!slot.allowed) return json(429, { error: "Mail rate limit reached; queued for later", retry_after_seconds: slot.retry_after_seconds ?? 60, stage: "rate_limit", send_outcome: "not_submitted" });

    stage = "authentication";
    const tokenRes = await fetch(
      `https://login.microsoftonline.com/${tenantId}/oauth2/v2.0/token`,
      {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: clientId,
          client_secret: clientSecret,
          scope: "https://graph.microsoft.com/.default",
          grant_type: "client_credentials",
        }),
        signal: AbortSignal.timeout(15000),
      },
    );

    const tokenData = await tokenRes.json();
    const accessToken = tokenData.access_token;

    if (!accessToken) {
      return json(500, {
        error: "Failed to get access token",
        details: {code: tokenData.error}, stage, send_outcome: "not_submitted",
      });
    }

    const graphAttachments = ((attachments ?? []) as MailAttachment[]).map((a) => ({
      "@odata.type": "#microsoft.graph.fileAttachment",
      name: a.name,
      contentType: a.contentType,
      contentBytes: a.contentBytes,
      ...(a.isInline === true && a.contentId
        ? { isInline: true, contentId: a.contentId } : {}),
    }));

    const toList = Array.isArray(to) ? to : [to];

    stage = "invitation_preparation";
    const outboundHtml = await prepareClubInvitation({queueId: email_queue_id,
      to: Array.isArray(to) ? (to.length === 1 ? to[0] : null) : to,
      url: supabaseUrl,key: serviceKey,fetcher: fetch,html});
    stage = "send";
    submitted = true;
    const emailRes = await fetch(
      `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(mailbox)}/sendMail`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            subject,
            body: {
              contentType: "HTML",
              content: outboundHtml,
            },
            toRecipients: toList.map((email: string) => ({
              emailAddress: { address: email },
            })),
            attachments: graphAttachments,
            ...(/^[0-9a-f-]{36}$/i.test(email_queue_id ?? "") ? {
              internetMessageHeaders: [{name:"X-Bowls-Email-Queue-Id",value:email_queue_id}],
            } : {}),
          },
          saveToSentItems: true,
        }),
        signal: AbortSignal.timeout(30000),
      },
    );

    if (!emailRes.ok) {
      const errorText = await emailRes.text();
      return json(emailRes.status, {
        error: "Graph sendMail failed",
        details: errorText.slice(0, 3000),
        stage, send_outcome: emailRes.status === 429 || (emailRes.status >= 400 && emailRes.status < 500 && emailRes.status !== 408) ? "rejected" : "uncertain",
        provider_status: emailRes.status,
        provider_request_id: emailRes.headers.get("request-id"),
        retry_after_seconds: retryAfterSeconds(emailRes.headers.get("Retry-After")),
      });
    }

    return json(200, {
      success: true,
      attachment_count: graphAttachments.length,
      send_outcome: "accepted", provider_status: emailRes.status, provider_request_id: emailRes.headers.get("request-id"),
    });
  } catch (err) {
    return json(500, {
      error: err instanceof Error ? err.message : String(err),
      stage, send_outcome: submitted ? "uncertain" : "not_submitted",
    });
  }
}


function retryAfterSeconds(value: string | null): number | null {
  if (!value) return null;
  const seconds = Number(value);
  return Number.isFinite(seconds) ? Math.max(0, seconds) :
    (Number.isFinite(Date.parse(value)) ? Math.max(0, Math.ceil((Date.parse(value)-Date.now())/1000)) : null);
}
