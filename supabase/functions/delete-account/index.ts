// delete-account — Apple 5.1.1(v) in-app account deletion.
// Mirrors the web app's deleteMyAccount server function: cascade-deletes all
// rows tied to the caller, purges their storage folder, then deletes the auth
// user. Guardian-linked athletes owned by someone else are only unlinked.
import { createClient } from "npm:@supabase/supabase-js@2";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user }, error: userError } = await userClient.auth.getUser();
    if (userError || !user) return json({ error: "Unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    if (body?.confirm !== "DELETE") {
      return json({ error: "Type DELETE to confirm" }, 400);
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Rows keyed to athletes the user OWNS (guardian-linked ones are unlinked below)
    const { data: owned } = await admin.from("athletes").select("id").eq("user_id", user.id);
    const athleteIds = (owned ?? []).map((a: { id: string }) => a.id);

    if (athleteIds.length > 0) {
      const athleteTables = [
        "athlete_college_interests",
        "athlete_contacts",
        "athlete_events",
        "athlete_photos",
        "athlete_videos",
        "athlete_guardians",
        "athlete_invites",
        "athlete_profile_views",
        "coach_saved_athletes",
        "messages",
      ];
      for (const table of athleteTables) {
        await admin.from(table).delete().in("athlete_id", athleteIds);
      }
    }

    // Rows keyed to the user themself
    await admin.from("athlete_guardians").delete().eq("user_id", user.id);
    await admin.from("coach_saved_athletes").delete().eq("coach_user_id", user.id);
    await admin.from("coach_saved_searches").delete().eq("coach_user_id", user.id);
    await admin.from("messages").delete().eq("coach_user_id", user.id);
    await admin.from("messages").delete().eq("sender_user_id", user.id);
    await admin.from("athlete_profile_views").delete().eq("viewer_user_id", user.id);
    await admin.from("notifications").delete().eq("user_id", user.id);
    await admin.from("coach_requests").delete().eq("user_id", user.id);
    await admin.from("athletes").delete().eq("user_id", user.id);
    await admin.from("user_roles").delete().eq("user_id", user.id);
    await admin.from("user_profiles").delete().eq("id", user.id);
    // user_blocks and content_reports cascade from the auth user deletion below

    // Best-effort storage purge of athlete-media/{userId}/ (incl. gallery subfolder)
    try {
      const bucket = admin.storage.from("athlete-media");
      const paths: string[] = [];
      const { data: rootFiles } = await bucket.list(user.id, { limit: 1000 });
      for (const f of rootFiles ?? []) {
        if (f.id) paths.push(`${user.id}/${f.name}`);
      }
      const { data: galleryFiles } = await bucket.list(`${user.id}/gallery`, { limit: 1000 });
      for (const f of galleryFiles ?? []) {
        if (f.id) paths.push(`${user.id}/gallery/${f.name}`);
      }
      if (paths.length > 0) await bucket.remove(paths);
    } catch (_) {
      // storage cleanup is best-effort; auth deletion below is the hard requirement
    }

    const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
    if (deleteError) return json({ error: deleteError.message }, 500);

    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
