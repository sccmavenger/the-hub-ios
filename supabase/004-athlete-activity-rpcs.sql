-- =============================================================================
-- 004 — Athlete activity drill-ins.
--
-- Athletes can't read coach_saved_athletes rows (stage/tags/notes are the
-- coach's private pipeline) or coach identities (user_profiles/coach_requests
-- are owner/admin-only). These SECURITY DEFINER functions expose exactly the
-- slice an athlete may see: who saved them + when, and name/program labels
-- for coaches they already share a thread with.
-- =============================================================================

set check_function_bodies = off;

-- Who bookmarked this athlete (identity + date only — no stage/tags/notes).
create or replace function public.bookmarks_for_athlete(_athlete_id uuid)
returns table (
  coach_user_id uuid,
  coach_name text,
  college text,
  title text,
  saved_at timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    s.coach_user_id,
    coalesce(p.display_name, cr.full_name, 'College coach'),
    cr.college,
    cr.title,
    s.created_at
  from public.coach_saved_athletes s
  left join public.user_profiles p on p.id = s.coach_user_id
  left join public.coach_requests cr on cr.user_id = s.coach_user_id
  where s.athlete_id = _athlete_id
    and public.can_manage_athlete(_athlete_id)
  order by s.created_at desc
$$;

revoke all on function public.bookmarks_for_athlete(uuid) from public, anon;
grant execute on function public.bookmarks_for_athlete(uuid) to authenticated;

-- Name/program labels for approved coaches (for message-thread headers).
create or replace function public.coach_directory_names(_user_ids uuid[])
returns table (
  user_id uuid,
  coach_name text,
  college text,
  title text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    cr.user_id,
    coalesce(p.display_name, cr.full_name, 'College coach'),
    cr.college,
    cr.title
  from public.coach_requests cr
  left join public.user_profiles p on p.id = cr.user_id
  where cr.user_id = any(_user_ids)
    and cr.status = 'approved'
$$;

revoke all on function public.coach_directory_names(uuid[]) from public, anon;
grant execute on function public.coach_directory_names(uuid[]) to authenticated;
