-- =============================================================================
-- 016 — Coach Workspace security foundation and coach read surface.
--
-- Added 2026-10-01 per docs/COACH-MODE-WORKSPACE-SPEC.md §5–§6, §8.1, §11
-- (decisions D4–D9, D12, D16, D19, D22, D24; W3). Phase 2A of Coach Mode 2.0.
--
-- What changes for a coach:
--   • Coaches no longer SELECT the athletes table. The only coach paths to
--     athlete data are the RPCs here, which return an explicit SAFE-FIELD
--     ALLOWLIST (no DOB, test scores, NCAA id, zip, coordinates, consent
--     fields, user_id) and apply: coach role · verified membership in the
--     supplied program · athlete published · program gender · not blocked.
--   • Blocks apply to every coach read (photos, videos, events, contacts,
--     RPCs), not just message sends. A block by the athlete's owner OR any
--     linked guardian counts (W3: athlete blocks one coach, everywhere).
--   • Athlete-interest notifications route by verified membership, never by
--     the free-text application claim (D6).
--   • Athletes/guardians can only start threads with an active coach (D9).
--   • Admin is an exclusive role (D24).
--   • coach_directory_names labels coaches with the verified program and only
--     for users the caller actually relates to (thread, block, bookmark).
--   • coach_saved_searches become program-scoped (D27).
--
-- Deviation from spec §6.5 (helper grants): RLS policies execute as the
-- querying role, so EXECUTE on has_role / athlete_is_published / … cannot be
-- revoked from `authenticated` without breaking every policy. Instead
-- athlete_is_published() now returns false unless the caller is a coach,
-- admin, or manager of the athlete, which closes the publication oracle for
-- everyone else. The remaining helpers are caller-relative and leak nothing.
--
-- Requires 015 (storage_path / profile_photo_path, coach_is_blocked).
-- Re-runnable.
-- =============================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- 1. Helpers
-- ---------------------------------------------------------------------------

-- Caller holds a verified membership in an active, verified program.
create or replace function public.coach_has_program(p_program_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.has_role('coach') and exists (
    select 1
    from public.coach_program_memberships m
    join public.recruiting_programs p on p.id = m.program_id
    where m.coach_user_id = auth.uid()
      and m.program_id = p_program_id
      and m.status = 'verified'
      and p.active
      and p.verified_at is not null
  );
$$;

create or replace function public.coach_assert_program(p_program_id uuid)
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_program_id is null or not public.coach_has_program(p_program_id) then
    raise exception 'not authorized';
  end if;
end;
$$;

-- Does an arbitrary user currently hold the (derived) coach role?
create or replace function public.is_active_coach(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.user_roles where user_id = p_user_id and role = 'coach');
$$;

-- Publication oracle closed: only coaches, admins and the athlete's managers
-- get a true answer. Every policy that uses this does so inside a coach or
-- manager branch, so behavior for them is unchanged.
create or replace function public.athlete_is_published(aid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.athletes a where a.id = aid and a.is_published
  )
  and (
    public.has_role('coach')
    or public.has_role('admin')
    or public.can_manage_athlete(aid)
  );
$$;

-- Miles between two points (haversine). Null when either side is missing.
create or replace function public.coach_distance_miles(
  lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision
)
returns double precision
language sql
immutable
as $$
  select case
    when lat1 is null or lng1 is null or lat2 is null or lng2 is null then null
    else 3958.8 * 2 * asin(least(1.0, sqrt(
      power(sin(radians(lat2 - lat1) / 2), 2)
      + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
    )))
  end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Safe-field projection (spec §6.2). THE allowlist. Add a column here only
--    after a product decision; never return athletes.* to a coach.
-- ---------------------------------------------------------------------------
create or replace function public.coach_athlete_card_json(a public.athletes, p_distance double precision default null)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'athlete_id', a.id,
    'full_name', a.full_name,
    'profile_photo_path', a.profile_photo_path,
    'high_school', a.high_school,
    'hometown', a.hometown,
    'state', a.state,
    'grad_year', a.grad_year,
    'position', a.position,
    'jersey_number', a.jersey_number,
    'height_inches', a.height_inches,
    'weight_lbs', a.weight_lbs,
    'gpa', a.gpa,
    'bio', a.bio,
    'intended_major', a.intended_major,
    'instagram_handle', a.instagram_handle,
    'tiktok_handle', a.tiktok_handle,
    'sport_gender', a.sport_gender,
    'is_published', a.is_published,
    'distance_miles', case when p_distance is null then null else (round(p_distance / 5.0) * 5)::integer end
  );
