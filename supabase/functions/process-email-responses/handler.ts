import { parseResponse } from "./response_parser.ts";
import { candidate, correlate, automated, header, buildReminderHtml, responseTokenHash } from "./written_reply.ts";
import type { Mail } from "./written_reply.ts";
import type { ResponseMessage } from "./response_parser.ts";
import { verifySentReminder } from "./verify_reminder.ts";

type GraphMessage = ResponseMessage & Mail & {
  id?: string;
  receivedDateTime?: string;
  from?: {
    emailAddress?: {
      address?: string;
    };
  };
  body?: {
    contentType?: string;
    content?: string;
  };
  ["@removed"]?: unknown;
};

type DeltaPage = {
  value?: GraphMessage[];
  ["@odata.nextLink"]?: string;
  ["@odata.deltaLink"]?: string;
  error?: {
    code?: string;
    message?: string;
  };
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function getGraphToken(env: (name: string) => string | undefined, fetch: typeof globalThis.fetch): Promise<string> {
  const tenantId = env("MS_TENANT_ID");
  const clientId = env("MS_CLIENT_ID");
  const clientSecret = env("MS_CLIENT_SECRET");

  if (!tenantId || !clientId || !clientSecret) {
    throw new Error("Missing Microsoft Graph environment variables");
  }

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
    },
  );

  const tokenData = await tokenRes.json();
  if (!tokenRes.ok || !tokenData?.access_token) {
    throw new Error(
      `Failed to obtain Microsoft Graph token (${tokenRes.status})`,
    );
  }

  return String(tokenData.access_token);
}

async function getMessageForParsing(
  mailbox: string,
  messageId: string,
  graphToken: string,
  fetch: typeof globalThis.fetch,
): Promise<GraphMessage> {
  const messageRes = await fetch(
    `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(mailbox)}` +
      `/messages/${encodeURIComponent(messageId)}` +
      "?$select=id,internetMessageId,internetMessageHeaders,subject,body,receivedDateTime,from",
    {
      headers: {
        Authorization: `Bearer ${graphToken}`,
        Prefer: 'outlook.body-content-type="text"',
      },
    },
  );
  const message = await messageRes.json() as GraphMessage & {
    error?: { code?: string; message?: string };
  };

  if (!messageRes.ok) {
    throw new Error(
      `Microsoft Graph message read failed (${messageRes.status}): ` +
        `${message.error?.code ?? ""} ${message.error?.message ?? ""}`,
    );
  }

  return {
    ...message,
    bodyText: String(message.body?.content ?? ""),
  };
}

