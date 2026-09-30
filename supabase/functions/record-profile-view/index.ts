// record-profile-view — mirrors the web app's recordProfileView server function:
// never counts self/guardian views, dedupes to one view per viewer per athlete
// per 6 hours, labels coach views with their program.
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
    const athleteId = typeof body?.athleteId === "string" ? body.athleteId : null;
    if (!athleteId) return json({ error: "athleteId is required" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: athlete } = await admin
      .from("athletes")
      .select("id, user_id")
      .eq("id", athleteId)
      .maybeSingle();
    if (!athlete) return json({ error: "Athlete not found" }, 404);

    // Self and guardian views never count
    if (athlete.user_id === user.id) return json({ skipped: "self" });
    const { data: guardianLink } = await admin
      .from("athlete_guardians")
      .select("id")
      .eq("athlete_id", athleteId)
      .eq("user_id", user.id)
      .maybeSingle();
    if (guardianLink) return json({ skipped: "guardian" });

    // One view per viewer per athlete per 6 hours
    const since = new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString();
    const { data: recent } = await admin
      .from("athlete_profile_views")
      .select("id")
      .eq("athlete_id", athleteId)
      .eq("viewer_user_id", user.id)
      .gte("created_at", since)
      .limit(1);
    if (recent && recent.length > 0) return json({ skipped: "dedupe" });

    const { data: roles } = await admin
      .from("user_roles")
      .select("role")
      .eq("user_id", user.id);
    const roleSet = new Set((roles ?? []).map((r: { role: string }) => r.role));
    const viewerRole = roleSet.has("coach") ? "coach" : roleSet.has("admin") ? "admin" : "athlete";

    let viewerLabel: string | null = null;
    if (viewerRole === "coach") {
      const { data: request } = await admin
        .from("coach_requests")
        .select("college")
        .eq("user_id", user.id)
        .maybeSingle();
      viewerLabel = request?.college ?? "College program";
    }

    const { error: insertError } = await admin.from("athlete_profile_views").insert({
      athlete_id: athleteId,
      viewer_user_id: user.id,
      viewer_role: viewerRole,
      viewer_label: viewerLabel,
    });
    if (insertError) return json({ error: insertError.message }, 500);

    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
