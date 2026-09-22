import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type Recipient = {
  member_profile_id?: string | null;
  email: string;
  type: "player" | "reserve";
  name?: string;
};

type AttachmentInput = {
  name: string;
  contentType: string;
  contentBytes: string;
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function formatDateTime(value: string) {
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) return value;
  return dt.toLocaleString("en-GB", {
    dateStyle: "full",
    timeStyle: "short",
  });
}

serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return json(405, { error: "Method not allowed" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceRoleKey) {
      return json(500, { error: "Missing Supabase environment variables" });
    }

    const {
      fixture_id,
      club_name,
      opponent,
      start_at,
      recipients,
      attachment,
    }: {
      fixture_id: string;
      club_name: string;
      opponent: string;
      start_at: string;
      recipients: Recipient[];
      attachment?: AttachmentInput;
    } = await req.json();

    if (!fixture_id || !club_name || !opponent || !start_at || !Array.isArray(recipients)) {
      return json(400, {
        error: "Missing required fields: fixture_id, club_name, opponent, start_at, recipients",
      });
    }

    const subject = `Team sheet published: ${club_name} v ${opponent}`;
    const whenText = formatDateTime(start_at);

    const results: Array<Record<string, unknown>> = [];

    for (const r of recipients) {
      if (!r.email?.trim()) {
        results.push({
          email: r.email ?? "",
          type: r.type,
          status: "skipped",
          reason: "Missing email",
        });
        continue;
      }

      const greeting = r.name?.trim()
        ? `<p>Hello ${r.name.trim()},</p>`
        : "<p>Hello,</p>";

      let roleLine = '<p>You have been named in the published team sheet.</p>';

      if (r.type === 'captain') {
        roleLine = `
          <p>You are the <strong>Captain</strong> for this fixture.</p>
          <p>Please find the team sheet attached for your reference and distribution.</p>
        `;
      } else if (r.type === 'vice_captain') {
        roleLine = `
          <p>You are the <strong>Vice-Captain</strong> for this fixture.</p>
          <p>Please find the team sheet attached for your reference.</p>
        `;
      } else if (r.type === 'reserve') {
        roleLine = `
          <p>You have been named as a <strong>reserve</strong> in the published team sheet.</p>
        `;
      } else {
        roleLine = `
          <p>You have been selected as a <strong>player</strong> in the published team sheet.</p>
        `;
      }

      const html = `
        ${greeting}
        <p>The team sheet has now been published.</p>
        <p><strong>${club_name} v ${opponent}</strong></p>
        <p><strong>When:</strong> ${whenText}</p>
        ${roleLine}
        <p>Please find the team sheet attached.</p>
        <p>Please check the Bowls app for full details.</p>
      `;

      const sendResp = await fetch(`${supabaseUrl}/functions/v1/send-graph-email`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "apikey": serviceRoleKey,
          "Authorization": `Bearer ${serviceRoleKey}`,
        },
        body: JSON.stringify({
          to: r.email,
          subject,
          html,
          attachments: attachment ? [attachment] : [],
        }),
      });

      const sendText = await sendResp.text();
      let sendBody: unknown = sendText;
      try {
        sendBody = JSON.parse(sendText);
      } catch (_) {}

      const status = sendResp.ok ? "submitted" : "failed";

      const logResp = await fetch(`${supabaseUrl}/rest/v1/fixture_email_log`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "apikey": serviceRoleKey,
          "Authorization": `Bearer ${serviceRoleKey}`,
          "Prefer": "return=representation",
        },
        body: JSON.stringify({
          fixture_id,
          member_profile_id: r.member_profile_id ?? null,
          email_address: r.email,
          email_type: r.type,
          send_status: status,
          sent_at: sendResp.ok ? new Date().toISOString() : null,
          error_message: sendResp.ok ? null : JSON.stringify(sendBody),
          provider_response: sendBody,
        }),
      });

      const logText = await logResp.text();

      results.push({
        email: r.email,
        type: r.type,
        status,
        response: sendBody,
        log_status: logResp.status,
        log_response: logText,
      });
    }

    const submittedCount = results.filter((r) => r.status === "submitted").length;

    if (submittedCount > 0) {
      const fixturePatchResp = await fetch(`${supabaseUrl}/rest/v1/fixtures?id=eq.${fixture_id}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "apikey": serviceRoleKey,
          "Authorization": `Bearer ${serviceRoleKey}`,
          "Prefer": "return=representation",
        },
        body: JSON.stringify({
          last_team_sheet_emailed_at: new Date().toISOString(),
          last_team_sheet_email_count: submittedCount,
        }),
      });

      const fixturePatchText = await fixturePatchResp.text();

      return json(200, {
        success: true,
        count: results.length,
        results,
        fixture_patch_status: fixturePatchResp.status,
        fixture_patch_response: fixturePatchText,
      });
    }

    return json(200, {
      success: true,
      count: results.length,
      results,
      fixture_patch_status: null,
      fixture_patch_response: "No submitted emails; fixture not updated",
    });
    
  } catch (e) {
    return json(500, {
      error: e instanceof Error ? e.message : String(e),
    });
  }
});