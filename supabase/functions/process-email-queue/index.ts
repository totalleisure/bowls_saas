import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

serve(async () => {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    // ---------------------------------------------
    // Fetch pending emails
    // ---------------------------------------------

    const { data: emails, error } = await supabase
      .from("email_queue")
      .select("*")
      .eq("status", "pending")
      .order("created_at")
      .limit(20);

    if (error) {
      return json(500, {
        error: error.message,
      });
    }

    let processed = 0;
    let failed = 0;

    for (const email of emails ?? []) {
      try {
        // -----------------------------------------
        // Mark processing
        // -----------------------------------------

        await supabase
          .from("email_queue")
          .update({
            status: "processing",
            processing_started_at: new Date().toISOString(),
            last_attempt_at: new Date().toISOString(),
            attempts: (email.attempts ?? 0) + 1,
          })
          .eq("id", email.id);

        // -----------------------------------------
        // Call send-graph-email
        // -----------------------------------------

        const sendRes = await fetch(
          `${Deno.env.get("SUPABASE_URL")}/functions/v1/send-graph-email`,
          {
            method: "POST",
            headers: {
              Authorization:
                `Bearer ${Deno.env.get("SUPABASE_ANON_KEY")}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              to: email.recipient_email,
              subject: email.subject,
              html: `
                <div style="font-family: Arial, sans-serif;">
                  ${String(email.body).replace(/\n/g, "<br>")}
                </div>
              `,
            }),
          },
        );

        const sendData = await sendRes.json();

        if (!sendRes.ok) {
          throw new Error(
            sendData?.error ??
              "Unknown send-graph-email error",
          );
        }

        // -----------------------------------------
        // Mark sent
        // -----------------------------------------

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
            last_error:
              err instanceof Error
                ? err.message
                : String(err),
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
      error:
        err instanceof Error
          ? err.message
          : String(err),
    });
  }
});