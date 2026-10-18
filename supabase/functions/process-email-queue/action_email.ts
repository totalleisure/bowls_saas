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

export function buildEmailActionBlock(
  block: EmailActionBlock | null | undefined,
  replyAddress: string,
  viewBase?: string,
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

  const viewUrl = viewBase && token ? new URL(viewBase) : null;
  if (viewUrl) { viewUrl.searchParams.set('code', code); viewUrl.searchParams.set('token', token); }
  const viewButton = viewUrl ? `<a href="${escapeHtml(viewUrl.href)}" style="display:inline-block;margin:6px 8px 6px 0;padding:12px 18px;border-radius:6px;background:#174f87;color:white;text-decoration:none;font-weight:700;">View fixture</a>` : '';
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
        ${buttons}${viewButton}
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
