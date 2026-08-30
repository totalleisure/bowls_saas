import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type GraphMessage = {
  id?: string;
  subject?: string;
  bodyPreview?: string;
  receivedDateTime?: string;
  from?: {
    emailAddress?: {
      address?: string;
    };
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

async function getGraphToken(): Promise<string> {
  const tenantId = Deno.env.get("MS_TENANT_ID");
  const clientId = Deno.env.get("MS_CLIENT_ID");
  const clientSecret = Deno.env.get("MS_CLIENT_SECRET");

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
      `Failed to obtain Microsoft Graph token: ${JSON.stringify(tokenData)}`,
    );
  }

  return String(tokenData.access_token);
}

function parseResponse(message: GraphMessage): {
  command: string;
  responseCode: string;
} | null {
  const subject = String(message.subject ?? "");
  const preview = String(message.bodyPreview ?? "");
  const text = `${subject}\n${preview}`;

  const match = text.match(/\b(ACCEPT|DECLINE)\s+(BWL-[A-F0-9]{12})\b/i);
  if (!match) return null;

  return {
    command: match[1].toUpperCase(),
    responseCode: match[2].toUpperCase(),
  };
}

serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const mailbox = Deno.env.get("MS_MAILBOX");

  if (!supabaseUrl || !serviceRoleKey || !mailbox) {
    return json(500, {
      error: "Missing Supabase or Microsoft mailbox environment variables",
    });
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey);

  try {
    const graphToken = await getGraphToken();

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

        const parsed = parseResponse(message);
        if (!parsed) continue;
        matched++;

        const sender = String(
          message.from?.emailAddress?.address ?? "",
        ).trim().toLowerCase();

        const { data: result, error: responseError } = await supabase.rpc(
          "apply_email_action_response",
          {
            p_response_code: parsed.responseCode,
            p_command: parsed.command,
            p_sender_email: sender,
            p_graph_message_id: message.id,
            p_received_at: message.receivedDateTime ??
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
      throw new Error(`Unable to save inbox delta cursor: ${saveError.message}`);
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
});
