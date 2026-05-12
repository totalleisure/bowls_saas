// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

// Setup type definitions for built-in Supabase Runtime APIs
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  try {

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!

    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY)

    const body = await req.json()

    const club_id = body.club_id
    const confirm_text = body.confirm_text
    const delete_auth_users = body.delete_auth_users === true

    if (!club_id) {
      return json({ ok:false, error:"club_id required" },400)
    }

    if (confirm_text !== "RESET CLUB MEMBERS") {
      return json({ ok:false, error:'confirm_text must equal "RESET CLUB MEMBERS"' },400)
    }

    // get all member profiles for the club
    const { data: memberships } = await admin
      .from("club_memberships")
      .select("member_profile_id, role")
      .eq("club_id", club_id)

    if (!memberships || memberships.length === 0) {
      return json({ ok:true, message:"No members to reset" })
    }

    const profileIds = memberships
      .filter(m => m.role !== "admin" && m.role !== "superuser")
      .map(m => m.member_profile_id)

    if (profileIds.length === 0) {
      return json({ ok:true, message:"Only admins present — nothing reset" })
    }

    // gather auth ids before deleting profiles
    const { data: profiles } = await admin
      .from("member_profiles")
      .select("id,user_id")
      .in("id", profileIds)

    const authIds = (profiles ?? [])
      .map(p => p.user_id)
      .filter(Boolean)

    // delete operational rows
    await admin.from("fixture_rink_assignments").delete().in("member_profile_id", profileIds)
    await admin.from("team_selection_members").delete().in("member_profile_id", profileIds)
    await admin.from("team_members").delete().in("member_profile_id", profileIds)
    await admin.from("fixture_rsvps").delete().in("member_profile_id", profileIds)

    // null blocking references
    await admin.from("fixtures")
      .update({ captain_member_profile_id:null })
      .in("captain_member_profile_id", profileIds)

    await admin.from("fixtures")
      .update({ vice_captain_member_profile_id:null })
      .in("vice_captain_member_profile_id", profileIds)

    await admin.from("team_selections")
      .update({ published_by_member_profile_id:null })
      .in("published_by_member_profile_id", profileIds)

    await admin.from("team_selections")
      .update({ captain_member_profile_id:null })
      .in("captain_member_profile_id", profileIds)

    await admin.from("team_selections")
      .update({ vice_captain_member_profile_id:null })
      .in("vice_captain_member_profile_id", profileIds)

    await admin.from("teams")
      .update({ captain_member_profile_id:null })
      .in("captain_member_profile_id", profileIds)

    await admin.from("teams")
      .update({ vice_captain_member_profile_id:null })
      .in("vice_captain_member_profile_id", profileIds)

    await admin.from("teams")
      .update({ manager_member_profile_id:null })
      .in("manager_member_profile_id", profileIds)

    // delete club memberships
    await admin
      .from("club_memberships")
      .delete()
      .eq("club_id", club_id)
      .in("member_profile_id", profileIds)

    // delete pending invites
    await admin
      .from("club_invites")
      .delete()
      .eq("club_id", club_id)
      .eq("status", "pending")

    // delete profiles
    await admin
      .from("member_profiles")
      .delete()
      .in("id", profileIds)

    // optionally delete auth users
    if (delete_auth_users) {

      for (const authId of authIds) {

        const { data: stillExists } = await admin
          .from("member_profiles")
          .select("id")
          .eq("user_id", authId)
          .maybeSingle()

        if (!stillExists) {
          await admin.auth.admin.deleteUser(authId)
        }

      }
    }

    return json({
      ok:true,
      reset_profiles: profileIds.length,
      auth_deleted: delete_auth_users
    })

  } catch (err) {

    return json({
      ok:false,
      error: err instanceof Error ? err.message : String(err)
    },500)

  }
})

function json(data:unknown,status=200) {
  return new Response(
    JSON.stringify(data),
    { status, headers:{ "Content-Type":"application/json" } }
  )
}