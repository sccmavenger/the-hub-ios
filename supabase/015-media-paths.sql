-- =============================================================================
-- 015 — Protected media: store object paths, sign on read, per-row policies.
--
-- Added 2026-10-01 per docs/COACH-MODE-WORKSPACE-SPEC.md §7 (decisions D1–D3,
-- W7). Closes TECH-DEBT #6 (1-year signed URLs stored in DB) and #32 (coach
-- storage policy keyed on the uploader's folder, which leaked a guardian's
-- other children's media).
--
-- Model after this migration:
--   • athlete_photos.storage_path / athletes.profile_photo_path hold the
--     canonical object path inside the private `athlete-media` bucket.
--   • Clients request SHORT-LIVED signed URLs (iOS: 60 min) from the Storage
--     API for those paths. Storage enforces the storage.objects SELECT
--     policies below, so authorization is per photo row, not per folder:
--       - owner folder (unchanged)
--       - managers (owner / guardian / admin) of the athlete the row belongs to
--       - coaches: coach role AND athlete published AND the object is
--         referenced by that athlete's photo/profile row AND the coach is not
--         blocked by the athlete or a guardian
--   • Legacy `url` columns are kept read-only for one release so older
--     clients keep working; new writes store paths only. Schedule: null the
--     url columns in 2.1 once all clients read paths.
--   • Why no SQL signing RPC: Supabase signs URLs in the Storage service with
--     its own secret; SQL cannot mint them. The storage RLS policy *is* the
--     authorization boundary (spec §7 amended accordingly).
--
-- Backfill parses the object path out of each stored signed URL
-- (/storage/v1/object/sign/athlete-media/<path>?token=…), sets storage_path
-- ONLY when the object exists in storage.objects, and reports counts. Nothing
-- is deleted or overwritten.
--
-- Re-runnable.
-- =============================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- 1. Columns
-- ---------------------------------------------------------------------------
alter table public.athlete_photos add column if not exists storage_path text;
alter table public.athletes add column if not exists profile_photo_path text;

create index if not exists idx_athlete_photos_storage_path
  on public.athlete_photos (storage_path) where storage_path is not null;
create index if not exists idx_athletes_profile_photo_path
  on public.athletes (profile_photo_path) where profile_photo_path is not null;

-- ---------------------------------------------------------------------------
-- 2. Block helper (shared with 016). True when the CALLER (a coach) has been
--    blocked by the athlete's owner or by any linked guardian.
-- ---------------------------------------------------------------------------
create or replace function public.coach_is_blocked(p_athlete_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_blocks b
    where b.blocked_user_id = auth.uid()
      and (
        b.blocker_user_id = (select a.user_id from public.athletes a where a.id = p_athlete_id)
        or b.blocker_user_id in (select g.user_id from public.athlete_guardians g where g.athlete_id = p_athlete_id)
      )
  );
$$;

-- Which athlete does a storage object belong to? Resolved through the photo /
-- profile rows, never through the folder name.
create or replace function public.media_athlete_for_object(p_object_name text)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select ph.athlete_id from public.athlete_photos ph where ph.storage_path = p_object_name limit 1),
    (select a.id from public.athletes a where a.profile_photo_path = p_object_name limit 1)
  );
$$;

-- May the CALLING coach see this athlete at all? Published and not blocked.
-- SECURITY DEFINER on purpose: policy subqueries run with the caller's
-- privileges, and coaches cannot select the athletes table (016), so a plain
-- EXISTS against athletes would always be false for them.
create or replace function public.coach_can_view_athlete(p_athlete_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_role('coach')
    and exists (select 1 from public.athletes a where a.id = p_athlete_id and a.is_published)
    and not public.coach_is_blocked(p_athlete_id);
$$;

-- ---------------------------------------------------------------------------
-- 3. Backfill from legacy signed URLs (verified against storage.objects).
-- ---------------------------------------------------------------------------
do $$
declare
  parsed integer := 0;
  verified integer := 0;
  missing integer := 0;
  r record;
  path text;
begin
  for r in
    select 'photo' as kind, id, url as src from public.athlete_photos where storage_path is null and url is not null
    union all
    select 'profile', id, profile_photo_url from public.athletes where profile_photo_path is null and profile_photo_url is not null
  loop
    path := substring(r.src from '/object/sign/athlete-media/([^?]+)');
    if path is null then
      -- Public-URL form from before the bucket went private (setup.sql).
      path := substring(r.src from '/object/public/athlete-media/([^?]+)');
    end if;
    if path is null then
      continue;
    end if;
    parsed := parsed + 1;
    if exists (select 1 from storage.objects o where o.bucket_id = 'athlete-media' and o.name = path) then
      verified := verified + 1;
      if r.kind = 'photo' then
        update public.athlete_photos set storage_path = path where id = r.id;
      else
        update public.athletes set profile_photo_path = path where id = r.id;
      end if;
    else
      missing := missing + 1;
      raise notice 'media backfill: object missing for % % (%)', r.kind, r.id, path;
    end if;
  end loop;
  raise notice 'media backfill: parsed=% verified=% missing=%', parsed, verified, missing;
end $$;

-- ---------------------------------------------------------------------------
-- 4. storage.objects SELECT policies (replace the folder-based coach rule).
-- ---------------------------------------------------------------------------
drop policy if exists "coaches read published athlete media" on storage.objects;
create policy "coaches read published athlete media" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'athlete-media'
    and public.coach_can_view_athlete(public.media_athlete_for_object(storage.objects.name))
  );

-- Guardians (and admins, already covered) read the media of athletes they
-- manage even when the file sits under another manager's folder; the athlete
-- reads files a guardian uploaded for them.
drop policy if exists "managers read athlete media" on storage.objects;
create policy "managers read athlete media" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'athlete-media'
    and public.can_manage_athlete(public.media_athlete_for_object(storage.objects.name))
  );

-- "athlete media owner read" (folder = own uid) and "admins read athlete media"
-- from 002 are unchanged.

-- ---------------------------------------------------------------------------
-- 5. Grants
-- ---------------------------------------------------------------------------
-- Used inside policies, which run as the querying role, so authenticated needs
-- EXECUTE. Neither function leaks anything the caller could not already learn
-- (coach_is_blocked is caller-relative; media_athlete_for_object needs an
-- exact object name).
revoke all on function public.coach_is_blocked(uuid) from public, anon;
grant execute on function public.coach_is_blocked(uuid) to authenticated;
revoke all on function public.media_athlete_for_object(text) from public, anon;
grant execute on function public.media_athlete_for_object(text) to authenticated;
revoke all on function public.coach_can_view_athlete(uuid) from public, anon;
grant execute on function public.coach_can_view_athlete(uuid) to authenticated;
