import "@supabase/functions-js/edge-runtime.d.ts";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function normalizeHeader(value: string): string {
  return value
    .replace(/^\uFEFF/, "") // strip UTF-8 BOM
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "_");
}

export function parseCsv(text: string): Record<string, string>[] {
  const records: { cells: string[]; line: number }[] = [];
  let cells: string[] = [], field = "", quoted = false, line = 1, startLine = 1;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      if (quoted && text[i + 1] === '"') { field += '"'; i++; }
      else { quoted = !quoted; }
    } else if (c === "," && !quoted) {
      cells.push(field); field = "";
    } else if ((c === "\n" || c === "\r") && !quoted) {
      cells.push(field);
      if (cells.some((v) => v.trim())) records.push({ cells, line: startLine });
      cells = []; field = "";
      if (c === "\r" && text[i + 1] === "\n") i++;
      line++; startLine = line;
    } else {
      field += c;
      if (c === "\n") line++;
    }
  }
  if (quoted) throw new Error("CSV has an unterminated quoted field");
  cells.push(field);
  if (cells.some((v) => v.trim())) records.push({ cells, line: startLine });
  if (!records.length) return [];
  const headers = records.shift()!.cells.map(normalizeHeader);
  if (new Set(headers).size !== headers.length) throw new Error("CSV has duplicate headers");
  return records.map(({ cells, line }) => {
    if (cells.length !== headers.length) throw new Error(`CSV row ${line}: incorrect number of columns`);
    const row: Record<string, string> = { _row: String(line) };
    headers.forEach((h, i) => { row[h] = cells[i].trim(); });
    return row;
  });
}

export function optionalProfileValues(row: Record<string, string>) {
  const optional = (value?: string) => value?.trim() || null;
  // Normalize explicit labels only; never infer ambiguous gender.
  const suppliedGender = optional(row.gender)?.toLowerCase().replace(/[ -]+/g, "_");
  const allowed = ["male", "female", "non_binary", "prefer_to_self_describe", "prefer_not_to_say"];
  return {
    title: optional(row.title),
    gender: suppliedGender && allowed.includes(suppliedGender) ? suppliedGender : null,
    // Club-approved mapping: only explicit Male/Female populate both fields.
    sex_at_birth: suppliedGender === "male" || suppliedGender === "female" ? suppliedGender : null,
    outdoor_club: optional(row.outdoor_club),
    phone: optional(row.mobile_phone),
  };
}

