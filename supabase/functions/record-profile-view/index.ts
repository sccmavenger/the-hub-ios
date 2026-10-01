// record-profile-view — logs that a signed-in user viewed an athlete's profile.
//
// 2026-10-01 (Coach Mode 2A, spec §6.8, decisions D7 / W8): a view is recorded
// only when the caller is allowed to see the athlete right now —
//   • athlete exists AND is published,
//   • the viewer is not blocked by the athlete's owner or any linked guardian,
//   • a coach viewer holds the derived coach role AND a verified membership in
//     the program they say they are viewing as (`programId`), which also
//     supplies the label athletes see ("CW University Men's Basketball").
// Self and guardian views never count; one view per viewer per athlete per 6 h.
//
// Every refusal returns 204 with no body so the endpoint cannot be used to
// learn whether an athlete id exists or is published (TECH-DEBT #9).
import { createClient } from "npm:@supabase/supabase-js@2";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
const skipped = () => new Response(null, { status: 204 });

const GENDER_LABEL: Record<string, string> = { mens: "Men's", womens: "Women's" };

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
    const programId = typeof body?.programId === "string" ? body.programId : null;
    if (!athleteId) return json({ error: "athleteId is required" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: athlete } = await admin
      .from("athletes")
      .select("id, user_id, is_published")
      .eq("id", athleteId)
      .maybeSingle();
    if (!athlete || !athlete.is_published) return skipped();

    // Self and guardian views never count
    if (athlete.user_id === user.id) return skipped();
    const { data: guardians } = await admin
      .from("athlete_guardians")
      .select("user_id")
      .eq("athlete_id", athleteId);
    const guardianIds = (guardians ?? []).map((g: { user_id: string }) => g.user_id);
    if (guardianIds.includes(user.id)) return skipped();

    // Blocked by the owner or any guardian → no view, no signal
    const { data: blocks } = await admin
      .from("user_blocks")
      .select("id")
      .eq("blocked_user_id", user.id)
      .in("blocker_user_id", [athlete.user_id, ...guardianIds])
      .limit(1);
    if (blocks && blocks.length > 0) return skipped();

    const { data: roles } = await admin
      .from("user_roles")
      .select("role")
      .eq("user_id", user.id);
    const roleSet = new Set((roles ?? []).map((r: { role: string }) => r.role));
    const viewerRole = roleSet.has("coach") ? "coach" : roleSet.has("admin") ? "admin" : "athlete";

    let viewerLabel: string | null = null;
    if (viewerRole === "coach") {
      // Coaches must name the program they are viewing as, and hold a verified
      // membership in it. The label is the verified program, never the
      // application's free-text claim.
      if (!programId) return skipped();
      const { data: membership } = await admin
        .from("coach_program_memberships")
        .select("status, recruiting_programs(institution_name, sport_gender, sport, active, verified_at)")
        .eq("coach_user_id", user.id)
        .eq("program_id", programId)
        .eq("status", "verified")
        .maybeSingle();
      const program = (membership as any)?.recruiting_programs;
      if (!membership || !program || !program.active || !program.verified_at) return skipped();
      const gender = GENDER_LABEL[program.sport_gender] ?? "";
      const sport = String(program.sport ?? "basketball");
      viewerLabel = `${program.institution_name} ${gender} ${sport.charAt(0).toUpperCase()}${sport.slice(1)}`.replace(/\s+/g, " ").trim();
    } else if (viewerRole === "admin") {
      viewerLabel = "The Hub staff";
    }

    // One view per viewer per athlete per 6 hours
    const since = new Date(Date.now() - 6 * 60 * 60 * 1000).toISOString();
    const { data: recent } = await admin
      .from("athlete_profile_views")
      .select("id")
      .eq("athlete_id", athleteId)
      .eq("viewer_user_id", user.id)
      .gte("created_at", since)
      .limit(1);
    if (recent && recent.length > 0) return skipped();

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