export async function handleRequest(req: Request, dependencies: {
  env: (name: string) => string | undefined;
  createClient: (url: string, key: string) => any;
  fetch?: typeof globalThis.fetch;
}) {
  const { env, createClient } = dependencies;
  const fetch = dependencies.fetch ?? globalThis.fetch;
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  const supabaseUrl = env("SUPABASE_URL");
  const serviceRoleKey = env("SUPABASE_SERVICE_ROLE_KEY");
  const mailbox = env("MS_MAILBOX");

  if (!supabaseUrl || !serviceRoleKey || !mailbox) {
    return json(500, {
      error: "Missing Supabase or Microsoft mailbox environment variables",
    });
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json(401, { error: "Server authorization required" });
  if (supabaseUrl !== "https://egxdkaotepgfjmszxlyn.supabase.co" || mailbox !== "bowls-staging@totalleisure.com") {
    return json(403, { error: "Staging project and mailbox required" });
  }
  if (authorization !== `Bearer ${serviceRoleKey}`) {
    // Let PostgREST verify a rotated/legacy worker JWT cryptographically. This
    // table explicitly revokes ALL access from anon/authenticated/PUBLIC.
    // Never trust a locally decoded role claim or fall back to the default token.
    try {
      const worker = await fetch(`${supabaseUrl}/rest/v1/email_written_reply_settings?select=mailbox&limit=0`, {
        headers: { apikey: serviceRoleKey, Authorization: authorization },
      });
      if (!worker.ok) return json(401, { error: "Server authorization required" });
    } catch { return json(503, { error: "Worker authorization unavailable" }); }
  }
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  try {
    const graphToken = await getGraphToken(env, fetch);
    const { data: config, error: configError } = await supabase.from("email_written_reply_settings")
      .select("*").eq("mailbox",mailbox).maybeSingle();
    if (configError) throw new Error("Unable to read written reply settings");
    // A read-only deployment probe never scans or processes messages.
    const input = await req.json().catch(() => ({}));
    if (input.mode === "verify") {
      const check = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(mailbox)}/mailFolders/inbox?$select=id`,
        { headers: { Authorization: `Bearer ${graphToken}` } });
      if (!check.ok) throw new Error(`Mailbox verification failed (${check.status})`);
      return json(200, { success:true, mailbox, written_replies_enabled:!!config?.enabled,
        allowed_recipients:config?.reminder_recipients?.length ?? 0, mode:"verify" });
    }
    if (input.mode === "verify_test_reminder") {
      try { return json(200, await verifySentReminder(input.request_id,mailbox,graphToken,supabase,fetch)); }
      catch { return json(500, {error:"Unable to verify sent test reminder"}); }
    }
    if (!config?.enabled) return json(409, { error: "Staging receipt tests are disabled" });
    if (input.mode === "send_test_selection") {
      const { data: email, error } = await supabase.from("email_queue")
        .select("id,recipient_email,subject,body,payload,status").eq("id", input.email_queue_id).maybeSingle();
      if (error || email?.payload?.written_reply_test !== true ||
          email?.recipient_email !== "wayne@totalleisure.com" || email?.status !== "pending") {
        return json(400, { error:"A pending Wayne-only synthetic test email is required" });
      }
      const { data: claimed, error: claimError } = await supabase.from("email_queue")
        .update({status:"processing",processing_started_at:new Date().toISOString()})
        .eq("id",email.id).eq("status","pending").select("id");
      if (claimError || claimed?.length !== 1) return json(409,{error:"Test email already claimed"});
      const sent = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(mailbox)}/sendMail`, {
        method:"POST",headers:{Authorization:`Bearer ${graphToken}`,"Content-Type":"application/json"},
        body:JSON.stringify({message:{subject:email.subject,body:{contentType:"HTML",content:email.body},
          toRecipients:[{emailAddress:{address:"wayne@totalleisure.com"}}]},saveToSentItems:true})
      });
      if (sent.status !== 202) throw new Error(`Test email send failed (${sent.status}); do not automatically retry`);
      const { error: saveError } = await supabase.from("email_queue")
        .update({status:"sent",sent_at:new Date().toISOString()}).eq("id",email.id);
      if (saveError) throw new Error("Test email accepted by Graph; delivery record needs review");
      return json(200,{success:true,recipient:"wayne@totalleisure.com",mode:"send_test_selection"});
    }

    const { data: state, error: stateError } = await supabase
      .from("email_inbox_sync_state")
      .select("*")
      .eq("mailbox", mailbox)
      .maybeSingle();

    if (stateError) {
      throw new Error(`Unable to read inbox sync state: ${stateError.message}`);
    }

    const initialSync = !state?.delta_link;
    const initialUrl =
      `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(mailbox)}` +
      "/mailFolders/inbox/messages/delta" +
      "?$select=id,subject,bodyPreview,receivedDateTime,from&$top=50";

    let nextUrl = state?.delta_link || initialUrl;
    let deltaLink = "";
    let pageCount = 0;
    let scanned = 0;
    let matched = 0;
    let processed = 0;
    let rejected = 0;
    let duplicates = 0;

    while (nextUrl && pageCount < 20) {
      const graphRes = await fetch(nextUrl, {
        headers: { Authorization: `Bearer ${graphToken}` },
      });
      const page = await graphRes.json() as DeltaPage;

      if (!graphRes.ok) {
        throw new Error(
          `Microsoft Graph inbox read failed (${graphRes.status}): ` +
            `${page.error?.code ?? ""} ${page.error?.message ?? ""}`,
        );
      }

      pageCount++;

      for (const message of page.value ?? []) {
        if (!message.id || message["@removed"]) continue;
        scanned++;

        // Establishing the first delta cursor must never process historical mail.
        if (initialSync) continue;

        const completeMessage = await getMessageForParsing(
          mailbox,
          message.id,
          graphToken,
          fetch,
        );
        // The staging pilot gates ALL actions, including explicit commands, so
        // an old delta cursor can never replay historic member responses.
        const received = Date.parse(completeMessage.receivedDateTime ?? "");
        if (!Number.isFinite(received) || received < Date.parse(config.enabled_at) ||
            received > Date.now() + 300000 ||
            !config.reminder_recipients.includes(String(completeMessage.from?.emailAddress?.address ?? "").trim().toLowerCase())) continue;
        if (automated(completeMessage, mailbox)) continue;
        const parsed = parseResponse(completeMessage);
        if (!parsed) {
          if (config?.enabled && candidate(completeMessage, mailbox, config.enabled_at, new Date().toISOString()) &&
              config.reminder_recipients.includes(String(completeMessage.from?.emailAddress?.address ?? "").trim().toLowerCase())) {
            await processWrittenReply(completeMessage, mailbox, graphToken, supabase, fetch);
          }
          continue;
        }
        matched++;

        if (parsed.kind === "ambiguous") {
          rejected++;
          continue;
        }

        const sender = String(
          completeMessage.from?.emailAddress?.address ?? "",
        ).trim().toLowerCase();

        const { data: result, error: responseError } = await supabase.rpc(
          "apply_email_action_response",
          {
            p_response_code: parsed.responseCode,
            p_response_token: parsed.responseToken,
            p_command: parsed.command,
            p_sender_email: sender,
            p_graph_message_id: message.id,
            p_received_at: completeMessage.receivedDateTime ??
              new Date().toISOString(),
          },
        );

        if (responseError) {
          rejected++;
          continue;
        }

        if (result?.status === "duplicate") {
          duplicates++;
        } else if (result?.ok === true) {
          processed++;
        } else {
          rejected++;
        }
      }

      if (page["@odata.deltaLink"]) {
        deltaLink = page["@odata.deltaLink"];
      }

      nextUrl = page["@odata.nextLink"] ?? "";
    }

    if (nextUrl) {
      throw new Error("Inbox delta sync exceeded the 20-page safety limit");
    }

    if (!deltaLink) {
      throw new Error("Microsoft Graph did not return an inbox delta cursor");
    }

    const now = new Date().toISOString();
    const { error: saveError } = await supabase
      .from("email_inbox_sync_state")
      .upsert({
        mailbox,
        delta_link: deltaLink,
        initialized_at: state?.initialized_at ?? now,
        last_checked_at: now,
        last_success_at: now,
        last_error: null,
        updated_at: now,
      }, { onConflict: "mailbox" });

    if (saveError) {
      throw new Error(
        `Unable to save inbox delta cursor: ${saveError.message}`,
      );
    }

    return json(200, {
      success: true,
      initialized_only: initialSync,
      pages: pageCount,
      scanned,
      matched,
      processed,
      rejected,
      duplicates,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    const now = new Date().toISOString();

    await supabase
      .from("email_inbox_sync_state")
      .upsert({
        mailbox,
        last_checked_at: now,
        last_error: message,
        updated_at: now,
      }, { onConflict: "mailbox" });

    return json(500, { error: message });
  }
}

export async function processWrittenReply(message: GraphMessage, mailbox: string, token: string, supabase: any, fetch: typeof globalThis.fetch) {
  const replyTo = header(message, "in-reply-to");
  const query = new URLSearchParams({
    "$filter": `internetMessageId eq '${replyTo.replaceAll("'", "''")}'`,
    "$select": "id,internetMessageId,subject,body,from,toRecipients,sentDateTime",
    "$top": "2",
  });
  const originalRes = await fetch(
    `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(mailbox)}/mailFolders/sentitems/messages?${query}`,
    { headers: { Authorization: `Bearer ${token}`, Prefer: 'outlook.body-content-type="text"' } });
  if (!originalRes.ok) throw new Error(`Original email lookup failed (${originalRes.status})`);
  const originals = await originalRes.json();
  if (originals.value?.length !== 1) return;
  const original = originals.value[0];
  const match = correlate(message, original, mailbox);
  if (!match) return;
  const { data: claim, error } = await supabase.rpc("claim_written_selection_reply", {
    p_mailbox:mailbox, p_internet_message_id:message.internetMessageId,
    p_graph_message_id:message.id, p_received_at:message.receivedDateTime,
    p_response_code:match.code, p_sender_email:message.from?.emailAddress?.address,
    p_original_subject:original.subject, p_excerpt:match.excerpt,
    p_response_token_hash:await responseTokenHash(match.responseToken),
  });
  if (error) throw new Error("Unable to record written selection reply");
  if (!claim?.send_reminder) return;
  // Reuse only the verified original credential. Do not rotate it: original
  // buttons remain valid until this same single-use request is answered.
  const html = buildReminderHtml(mailbox,match.code,match.responseToken,claim.response_protocol_version);
  // Claim is durable BEFORE calling Graph. Unknown delivery outcomes are never retried.
  let deliveryStatus = "failed_or_unknown";
  try {
    const sent = await fetch(`https://graph.microsoft.com/v1.0/users/${encodeURIComponent(mailbox)}/sendMail`, {
      method:"POST", headers:{ Authorization:`Bearer ${token}`, "Content-Type":"application/json" },
      body:JSON.stringify({message:{
        subject:"Your selection response",
        body:{contentType:"HTML",content:html},
        toRecipients:[{emailAddress:{address:claim.recipient}}],
        internetMessageHeaders:[{name:"x-bowls-selection-reminder",value:"1"}]
      },saveToSentItems:true})
    });
    if (sent.status === 202) deliveryStatus = "accepted";
  } catch { /* Leave a durable uncertain outcome for manual review, never resend. */ }
  const { error: saveError } = await supabase.from("email_written_reply_reminders")
    .update({delivery_status:deliveryStatus,updated_at:new Date().toISOString()}).eq("reply_id",claim.reply_id);
  if (saveError) throw new Error("Unable to record reminder delivery outcome");
}
