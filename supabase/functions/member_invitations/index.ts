import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import { parseCsv } from "../_shared/member_csv.ts";
import { GUIDE_LABELS, invitationContent, invitationEligibility, invitationHtml } from "./email.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
const uuid = (v: unknown): v is string =>
  typeof v === "string" && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(v);
const bucket = "MemberInvitationGuides";
class UserError extends Error {}
const requireData = <R extends { data: unknown; error: unknown }>(result: R): R["data"] => {
  if (result.error) throw new Error("Database or storage request failed");
  return result.data;
};
const present = <T>(data: T): NonNullable<T> => {
  if (data == null) throw new Error("Expected data was not returned");
  return data;
};
type Guide = { kind: string; name: string; path: string };

export function validatePdf(base64: unknown): Uint8Array {
  if (typeof base64 !== "string" || base64.length > 2000000) {
    throw new UserError("Choose a PDF smaller than 1.5 MB.");
  }
  let raw: string;
  try {
    raw = atob(base64);
  } catch {
    throw new UserError("The PDF could not be read.");
  }
  if (!raw.startsWith("%PDF-") || raw.length > 1500000) {
    throw new UserError("Choose a valid PDF smaller than 1.5 MB.");
  }
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

export async function handleInvitation(req: Request) {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const token = req.headers.get("Authorization")?.match(/^Bearer\s+(\S+)$/i)?.[1];
  if (!token) return json({ error: "Please sign in." }, 401);
  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { data: caller, error } = await admin.auth.getUser(token);
    if (error || !caller.user) return json({ error: "Please sign in again." }, 401);
    // Bound uploads and reject malformed bodies before any privileged data read.
    const raw = await req.text();
    if (raw.length > 2100000) return json({ error: "Request too large." }, 413);
    let body;
    try {
      body = JSON.parse(raw);
    } catch {
      return json({ error: "Invalid request." }, 400);
    }
    if (!body || !uuid(body.club_id)) return json({ error: "Select a club." }, 400);
    const clubId = body.club_id;
    const superuser = requireData(
      await admin.from("app_superusers").select("user_id").eq("user_id", caller.user.id)
        .maybeSingle(),
    );
    if (!superuser) {
      const profile = requireData(
        await admin.from("member_profiles").select("id").eq("user_id", caller.user.id)
          .maybeSingle(),
      );
      if (!profile) return json({ error: "Club administrator access required." }, 403);
      const permission = requireData(
        await admin.from("club_memberships").select("id").eq("club_id", clubId).eq(
          "member_profile_id",
          profile.id,
        ).eq("role", "admin").eq("is_active", true).maybeSingle(),
      );
      if (!permission) return json({ error: "Club administrator access required." }, 403);
    }
    const club = present(
      requireData(await admin.from("clubs").select("name").eq("id", clubId).single()),
    );
    const guides = async (): Promise<Guide[]> =>
      present(
        requireData(
          await admin.from("member_invitation_guides").select("kind,name,path").eq(
            "club_id",
            clubId,
          ),
        ),
      );
    const signedGuides = async (items: Guide[]) =>
      await Promise.all(
        items.map(async (g) => ({
          ...g,
          url: present(requireData(await admin.storage.from(bucket).createSignedUrl(g.path, 3600)))
            .signedUrl,
        })),
      );

    if (body.action === "guides") return json({ guides: await signedGuides(await guides()) });
    if (body.action === "upload_guide") {
      if (!Object.hasOwn(GUIDE_LABELS, body.kind)) throw new UserError("Select a guide type.");
      const bytes = validatePdf(body.content);
      const kind = body.kind as keyof typeof GUIDE_LABELS;
      // Never overwrite the bytes of a document already included in a review.
      const path = `${clubId}/${kind}/${crypto.randomUUID()}.pdf`;
      requireData(
        await admin.storage.from(bucket).upload(path, bytes, {
          contentType: "application/pdf",
          upsert: false,
        }),
      );
      requireData(
        await admin.from("member_invitation_guides").upsert({
          club_id: clubId,
          kind,
          name: `${GUIDE_LABELS[kind]}.pdf`,
          path,
          updated_at: new Date().toISOString(),
        }),
      );
      return json({ guides: await signedGuides(await guides()) });
    }

    if (body.action === "preview") {
      const path = body.storage_path;
      if (
        typeof path !== "string" || !path.startsWith(`${clubId}/`) || path.includes("\\") ||
        path.includes("%") || path.split("/").some((p) => !p || p === "." || p === "..") ||
        typeof body.resend !== "boolean"
      ) throw new UserError("Choose a CSV and whether to resend invitations.");
      const docs = await guides();
      if (
        docs.length !== 2 || !docs.some((g) => g.kind === "introduction") ||
        !docs.some((g) => g.kind === "android")
      ) throw new UserError("Add both PDF guides before preparing invitations.");
      // Fail before review if an attachment is missing or no longer readable.
      let guideBytes = 0;
      for (const g of docs) {
        guideBytes += present(requireData(await admin.storage.from(bucket).download(g.path))).size;
      }
      if (guideBytes > 2800000) {
        throw new UserError(
          "The two guides together must be smaller than 2.8 MB. Replace one with a smaller PDF.",
        );
      }
      const file = present(requireData(await admin.storage.from("Imports").download(path)));
      if (file.size > 2000000) throw new UserError("Choose a CSV smaller than 2 MB.");
      let rows;
      try {
        rows = parseCsv(await file.text());
      } catch {
        throw new UserError("The CSV could not be read. Check its headings and quoted values.");
      }
      if (!rows.length || rows.length > 250) {
        throw new UserError("Choose between 1 and 250 members per invitation review.");
      }
      const recipients = [], seen = new Set<string>();
      const exceptions: { row: string; email: string; name: string; reason: string }[] = [];
      if (
        body.excluded_emails !== undefined &&
        (!Array.isArray(body.excluded_emails) ||
          body.excluded_emails.some((e: unknown) => typeof e !== "string"))
      ) throw new UserError("Invalid import exception list.");
      const excluded = new Set<string>(
        (body.excluded_emails || []).map((e: string) => e.trim().toLowerCase()),
      );
      for (const row of rows) {
        const email = row.email?.trim().toLowerCase();
        const issue = (reason: string) =>
          exceptions.push({
            row: row._row,
            email: email || "",
            name: [row.first_name, row.last_name].filter(Boolean).join(" "),
            reason,
          });
        if (!email) {
          issue("No email address — review manually");
          continue;
        }
        if (excluded.has(email)) {
          issue("This row failed during import — review before inviting");
          continue;
        }
        if (seen.has(email)) {
          issue("Duplicate email in CSV — included once");
          continue;
        }
        seen.add(email);
        // Exact, case-insensitive lookup: escape LIKE wildcards supplied in addresses.
        const escaped = email.replace(/[\\%_]/g, (c) => `\\${c}`);
        const profiles = present(
          requireData(
            await admin.from("member_profiles").select(
              "id,user_id,first_name,last_name,email_address",
            ).ilike("email_address", escaped),
          ),
        );
        if (profiles.length !== 1 || !profiles[0].user_id) {
          issue("No unique existing member matches this email");
          continue;
        }
        const profile = profiles[0];
        const membership = requireData(
          await admin.from("club_memberships").select("id,is_active").eq("club_id", clubId).eq(
            "member_profile_id",
            profile.id,
          ).maybeSingle(),
        );
        if (!membership) {
          issue("Not a member of this club — import or review first");
          continue;
        }
        const account = requireData(await admin.auth.admin.getUserById(profile.user_id));
        if (account.user?.email?.toLowerCase() !== email) {
          issue("Login email differs from the CSV — review before inviting");
          continue;
        }
        const previous = requireData(
          await admin.from("member_invitation_attempts").select("id,status").eq(
            "membership_id",
            membership.id,
          ).in("status", ["sending", "sent", "unknown"]).maybeSingle(),
        );
        const reason = invitationEligibility(membership.is_active, previous, body.resend);
        if (reason) {
          issue(reason);
          continue;
        }
        const firstName = profile.first_name?.trim() || row.first_name?.trim() || "Member";
        const preview = invitationContent(firstName, email, club.name);
        const attempt = {
          id: crypto.randomUUID(),
          club_id: clubId,
          membership_id: membership.id,
          created_by: caller.user.id,
          email,
          user_id: profile.user_id,
          first_name: firstName,
          subject: preview.subject,
          html: invitationHtml(preview),
          preview,
          guides: docs,
          previous_sent_id: previous?.status === "sent" ? previous.id : null,
        };
        requireData(await admin.from("member_invitation_attempts").insert(attempt));
        recipients.push({
          id: attempt.id,
          email,
          name: `${firstName} ${profile.last_name || ""}`.trim(),
          preview,
          resend: !!attempt.previous_sent_id,
        });
      }
      return json({ recipients, exceptions, guides: await signedGuides(docs) });
    }

    if (body.action === "send") {
      if (!uuid(body.invitation_id) || body.confirm !== true) {
        throw new UserError("Review the invitation before sending.");
      }
      const attempt = requireData(
        await admin.from("member_invitation_attempts").select("*").eq("id", body.invitation_id).eq(
          "club_id",
          clubId,
        ).eq("created_by", caller.user.id).maybeSingle(),
      );
      if (!attempt) return json({ error: "Invitation review not found." }, 404);
      if (attempt.status !== "pending") return json({ status: attempt.status });
      if (Date.parse(attempt.created_at) < Date.now() - 86400000) {
        throw new UserError("This review has expired. Prepare a new review.");
      }
      // Recheck current membership and login email; never send a stale reviewed address.
      const membership = requireData(
        await admin.from("club_memberships").select("id,is_active,member_profile_id").eq(
          "id",
          attempt.membership_id,
        ).eq("club_id", clubId).maybeSingle(),
      );
      if (!membership?.is_active) {
        throw new UserError("Membership is now inactive or removed. Prepare a new review.");
      }
      const profile = present(
        requireData(
          await admin.from("member_profiles").select("user_id,email_address").eq(
            "id",
            membership.member_profile_id,
          ).single(),
        ),
      );
      const account = requireData(await admin.auth.admin.getUserById(attempt.user_id));
      if (
        profile.user_id !== attempt.user_id ||
        profile.email_address?.toLowerCase() !== attempt.email ||
        account.user?.email?.toLowerCase() !== attempt.email
      ) throw new UserError("The member’s email has changed. Prepare a new review.");
      const attachments = [];
      let guideBytes = 0;
      for (const guide of attempt.guides as Guide[]) {
        const file = present(requireData(await admin.storage.from(bucket).download(guide.path)));
        const bytes = new Uint8Array(await file.arrayBuffer());
        guideBytes += bytes.length;
        if (guideBytes > 2800000) {
          throw new UserError(
            "The attached guides are too large. Prepare a new review with smaller PDFs.",
          );
        }
        let binary = "";
        for (let i = 0; i < bytes.length; i += 8192) {
          binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
        }
        attachments.push({
          "@odata.type": "#microsoft.graph.fileAttachment",
          name: guide.name,
          contentType: "application/pdf",
          contentBytes: btoa(binary),
        });
      }
      const tenant = Deno.env.get("MS_TENANT_ID"),
        clientId = Deno.env.get("MS_CLIENT_ID"),
        secret = Deno.env.get("MS_CLIENT_SECRET"),
        mailbox = Deno.env.get("MS_MAILBOX");
      if (!tenant || !clientId || !secret || !mailbox) {
        throw new UserError("Invitation email is not configured yet. Please contact support.");
      }
      const tokenResponse = await fetch(
        `https://login.microsoftonline.com/${encodeURIComponent(tenant)}/oauth2/v2.0/token`,
        {
          method: "POST",
          signal: AbortSignal.timeout(20000),
          body: new URLSearchParams({
            client_id: clientId,
            client_secret: secret,
            scope: "https://graph.microsoft.com/.default",
            grant_type: "client_credentials",
          }),
        },
      );
      if (!tokenResponse.ok) throw new Error("Email authentication unavailable");
      const accessToken = (await tokenResponse.json()).access_token;
      if (!accessToken) throw new Error("Email authentication unavailable");
      const claimed = requireData(
        await admin.rpc("claim_member_invitation", {
          p_id: attempt.id,
          p_club: clubId,
          p_caller: caller.user.id,
        }),
      );
      if (!claimed) {
        return json({
          status: "skipped",
          message: "Already processed or the review is no longer current. Prepare a new review.",
        });
      }
      // A timeout after submission is uncertain, not safe to retry automatically.
      let status = "unknown";
      try {
        const result = await fetch(
          `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(mailbox)}/sendMail`,
          {
            method: "POST",
            signal: AbortSignal.timeout(25000),
            headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
            body: JSON.stringify({
              message: {
                subject: attempt.subject,
                body: { contentType: "HTML", content: attempt.html },
                toRecipients: [{ emailAddress: { address: attempt.email } }],
                attachments,
              },
              saveToSentItems: true,
            }),
          },
        );
        status = result.status === 202
          ? "sent"
          : result.status >= 400 && result.status < 500 && result.status !== 408
          ? "failed"
          : "unknown";
      } catch { /* Keep unknown to prevent an accidental duplicate. */ }
      requireData(
        await admin.from("member_invitation_attempts").update({
          status,
          updated_at: new Date().toISOString(),
        }).eq("id", attempt.id).eq("status", "sending"),
      );
      return json({ status });
    }
    return json({ error: "Unknown action." }, 400);
  } catch (e) {
    return json({
      error: e instanceof UserError
        ? e.message
        : "The invitation request could not complete. Nothing will be retried automatically. Please review the results.",
    }, e instanceof UserError ? 400 : 500);
  }
}

Deno.serve(handleInvitation);