export function missingProfileUpdates(
  existing: Record<string, unknown>,
  supplied: Record<string, string | null>,
): Record<string, string> {
  const updates: Record<string, string> = {};
  for (const [key, value] of Object.entries(supplied)) {
    if (!String(existing[key] ?? "").trim() && value) updates[key] = value;
  }
  return updates;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), {
  status, headers: { ...corsHeaders, "Content-Type": "application/json" },
});

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ ok: false, error: "Method not allowed" }, 405);
  const token = req.headers.get("Authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!token) return json({ ok: false, error: "Sign in to import members" }, 401);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) return json({ ok: false, error: "Missing server configuration" }, 500);
    const admin = createClient(url, key, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    // Verify the token with Auth; never trust client-supplied roles or metadata.
    const { data: caller, error: authError } = await admin.auth.getUser(token);
    if (authError || !caller.user) return json({ ok: false, error: "Invalid session" }, 401);

    let body;
    try { body = await req.json(); }
    catch { return json({ ok: false, error: "Invalid JSON body" }, 400); }
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json({ ok: false, error: "Invalid request" }, 400);
    }
    const { club_id, storage_path, new_members_active } = body;
    if (typeof club_id !== "string" || !/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(club_id) ||
        typeof storage_path !== "string" || !storage_path.startsWith(`${club_id}/`) ||
        storage_path.includes("\\") || storage_path.includes("%") ||
        storage_path.split("/").some((part: string) => !part || part === "." || part === "..") ||
        typeof new_members_active !== "boolean") {
      return json({ ok: false, error: "Provide a club, a CSV path within that club, and an Active/Inactive choice" }, 400);
    }

    // Privileged reads below are limited to checking this verified caller.
    const { data: superuser, error: superError } = await admin.from("app_superusers")
      .select("user_id").eq("user_id", caller.user.id).maybeSingle();
    if (superError) throw superError;
    if (!superuser) {
      const { data: profile, error: profileError } = await admin.from("member_profiles")
        .select("id").eq("user_id", caller.user.id).maybeSingle();
      if (profileError) throw profileError;
      if (!profile) return json({ ok: false, error: "Club administrator access required" }, 403);
      const { data: permission, error: permissionError } = await admin.from("club_memberships")
        .select("id").eq("club_id", club_id).eq("member_profile_id", profile.id)
        .eq("role", "admin").eq("is_active", true).maybeSingle();
      if (permissionError) throw permissionError;
      if (!permission) return json({ ok: false, error: "Club administrator access required" }, 403);
    }

    // No storage download, account listing or mutation occurs before authorization.
    const { data: file, error: downloadError } = await admin.storage.from("Imports").download(storage_path);
    if (downloadError || !file) return json({ ok: false, error: "Could not read the selected CSV" }, 400);
    let rows: Record<string, string>[];
    try { rows = parseCsv(await file.text()); }
    catch (error) { return json({ ok: false, error: error instanceof Error ? error.message : String(error) }, 400); }

    const usersByEmail = new Map<string, string>();
    // Paginate so repeat imports also find accounts beyond the first page.
    const pageSize = 1000;
    for (let page = 1; ; page++) {
      const { data, error } = await admin.auth.admin.listUsers({ page, perPage: pageSize });
      if (error) throw error;
      for (const user of data.users) if (user.email) usersByEmail.set(user.email.toLowerCase(), user.id);
      if (data.users.length < pageSize) break;
    }

    let created = 0, linked = 0, existingMemberships = 0, errors = 0;
    const report: Record<string, unknown>[] = [];
    const manual_review: Record<string, unknown>[] = [];
    const seenEmails = new Set<string>();
    for (const row of rows) {
      const email = (row.email ?? "").trim().toLowerCase();
      const first_name = (row.first_name ?? row.firstname ?? "").trim();
      const last_name = (row.last_name ?? row.lastname ?? "").trim();
      const password = (row.password ?? "").trim();
      const values = optionalProfileValues(row);
      if (!email && !values.phone) {
        manual_review.push({ row: row._row, first_name, last_name, reason: "Neither email nor mobile phone supplied" });
        continue;
      }
      if (!email) {
        errors++;
        report.push({ row: row._row, status: "error", email, message: "Email required by current importer; mobile phone supplied. Review manually; do not invent an email." });
        continue;
      }
      if (seenEmails.has(email)) {
        report.push({ row: row._row, email, status: "skipped_duplicate_in_csv" });
        continue;
      }
      seenEmails.add(email);
      try {
        const warnings = row.gender?.trim() && !values.gender
          ? ["Gender not recognized; left unsupplied for manual review"] : [];
        let userId = usersByEmail.get(email);
        const newAccount = !userId;
        const displayName = [first_name, last_name].filter(Boolean).join(" ") || email;
        if (!userId) {
          if (!password) throw new Error("New accounts require a CSV password; no invitation was sent.");
          const { data, error } = await admin.auth.admin.createUser({
            email, password, email_confirm: true,
            // handle_new_user reads display_name when automatically creating the profile.
            user_metadata: { display_name: displayName },
          });
          if (error) throw error;
          userId = data.user?.id;
          if (!userId) throw new Error("Account creation returned no user id");
          usersByEmail.set(email, userId);
          created++;
        }
        const { data: profile, error: profileError } = await admin.from("member_profiles")
          .select("id, first_name, last_name, email_address, display_name, title, gender, sex_at_birth, outdoor_club, phone")
          .eq("user_id", userId).maybeSingle();
        if (profileError) throw profileError;
        let profileId = profile?.id;
        let profileChanged = false;
        if (!profileId) {
          const { data, error } = await admin.from("member_profiles")
            .insert({ user_id: userId, first_name, last_name, email_address: email, display_name: displayName, ...values })
            .select("id").single();
          if (error) throw error;
          profileId = data.id;
          profileChanged = true;
        } else {
          const updates = missingProfileUpdates(profile, { first_name, last_name, email_address: email, ...values });
          // Repair only an empty or email-placeholder display name; keep custom names.
          const currentName = String(profile.display_name ?? "").trim();
          const fullName = [updates.first_name ?? profile.first_name, updates.last_name ?? profile.last_name]
            .map(value => String(value ?? "").trim()).filter(Boolean).join(" ");
          if (fullName && (!currentName || currentName.toLowerCase() === email ||
              currentName.toLowerCase() === String(profile.email_address ?? "").trim().toLowerCase())) {
            updates.display_name = fullName;
          }
          if (Object.keys(updates).length) {
            const { error } = await admin.from("member_profiles").update(updates).eq("id", profileId);
            if (error) throw error;
            profileChanged = true;
          }
        }
        // ON CONFLICT DO NOTHING preserves existing role/status, including concurrent imports.
        const { data: inserted, error: membershipError } = await admin.from("club_memberships")
          .upsert({ club_id, member_profile_id: profileId, role: "member", is_active: new_members_active },
            { onConflict: "club_id,member_profile_id", ignoreDuplicates: true })
          .select("id");
        if (membershipError) throw membershipError;
        const membershipCreated = (inserted?.length ?? 0) > 0;
        if (membershipCreated) linked++; else existingMemberships++;
        report.push({ row: row._row, email, warnings,
          status: membershipCreated ? (newAccount ? "created_and_linked" : "linked_existing_account")
            : profileChanged ? "updated_profile_existing_membership" : "already_linked_no_changes" });
      } catch (error) {
        errors++;
        report.push({ row: row._row, email, status: "error", message: error instanceof Error ? error.message : String(error) });
      }
    }
    return json({ ok: true,
      summary: { created, invited: 0, linked, existing_memberships: existingMemberships, errors,
        manual_review: manual_review.length, total: rows.length }, report, manual_review });
  } catch {
    return json({ ok: false, error: "Import could not complete. Check the server configuration and permissions." }, 500);
  }
});
