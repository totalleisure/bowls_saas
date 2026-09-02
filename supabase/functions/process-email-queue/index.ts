import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type EmailAction = {
  command?: string;
  label?: string;
  style?: string;
};

type EmailActionBlock = {
  version?: number;
  request_id?: string;
  action_type?: string;
  heading?: string;
  instructions?: string;
  response_code?: string;
  response_token?: string;
  expires_at?: string | null;
  actions?: EmailAction[];
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function escapeHtml(value: unknown): string {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function formatExpiry(value: string | null | undefined): string {
  if (!value) return "";
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return "";
  return dt.toLocaleString("en-GB", {
    timeZone: "Europe/London",
    dateStyle: "full",
    timeStyle: "short",
  });
}

function generateResponseToken(): string {
  const bytes = new Uint8Array(24);
  crypto.getRandomValues(bytes);
  return `RSP-${
    Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("")
      .toUpperCase()
  }`;
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(
    new Uint8Array(digest),
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

function buildEmailActionBlock(
  block: EmailActionBlock | null | undefined,
  replyAddress: string,
): string {
  if (!block || !block.response_code || !Array.isArray(block.actions)) {
    return "";
  }

  const code = String(block.response_code).trim().toUpperCase();
  const token = String(block.response_token ?? "").trim().toUpperCase();
  const actions = block.actions.filter((action) =>
    Boolean(action?.command?.trim() && action?.label?.trim())
  );

  if (!code || actions.length === 0) return "";

  const responseCredential = token ? `${code} ${token}` : code;

  const buttons = actions.map((action) => {
    const command = String(action.command).trim().toUpperCase();
    const label = String(action.label).trim();
    const isNegative = action.style === "negative";
    const colour = isNegative ? "#b3261e" : "#18794e";
    const subject = `Bowls response: ${command} ${responseCredential}`;
    const body = `${command} ${responseCredential}`;
    const href = `mailto:${replyAddress}?subject=${
      encodeURIComponent(subject)
    }&body=${encodeURIComponent(body)}`;

    return `
      <a href="${escapeHtml(href)}"
         style="display:inline-block;margin:6px 8px 6px 0;padding:12px 18px;
                border-radius:6px;background:${colour};color:#ffffff;
                text-decoration:none;font-weight:700;">
        ${escapeHtml(label)}
      </a>`;
  }).join("");

  const expiry = formatExpiry(block.expires_at);
  const heading = block.heading || "Please respond";
  const instructions = block.instructions ||
    "Select a response. Your email application will open a prepared reply; send it without changing the response code.";

  return `
    <div style="margin-top:24px;padding:18px;border:1px solid #d6d6d6;
                border-radius:8px;background:#f8f9fa;">
      <div style="font-size:17px;font-weight:700;margin-bottom:8px;">
        ${escapeHtml(heading)}
      </div>
      <div style="margin-bottom:10px;">
        ${escapeHtml(instructions)}
      </div>
      <div style="margin:8px 0 10px 0;">
        ${buttons}
      </div>
      <div style="font-size:13px;color:#555555;margin-top:8px;">
        If the buttons do not open your email application, reply to this email
        with one of the commands shown below, followed by the response code:
        <strong>${
    actions.map((a) => escapeHtml(String(a.command).toUpperCase())).join(" or ")
  }</strong>
        <strong>${escapeHtml(responseCredential)}</strong>.
      </div>
      ${
    expiry
      ? `<div style="font-size:13px;color:#555555;margin-top:6px;">
        Please respond before ${escapeHtml(expiry)}.
      </div>`
      : ""
  }
    </div>`;
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  let requestedEmailQueueId: string | null = null;
  try {
    const requestBody = await req.json();
    requestedEmailQueueId = typeof requestBody?.email_queue_id === "string" &&
        requestBody.email_queue_id.trim()
      ? requestBody.email_queue_id.trim()
      : null;
  } catch {
    // An empty body retains the normal batch-processing behaviour.
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const replyAddress = Deno.env.get("MS_MAILBOX");

  if (!supabaseUrl || !serviceRoleKey) {
    return json(500, { error: "Missing Supabase environment variables" });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  try {
    let emailQuery = supabase
      .from("email_queue")
      .select("*")
      .eq("status", "pending");

    if (requestedEmailQueueId) {
      emailQuery = emailQuery.eq("id", requestedEmailQueueId);
    }

    const { data: emails, error } = await emailQuery
      .order("created_at")
      .limit(requestedEmailQueueId ? 1 : 20);

    if (error) {
      return json(500, { error: error.message });
    }

    let processed = 0;
    let failed = 0;

    for (const email of emails ?? []) {
      try {
        await supabase
          .from("email_queue")
          .update({
            status: "processing",
            processing_started_at: new Date().toISOString(),
            last_attempt_at: new Date().toISOString(),
            attempts: (email.attempts ?? 0) + 1,
          })
          .eq("id", email.id);

        let actionBlock = email.payload?.action_block as
          | EmailActionBlock
          | undefined;

        if (actionBlock && !replyAddress) {
          throw new Error("MS_MAILBOX is required for actionable email");
        }

        if ((actionBlock?.version ?? 1) >= 2) {
          if (!actionBlock?.request_id) {
            throw new Error("Version-2 action block has no Action Request ID");
          }

          const responseToken = generateResponseToken();
          const responseTokenHash = await sha256Hex(responseToken);
          const { data: tokenIssued, error: tokenError } = await supabase.rpc(
            "issue_email_action_response_token",
            {
              p_request_id: actionBlock.request_id,
              p_email_queue_id: email.id,
              p_response_token_hash: responseTokenHash,
            },
          );

          if (tokenError || tokenIssued !== true) {
            throw new Error(
              tokenError?.message ??
                "Unable to issue a single-use response token",
            );
          }

          // The plaintext token exists only in this function invocation and
          // the rendered outbound message. It is never written to the queue.
          actionBlock = { ...actionBlock, response_token: responseToken };
        }

        const bodyHtml = escapeHtml(String(email.body ?? ""))
          .replace(/\r?\n/g, "<br>");
        const actionHtml = actionBlock
          ? buildEmailActionBlock(actionBlock, replyAddress!)
          : "";

        const sendRes = await fetch(
          `${supabaseUrl}/functions/v1/send-graph-email`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${serviceRoleKey}`,
              apikey: serviceRoleKey,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              to: email.recipient_email,
              subject: email.subject,
              html: `
                <div style="font-family:Arial,sans-serif;line-height:1.45;color:#222222;">
                  ${bodyHtml}
                  ${actionHtml}
                </div>
              `,
              attachments: email.attachments ?? [],
            }),
          },
        );

        const sendText = await sendRes.text();
        let sendData: Record<string, unknown> = {};
        try {
          sendData = JSON.parse(sendText);
        } catch {
          sendData = { error: sendText };
        }

        if (!sendRes.ok) {
          throw new Error(
            String(sendData?.error ?? "Unknown send-graph-email error"),
          );
        }

        await supabase
          .from("email_queue")
          .update({
            status: "sent",
            sent_at: new Date().toISOString(),
            last_error: null,
          })
          .eq("id", email.id);

        processed++;
      } catch (err) {
        await supabase
          .from("email_queue")
          .update({
            status: "failed",
            last_error: err instanceof Error ? err.message : String(err),
          })
          .eq("id", email.id);

        failed++;
      }
    }

    return json(200, {
      success: true,
      processed,
      failed,
    });
  } catch (err) {
    return json(500, {
      error: err instanceof Error ? err.message : String(err),
    });
  }
});