$$;

-- ---------------------------------------------------------------------------
-- 3. Discover: search_published_athletes (spec §8.1)
--    Keyset pagination: cursor = jsonb {"k": sort key, "id": athlete id}.
--    Sort = distance when a center is supplied, else lower(full_name).
--    Hard cap 500 rows per query; page ≤ 50.
-- ---------------------------------------------------------------------------
create or replace function public.search_published_athletes(
  p_program_id uuid,
  p_query text default null,
  p_positions text[] default null,
  p_grad_years integer[] default null,
  p_center_lat double precision default null,
  p_center_lng double precision default null,
  p_radius_miles integer default null,
  p_states text[] default null,
  p_min_height_in integer default null,
  p_min_gpa numeric default null,
  p_playing_within text default null,
  p_cursor jsonb default null,
  p_limit integer default 25
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  prog public.recruiting_programs%rowtype;
  lim integer := least(greatest(coalesce(p_limit, 25), 1), 50);
  today date := (now() at time zone 'America/Chicago')::date;
  window_end date;
  use_distance boolean := p_center_lat is not null and p_center_lng is not null;
  cur_k text := p_cursor ->> 'k';
  cur_id uuid := nullif(p_cursor ->> 'id', '')::uuid;
  items jsonb := '[]'::jsonb;
  next_cursor jsonb := null;
  total integer := 0;
  r record;
  n integer := 0;
  q text := nullif(btrim(coalesce(p_query, '')), '');
begin
  perform public.coach_assert_program(p_program_id);
  select * into prog from public.recruiting_programs where id = p_program_id;

  if p_playing_within is not null then
    window_end := case p_playing_within
      when 'weekend' then today + ((7 - extract(isodow from today)::integer) % 7)   -- through the coming Sunday
      when '7d' then today + 7
      when '30d' then today + 30
      else null
    end;
    if window_end is null then
      raise exception 'invalid p_playing_within';
    end if;
  end if;
  if p_radius_miles is not null and p_radius_miles not in (25, 50, 100, 150, 250) then
    raise exception 'invalid p_radius_miles';
  end if;

  for r in
    with base as (
      select a.*,
             case when use_distance
                  then public.coach_distance_miles(p_center_lat, p_center_lng, a.latitude, a.longitude)
                  else null end as dist
      from public.athletes a
      where a.is_published
        and a.sport_gender = prog.sport_gender
        and not public.coach_is_blocked(a.id)
        and (q is null or a.full_name ilike '%' || q || '%')
        and (p_positions is null or exists (
              select 1 from unnest(p_positions) pos where a.position ilike '%' || pos || '%'))
        and (p_grad_years is null or a.grad_year = any(p_grad_years))
        and (p_states is null or upper(a.state) = any(select upper(s) from unnest(p_states) s))
        and (p_min_height_in is null or a.height_inches >= p_min_height_in)
        and (p_min_gpa is null or a.gpa >= p_min_gpa)
        and (p_playing_within is null or exists (
              select 1 from public.athlete_events e
              where e.athlete_id = a.id and e.event_date between today and window_end))
    ),
    filtered as (
      select *,
             case when use_distance then lpad(to_char(coalesce(dist, 99999), 'FM00000.000'), 10, '0')
                  else lower(full_name) end as k
      from base
      where (not use_distance or p_radius_miles is null or dist <= p_radius_miles)
    ),
    counted as (select count(*) as c from filtered),
    page as (
      select f.*, counted.c
      from filtered f, counted
      where cur_k is null or (f.k, f.id::text) > (cur_k, cur_id::text)
      order by f.k, f.id
      limit lim + 1
    )
    select * from page
  loop
    total := r.c;
    n := n + 1;
    if n > lim then
      exit;  -- a further page exists; next_cursor already points at the last emitted row
    end if;
    items := items || public.coach_athlete_card_json(
      (select a from public.athletes a where a.id = r.id), r.dist);
    next_cursor := jsonb_build_object('k', r.k, 'id', r.id);
  end loop;

  if n <= lim then
    next_cursor := null;  -- no further page
  end if;

  return jsonb_build_object(
    'items', items,
    'next_cursor', next_cursor,
    'total', least(total, 500),
    'program_id', p_program_id,
    'sport_gender', prog.sport_gender
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Athlete detail for a coach (spec §8.3). Contact appears only when the
--    program has saved the athlete (017 rewires this to the program board;
--    until then the legacy per-coach save counts).
-- ---------------------------------------------------------------------------
create or replace function public.coach_athlete_detail(p_program_id uuid, p_athlete_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  prog public.recruiting_programs%rowtype;
  a public.athletes%rowtype;
  contact_unlocked boolean;
  contact jsonb := null;
begin
  perform public.coach_assert_program(p_program_id);
  select * into prog from public.recruiting_programs where id = p_program_id;

  select * into a from public.athletes
  where id = p_athlete_id and is_published and sport_gender = prog.sport_gender;
  if not found or public.coach_is_blocked(p_athlete_id) then
    raise exception 'not found';   -- uniform: unpublished, wrong program, blocked all look the same
  end if;

  contact_unlocked := exists (
    select 1 from public.coach_saved_athletes s
    where s.athlete_id = p_athlete_id and s.coach_user_id = auth.uid()
  );
  if contact_unlocked then
    select jsonb_build_object(
      'athlete_email', c.athlete_email, 'athlete_phone', c.athlete_phone,
      'guardian_name', c.guardian_name, 'guardian_email', c.guardian_email, 'guardian_phone', c.guardian_phone,
      'club_coach_name', c.club_coach_name, 'club_coach_phone', c.club_coach_phone
    ) into contact
    from public.athlete_contacts c where c.athlete_id = p_athlete_id;
  end if;

  return jsonb_build_object(
    'athlete', public.coach_athlete_card_json(a, null),
    'photos', coalesce((
      select jsonb_agg(jsonb_build_object('id', ph.id, 'storage_path', ph.storage_path, 'caption', ph.caption, 'created_at', ph.created_at)
                       order by ph.created_at)
      from public.athlete_photos ph where ph.athlete_id = a.id and ph.storage_path is not null), '[]'::jsonb),
    'videos', coalesce((
      select jsonb_agg(jsonb_build_object('id', v.id, 'url', v.url, 'title', v.title) order by v.created_at)
      from public.athlete_videos v where v.athlete_id = a.id), '[]'::jsonb),
    'upcoming_events', coalesce((
      select jsonb_agg(jsonb_build_object('id', e.id, 'event_date', e.event_date, 'event_time', e.event_time,
                                          'opponent', e.opponent, 'location', e.location, 'notes', e.notes, 'is_mayb', e.is_mayb)
                       order by e.event_date, e.event_time)
      from public.athlete_events e
      where e.athlete_id = a.id
        and e.event_date between (now() at time zone 'America/Chicago')::date
                             and (now() at time zone 'America/Chicago')::date + 30), '[]'::jsonb),
    'contact_unlocked', contact_unlocked,
    'contact', contact,
    'board', null,           -- 017 fills this in
    'program_id', p_program_id
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Program staff roster (spec §11, D22) and a first home summary (spec §10;
--    017 adds board counts).
-- ---------------------------------------------------------------------------
create or replace function public.program_staff(p_program_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.coach_assert_program(p_program_id);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'user_id', m.coach_user_id,
             'display_name', coalesce(up.display_name, cr.full_name, 'Coach'),
             'title', m.title,
             'membership_role', m.membership_role,
             'verified_at', m.verified_at,
             'is_me', m.coach_user_id = auth.uid()
           ) order by (coalesce(m.membership_role, '') = 'head_coach') desc, coalesce(up.display_name, cr.full_name))
    from public.coach_program_memberships m
    left join public.user_profiles up on up.id = m.coach_user_id
    left join public.coach_requests cr on cr.user_id = m.coach_user_id
    where m.program_id = p_program_id
      and m.status = 'verified'
      and public.is_active_coach(m.coach_user_id)
  ), '[]'::jsonb);
end;
$$;

create or replace function public.coach_home_summary(p_program_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  perform public.coach_assert_program(p_program_id);
  return jsonb_build_object(
    'unread_threads', (
      select count(distinct m.athlete_id)
      from public.messages m
      where m.coach_user_id = auth.uid()
        and m.sender_user_id <> auth.uid()
        and m.read_at is null
        and not public.coach_is_blocked(m.athlete_id)),
    'saved_searches', (
      select count(*) from public.coach_saved_searches s
      where s.coach_user_id = auth.uid() and s.program_id = p_program_id),
    'board_counts', '{}'::jsonb,       -- 017
    'assigned_to_me', 0,               -- 017
    'recent_activity', '[]'::jsonb     -- 017
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. RLS: coaches leave the athletes table; blocks on every coach read.
-- ---------------------------------------------------------------------------
drop policy if exists "athletes select" on public.athletes;
create policy "athletes select" on public.athletes
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_guardian_of(id)
    or public.has_role('admin')
  );

drop policy if exists "photos select" on public.athlete_photos;
create policy "photos select" on public.athlete_photos
  for select to authenticated
  using (
    public.can_manage_athlete(athlete_id)
    or (public.athlete_is_published(athlete_id) and public.has_role('coach') and not public.coach_is_blocked(athlete_id))
  );

drop policy if exists "videos select" on public.athlete_videos;
create policy "videos select" on public.athlete_videos
  for select to authenticated
  using (
    public.can_manage_athlete(athlete_id)
    or (public.athlete_is_published(athlete_id) and public.has_role('coach') and not public.coach_is_blocked(athlete_id))
  );

drop policy if exists "events select" on public.athlete_events;
create policy "events select" on public.athlete_events
  for select to authenticated
  using (
    public.can_manage_athlete(athlete_id)
    or (public.athlete_is_published(athlete_id) and public.has_role('coach') and not public.coach_is_blocked(athlete_id))
  );

drop policy if exists "contacts select" on public.athlete_contacts;
create policy "contacts select" on public.athlete_contacts
  for select to authenticated
  using (
    public.can_manage_athlete(athlete_id)
    or (
      public.has_role('coach')
      and public.athlete_is_published(athlete_id)
      and not public.coach_is_blocked(athlete_id)
      and exists (
        select 1 from public.coach_saved_athletes s
        where s.athlete_id = athlete_contacts.athlete_id
          and s.coach_user_id = auth.uid()
      )
    )
  );

-- Athletes/guardians may only open a thread with an active coach (D9).
drop policy if exists "messages insert" on public.messages;
create policy "messages insert" on public.messages
  for insert to authenticated
  with check (
    sender_user_id = auth.uid()
    and (
      (coach_user_id = auth.uid()
        and public.has_role('coach')
        and public.athlete_is_published(athlete_id)
        and not public.coach_is_blocked(athlete_id))
      or (public.can_manage_athlete(athlete_id) and public.is_active_coach(coach_user_id))
    )
  );

-- Guardians' blocks count in the message trigger too (W3).
create or replace function public.enforce_message_blocks()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  athlete_owner uuid;
  blocked boolean;
begin
  select a.user_id into athlete_owner from public.athletes a where a.id = new.athlete_id;

  select exists (
    select 1 from public.user_blocks b
    where (b.blocker_user_id = new.sender_user_id
           and b.blocked_user_id in (new.coach_user_id, athlete_owner))
       or (b.blocked_user_id = new.sender_user_id
           and b.blocker_user_id in (new.coach_user_id, athlete_owner))
       or (b.blocker_user_id = athlete_owner and b.blocked_user_id = new.coach_user_id)
       or (b.blocker_user_id = new.coach_user_id and b.blocked_user_id = athlete_owner)
       or (b.blocked_user_id = new.coach_user_id
           and b.blocker_user_id in (select g.user_id from public.athlete_guardians g where g.athlete_id = new.athlete_id))
  ) into blocked;

  if blocked then
    raise exception 'This conversation is blocked. Unblock to send messages.';
  end if;

  return new;
end;
$$;

-- Saved searches are personal AND program-scoped (D27). 0 rows in prod.
alter table public.coach_saved_searches
  add column if not exists program_id uuid references public.recruiting_programs (id) on delete cascade;
update public.coach_saved_searches s
  set program_id = (
    select m.program_id from public.coach_program_memberships m
    where m.coach_user_id = s.coach_user_id and m.status = 'verified'
    order by m.verified_at desc limit 1)
  where s.program_id is null;
delete from public.coach_saved_searches where program_id is null;   -- unresolvable legacy rows (none in prod)
alter table public.coach_saved_searches alter column program_id set not null;

drop policy if exists "saved searches all" on public.coach_saved_searches;
create policy "saved searches all" on public.coach_saved_searches
  for all to authenticated
  using (coach_user_id = auth.uid() and public.coach_has_program(program_id))
  with check (coach_user_id = auth.uid() and public.coach_has_program(program_id));

-- ---------------------------------------------------------------------------
-- 7. Admin is an exclusive role (D24).
-- ---------------------------------------------------------------------------
create or replace function public.guard_admin_exclusive()
returns trigger
language plpgsql
as $$
begin
  if new.role = 'admin' and exists (
       select 1 from public.user_roles where user_id = new.user_id and role <> 'admin') then
    raise exception 'admin accounts cannot hold other roles';
  end if;
  if new.role <> 'admin' and exists (
       select 1 from public.user_roles where user_id = new.user_id and role = 'admin') then
    raise exception 'admin accounts cannot hold other roles';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_admin_exclusive on public.user_roles;
create trigger trg_guard_admin_exclusive
before insert on public.user_roles
for each row execute function public.guard_admin_exclusive();

-- ---------------------------------------------------------------------------
-- 8. Interest notifications by verified membership (D6).
-- ---------------------------------------------------------------------------
create or replace function public.notify_coaches_of_interest(_athlete_id uuid, _college_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  athlete_name text;
  athlete_pos text;
  athlete_grad int;
  athlete_gender text;
  published boolean;
  c record;
begin
  select a.full_name, a.position, a.grad_year, a.sport_gender, a.is_published
    into athlete_name, athlete_pos, athlete_grad, athlete_gender, published
  from public.athletes a where a.id = _athlete_id;

  if not coalesce(published, false) then
    return;
  end if;

  for c in
    select distinct m.coach_user_id
    from public.coach_program_memberships m
    join public.recruiting_programs p on p.id = m.program_id
    where m.status = 'verified'
      and p.active
      and p.verified_at is not null
      and (athlete_gender is null or p.sport_gender = athlete_gender)
      and public.normalize_college(p.institution_name) = public.normalize_college(_college_name)
      and public.normalize_college(p.institution_name) <> ''
      and public.is_active_coach(m.coach_user_id)
      and not exists (
        select 1 from public.user_blocks b
        where b.blocked_user_id = m.coach_user_id
          and (b.blocker_user_id = (select a.user_id from public.athletes a where a.id = _athlete_id)
               or b.blocker_user_id in (select g.user_id from public.athlete_guardians g where g.athlete_id = _athlete_id)))
  loop
    insert into public.notifications (user_id, type, title, body, link)
    values (
      c.coach_user_id,
      'interest',
      'An athlete listed your program',
      coalesce(athlete_name, 'An athlete')
        || coalesce(' (' || athlete_pos || ')', '')
        || coalesce(', class of ' || athlete_grad::text, '')
        || ' added ' || _college_name || ' to their target school list.',
      '/a/' || _athlete_id
    );
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. coach_directory_names: verified program label, related users only.
-- ---------------------------------------------------------------------------
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
    u.id,
    coalesce(p.display_name, cr.full_name, 'College coach'),
    coalesce(prog.institution_name, cr.college),
    coalesce(mem.title, cr.title)
  from unnest(_user_ids) as u(id)
  left join public.user_profiles p on p.id = u.id
  left join public.coach_requests cr on cr.user_id = u.id
  left join lateral (
    select m.title, m.program_id
    from public.coach_program_memberships m
    join public.recruiting_programs rp on rp.id = m.program_id
    where m.coach_user_id = u.id and m.status = 'verified' and rp.active and rp.verified_at is not null
    order by m.verified_at desc limit 1
  ) mem on true
  left join public.recruiting_programs prog on prog.id = mem.program_id
  where public.is_active_coach(u.id)
    and (
      public.has_role('admin')
      or u.id = auth.uid()
      -- shares a thread with an athlete the caller manages
      or exists (select 1 from public.messages msg
                 where msg.coach_user_id = u.id and public.can_manage_athlete(msg.athlete_id))
      -- saved an athlete the caller manages
      or exists (select 1 from public.coach_saved_athletes s
                 where s.coach_user_id = u.id and public.can_manage_athlete(s.athlete_id))
      -- the caller blocked them (Account → Blocked people)
      or exists (select 1 from public.user_blocks b
                 where b.blocker_user_id = auth.uid() and b.blocked_user_id = u.id)
    )
$$;

-- ---------------------------------------------------------------------------
-- 10. Grants
-- ---------------------------------------------------------------------------
revoke all on function public.coach_has_program(uuid) from public, anon;
grant execute on function public.coach_has_program(uuid) to authenticated;
revoke all on function public.coach_assert_program(uuid) from public, anon, authenticated;
revoke all on function public.is_active_coach(uuid) from public, anon;
grant execute on function public.is_active_coach(uuid) to authenticated;
revoke all on function public.coach_distance_miles(double precision, double precision, double precision, double precision) from public, anon, authenticated;
revoke all on function public.coach_athlete_card_json(public.athletes, double precision) from public, anon, authenticated;
revoke all on function public.guard_admin_exclusive() from public, anon, authenticated;

revoke all on function public.search_published_athletes(uuid, text, text[], integer[], double precision, double precision, integer, text[], integer, numeric, text, jsonb, integer) from public, anon;
grant execute on function public.search_published_athletes(uuid, text, text[], integer[], double precision, double precision, integer, text[], integer, numeric, text, jsonb, integer) to authenticated;
revoke all on function public.coach_athlete_detail(uuid, uuid) from public, anon;
grant execute on function public.coach_athlete_detail(uuid, uuid) to authenticated;
revoke all on function public.program_staff(uuid) from public, anon;
grant execute on function public.program_staff(uuid) to authenticated;
revoke all on function public.coach_home_summary(uuid) from public, anon;
grant execute on function public.coach_home_summary(uuid) to authenticated;
