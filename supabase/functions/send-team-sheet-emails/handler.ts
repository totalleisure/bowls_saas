
type Recipient = {
  member_profile_id?: string | null;
  email: string;
  type: "player" | "reserve" | "captain" | "vice_captain";
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
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" },
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

export async function handleRequest(req: Request, env: (name: string) => string | undefined, fetch: typeof globalThis.fetch = globalThis.fetch) {
  try {
    if (req.method === "OPTIONS") return json(200, { ok: true });
    if (req.method !== "POST") {
      return json(405, { error: "Method not allowed" });
    }

    const supabaseUrl = env("SUPABASE_URL");
    const serviceRoleKey = env("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceRoleKey) {
      return json(500, { error: "Missing Supabase environment variables" });
    }

    const authorization = req.headers.get("Authorization") ?? "";
    if (!/^Bearer \S+$/i.test(authorization)) return json(401, { error: "Sign in required" });
    const userResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: serviceRoleKey, Authorization: authorization },
    });
    if (!userResponse.ok) return json(401, { error: "Invalid session" });
    const user = await userResponse.json();
    if (!user.id || user.is_anonymous) return json(401, { error: "Sign in required" });

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


    if (typeof fixture_id !== "string" || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(fixture_id)) {
      return json(400, { error: "Invalid fixture ID" });
    }
    // Every privileged lookup is constrained by verified identity or fixture.
    async function rows(table: string, params: Record<string, string>) {
      const response = await fetch(`${supabaseUrl}/rest/v1/${table}?${new URLSearchParams(params)}`, {
        headers: { apikey: serviceRoleKey!, Authorization: `Bearer ${serviceRoleKey}` },
      });
      if (!response.ok) throw new Error("Authorization lookup failed");
      const data = await response.json();
      if (!Array.isArray(data)) throw new Error("Invalid authorization response");
      return data;
    }
    const fixtures = await rows("fixtures", { id: `eq.${fixture_id}`, select: "id,club_id,captain_member_profile_id,vice_captain_member_profile_id" });
    if (fixtures.length !== 1) return json(403, { error: "Fixture access denied" });
    const fixture = fixtures[0];
    const superusers = await rows("app_superusers", { user_id: `eq.${user.id}`, select: "user_id" });
    if (superusers.length !== 1) {
      const profiles = await rows("member_profiles", { user_id: `eq.${user.id}`, select: "id" });
      if (profiles.length !== 1) return json(403, { error: "Fixture access denied" });
      const profileId = profiles[0].id;
      const memberships = await rows("club_memberships", {
        club_id: `eq.${fixture.club_id}`, member_profile_id: `eq.${profileId}`,
        is_active: "eq.true", select: "role,is_active",
      });
      const membership = memberships[0];
      const allowed = membership?.is_active === true && (
        ["admin", "selector"].includes(membership.role) ||
        (membership.role !== "guest" && [fixture.captain_member_profile_id, fixture.vice_captain_member_profile_id].includes(profileId))
      );
      if (!allowed) return json(403, { error: "Fixture access denied" });
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
      const fixturePatchResp = await fetch(`${supabaseUrl}/rest/v1/fixtures?id=eq.${fixture_id}&club_id=eq.${fixture.club_id}`, {
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
}
