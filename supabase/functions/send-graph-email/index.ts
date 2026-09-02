import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type MailAttachment = {
  name: string;
  contentType: string;
  contentBytes: string; // base64
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return json(405, { error: "Method not allowed" });
    }

    const { to, subject, html, attachments } = await req.json();

    const tenantId = Deno.env.get("MS_TENANT_ID");
    const clientId = Deno.env.get("MS_CLIENT_ID");
    const clientSecret = Deno.env.get("MS_CLIENT_SECRET");
    const mailbox = Deno.env.get("MS_MAILBOX");

    if (!tenantId || !clientId || !clientSecret || !mailbox) {
      return json(500, { error: "Missing Microsoft Graph environment variables" });
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
    const accessToken = tokenData.access_token;

    if (!accessToken) {
      return json(500, {
        error: "Failed to get access token",
        details: tokenData,
      });
    }

    const graphAttachments = ((attachments ?? []) as MailAttachment[]).map((a) => ({
      "@odata.type": "#microsoft.graph.fileAttachment",
      name: a.name,
      contentType: a.contentType,
      contentBytes: a.contentBytes,
    }));

    const toList = Array.isArray(to) ? to : [to];

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
              content: html,
            },
            toRecipients: toList.map((email: string) => ({
              emailAddress: { address: email },
            })),
            attachments: graphAttachments,
          },
          saveToSentItems: true,
        }),
      },
    );

    if (!emailRes.ok) {
      const errorText = await emailRes.text();
      return json(emailRes.status, {
        error: "Graph sendMail failed",
        details: errorText,
      });
    }

    return json(200, {
      success: true,
      attachment_count: graphAttachments.length,
    });
  } catch (err) {
    return json(500, {
      error: err instanceof Error ? err.message : String(err),
    });
  }
});
