export const APP_STORE = "https://apps.apple.com/gb/app/total-leisure-bowls/id6762380407";
export const HELP_EMAIL = "bowls@totalleisure.com";
export const GUIDE_LABELS = {
  introduction: "Member introduction",
  android: "Android & Samsung installation guide",
};
export const escapeHtml = (value: string) =>
  value.replace(
    /[&<>"']/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!),
  );

// The on-screen review and HTML message use exactly the same text.
export function invitationContent(firstName: string, email: string, club: string) {
  return {
    subject: `${firstName}, welcome to your Bowls Club App`,
    club,
    greeting: `Hello ${firstName},`,
    introduction:
      "Your club account has been set up, and we’re pleased to invite you to start using the Bowls Club App. Keep up with fixtures and events, reply to team selections and arrange your rink bookings — all in one place.",
    email,
    sections: [
      {
        title: "Your login details",
        text:
          `Email address: ${email}\nUse your current password. If you do not know it, choose Forgotten password on the sign-in screen to set a new one. You already have an account — there is no need to register again.`,
      },
      {
        title: "1. Get the app",
        text:
          "iPhone or iPad: download Total Leisure Bowls using the App Store button below.\nAndroid or Samsung: email bowls@totalleisure.com to request the Android installation file. The attached Android & Samsung guide explains the steps.",
        link: APP_STORE,
        link_label: "Download for iPhone / iPad",
      },
      {
        title: "2. Sign in and make it yours",
        text:
          `Open the app, enter your email address and password, then choose Sign In. Select ${club} from your club list.\nOpen Member and Volunteer Lists → Account and Security if you would like to change your password. Please also check your membership details and choose which contact information other members can see.`,
      },
      {
        title: "3. See what’s happening",
        text:
          "• Check your dashboard for upcoming fixtures and requests.\n• View the club diary and rink availability.\n• Reply when asked about availability or team selection.\n• Use My Fixture Bookings to arrange a rink booking.\nPrompt replies help our captains and selectors organise teams. Please check the app regularly for updates.",
      },
      {
        title: "Two guides to help you get started",
        text:
          "Member introduction — signing in, finding your way around and making a rink booking.\nAndroid & Samsung installation guide — installing the app on your phone or tablet.",
      },
      {
        title: "Need a hand?",
        text:
          `Email ${HELP_EMAIL} and we’ll help you get started. If you forget your password, choose Forgotten password on the sign-in screen.`,
        link: `mailto:${HELP_EMAIL}`,
        link_label: HELP_EMAIL,
      },
    ],
    closing: `We look forward to seeing you on the green.\nYour ${club} team`,
  };
}

export function invitationHtml(content: ReturnType<typeof invitationContent>) {
  const e = (s: string) => escapeHtml(s).replaceAll("\n", "<br>");
  const sections = content.sections.map((s, i) =>
    `<tr><td style="padding:0 32px 24px"><div style="padding:18px;background:${
      i === 4 ? "#faf4e4" : i === 0 ? "#f0f6f2" : "#ffffff"
    }"><h2 style="font-size:20px;margin:0 0 12px;color:#153f32">${
      e(s.title)
    }</h2><p style="font-size:15px;line-height:24px;margin:0">${e(s.text)}</p>${
      s.link
        ? `<p style="margin:18px 0 0"><a href="${
          escapeHtml(s.link)
        }" style="display:inline-block;background:#24694f;color:#fff;padding:14px 20px;border-radius:7px;text-decoration:none">${
          e(s.link_label!)
        }</a></p>`
        : ""
    }</div></td></tr>`
  ).join("");
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:#edf2ee;font-family:Arial,Helvetica,sans-serif;color:#243b32"><table role="presentation" width="100%"><tr><td align="center" style="padding:24px 8px"><table role="presentation" cellspacing="0" cellpadding="0" width="640" style="width:100%;max-width:640px;background:white;border-radius:16px;overflow:hidden"><tr><td style="background:#153f32;color:white;padding:30px 32px;border-top:7px solid #d9b85b"><p style="color:#e1cc91">${
    e(content.club)
  }</p><h1 style="font-size:34px">Your club.<br>Now at your fingertips.</h1><p>Welcome to the Bowls Club App</p></td></tr><tr><td style="padding:28px 32px"><h2>${
    e(content.greeting)
  }</h2><p style="font-size:16px;line-height:25px">${
    e(content.introduction)
  }</p></td></tr>${sections}<tr><td style="padding:0 32px 30px;line-height:25px">${
    e(content.closing)
  }</td></tr><tr><td style="background:#153f32;color:#e4d7ad;padding:18px;text-align:center">Fixtures. Teams. Rink bookings.</td></tr></table></td></tr></table></body></html>`;
}

export function invitationEligibility(
  active: boolean,
  previous: { id: string; status: string } | null,
  resend: boolean,
) {
  if (!active) return "Inactive membership — activate before inviting";
  if (previous?.status === "sending" || previous?.status === "unknown") {
    return "Sending or outcome uncertain — check Sent Items before any further invitation";
  }
  if (previous?.status === "sent" && !resend) {
    return "Already invited — select Resend invitations to include";
  }
  return null;
}
