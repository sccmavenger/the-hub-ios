-- =============================================================================
-- 020 — Notifications center, typed destinations, saved-search alerts.
--
-- Added 2026-10-01 per docs/COACH-MODE-WORKSPACE-SPEC.md §13 (2F) and
-- decisions D13, D17, D28.
--
--   • notifications.destination (019) is now filled for EVERY notification: a
--     BEFORE INSERT trigger maps the legacy web `link` strings to typed JSON so
--     older triggers need no change (D28 "map legacy strings").
--   • mark_notifications_read(p_ids default null) — own rows; null = all.
--   • unread_notification_count().
--   • Saved-search alerts (D13): the Discover query is refactored into an
--     internal function parameterized by coach + program + filters JSON so the
--     RPC and the scheduled job run the SAME predicates. run_saved_search_alerts()
--     runs hourly via pg_cron: the first run after alerts are enabled (or the
--     filters change) only seeds the baseline, later runs notify about athletes
--     not seen before. Eligibility (active coach, verified membership, blocks,
--     publication) is re-checked on every run; nothing is replayed.
--
-- Requires 016–019; pg_cron enabled 2026-10-01. Re-runnable.
-- =============================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- 1. Block helper parameterized by coach (jobs have no auth.uid()).
-- ---------------------------------------------------------------------------
create or replace function public.coach_is_blocked_for(p_coach_user_id uuid, p_athlete_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_blocks b
    where b.blocked_user_id = p_coach_user_id
      and (
        b.blocker_user_id = (select a.user_id from public.athletes a where a.id = p_athlete_id)
        or b.blocker_user_id in (select g.user_id from public.athlete_guardians g where g.athlete_id = p_athlete_id)
      )
  );
$$;

create or replace function public.coach_is_blocked(p_athlete_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.coach_is_blocked_for(auth.uid(), p_athlete_id);
$$;

-- ---------------------------------------------------------------------------
-- 2. Discover core, shared by the RPC and the alert job.
--    p_filters keys (= DiscoverFilters JSON): query, positions, grad_years,
--    center_lat, center_lng, radius_miles, states, min_height_inches, min_gpa,
--    playing_within.
-- ---------------------------------------------------------------------------
create or replace function public.coach_search_athletes_internal(
  p_coach_user_id uuid,
  p_program_id uuid,
  p_filters jsonb,
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
  q text := nullif(btrim(coalesce(p_filters ->> 'query', '')), '');
  positions text[] := case when jsonb_typeof(p_filters -> 'positions') = 'array' and jsonb_array_length(p_filters -> 'positions') > 0
                           then array(select jsonb_array_elements_text(p_filters -> 'positions')) end;
  grad_years integer[] := case when jsonb_typeof(p_filters -> 'grad_years') = 'array' and jsonb_array_length(p_filters -> 'grad_years') > 0
                              then array(select (jsonb_array_elements_text(p_filters -> 'grad_years'))::integer) end;
  states text[] := case when jsonb_typeof(p_filters -> 'states') = 'array' and jsonb_array_length(p_filters -> 'states') > 0
                        then array(select upper(jsonb_array_elements_text(p_filters -> 'states'))) end;
  center_lat double precision := nullif(p_filters ->> 'center_lat', '')::double precision;
  center_lng double precision := nullif(p_filters ->> 'center_lng', '')::double precision;
  radius_miles integer := nullif(p_filters ->> 'radius_miles', '')::integer;
  min_height integer := nullif(p_filters ->> 'min_height_inches', '')::integer;
  min_gpa numeric := nullif(p_filters ->> 'min_gpa', '')::numeric;
  playing_within text := nullif(p_filters ->> 'playing_within', '');
  use_distance boolean;
  cur_k text := p_cursor ->> 'k';
  cur_id uuid := nullif(p_cursor ->> 'id', '')::uuid;
  items jsonb := '[]'::jsonb;
  next_cursor jsonb := null;
  total integer := 0;
  r record;
  n integer := 0;
begin
  -- Eligibility for the named coach (the RPC already asserted; the job relies on this).
  if not exists (
    select 1 from coach_program_memberships m
    join recruiting_programs p on p.id = m.program_id
    where m.coach_user_id = p_coach_user_id and m.program_id = p_program_id
      and m.status = 'verified' and p.active and p.verified_at is not null
  ) or not public.is_active_coach(p_coach_user_id) then
    return jsonb_build_object('items', '[]'::jsonb, 'next_cursor', null, 'total', 0, 'program_id', p_program_id, 'sport_gender', null);
  end if;
  select * into prog from recruiting_programs where id = p_program_id;

  use_distance := center_lat is not null and center_lng is not null;
  if playing_within is not null then
    window_end := case playing_within
      when 'weekend' then today + ((7 - extract(isodow from today)::integer) % 7)
      when '7d' then today + 7
      when '30d' then today + 30
      else null end;
    if window_end is null then raise exception 'invalid p_playing_within'; end if;
  end if;
  if radius_miles is not null and radius_miles not in (25, 50, 100, 150, 250) then
    raise exception 'invalid p_radius_miles';
  end if;

  for r in
    with base as (
      select a.*,
             case when use_distance then public.coach_distance_miles(center_lat, center_lng, a.latitude, a.longitude) else null end as dist
      from public.athletes a
      where a.is_published
        and a.sport_gender = prog.sport_gender
        and not public.coach_is_blocked_for(p_coach_user_id, a.id)
        and (q is null or a.full_name ilike '%' || q || '%')
        and (positions is null or exists (select 1 from unnest(positions) pos where a.position ilike '%' || pos || '%'))
        and (grad_years is null or a.grad_year = any(grad_years))
        and (states is null or upper(a.state) = any(states))
        and (min_height is null or a.height_inches >= min_height)
        and (min_gpa is null or a.gpa >= min_gpa)
        and (playing_within is null or exists (
              select 1 from public.athlete_events e where e.athlete_id = a.id and e.event_date between today and window_end))
    ),
    filtered as (
      select *, case when use_distance then lpad(to_char(coalesce(dist, 99999), 'FM00000.000'), 10, '0') else lower(full_name) end as k
      from base
      where (not use_distance or radius_miles is null or dist <= radius_miles)
    ),
    counted as (select count(*) as c from filtered),
    page as (
      select f.*, counted.c from filtered f, counted
      where cur_k is null or (f.k, f.id::text) > (cur_k, cur_id::text)
      order by f.k, f.id
      limit lim + 1
    )
    select * from page
  loop
    total := r.c;
    n := n + 1;
    if n > lim then exit; end if;
    items := items || (
      public.coach_athlete_card_json((select a from public.athletes a where a.id = r.id), r.dist)
      || jsonb_build_object(
           'board_stage', (select e.stage from public.program_board_entries e
                           where e.program_id = p_program_id and e.athlete_id = r.id and e.removed_at is null),
           'next_event_date', (select min(ev.event_date) from public.athlete_events ev
                               where ev.athlete_id = r.id and ev.event_date >= today))
    );
    next_cursor := jsonb_build_object('k', r.k, 'id', r.id);
  end loop;
  if n <= lim then next_cursor := null; end if;

  return jsonb_build_object('items', items, 'next_cursor', next_cursor, 'total', least(total, 500),
                            'program_id', p_program_id, 'sport_gender', prog.sport_gender);
end;
$$;

-- Same signature as 016/018; now a thin wrapper.
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
begin
  perform public.coach_assert_program(p_program_id);
  return public.coach_search_athletes_internal(
    auth.uid(), p_program_id,
    jsonb_strip_nulls(jsonb_build_object(
      'query', p_query,
      'positions', to_jsonb(p_positions),
      'grad_years', to_jsonb(p_grad_years),
      'center_lat', p_center_lat,
      'center_lng', p_center_lng,
      'radius_miles', p_radius_miles,
      'states', to_jsonb(p_states),
      'min_height_inches', p_min_height_in,
      'min_gpa', p_min_gpa,
      'playing_within', p_playing_within)),
    p_cursor, p_limit);
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Notifications: typed destinations for legacy links; read helpers.
-- ---------------------------------------------------------------------------
create or replace function public.notification_destination_from_link(p_link text)
returns jsonb
language sql
immutable
as $$
  select case
    when p_link ~ '^/a/[0-9a-f-]{36}$' then jsonb_build_object('type', 'athlete', 'athlete_id', substring(p_link from 4))
    when p_link in ('/messages', '/coaches/messages') then jsonb_build_object('type', 'messages')
    when p_link = '/coach' then jsonb_build_object('type', 'coach_home')
    when p_link = '/coach/application' then jsonb_build_object('type', 'coach_application')
    when p_link = '/admin/coaches' then jsonb_build_object('type', 'admin_coaches')
    when p_link = '/admin/reports' then jsonb_build_object('type', 'admin_reports')
    when p_link = '/coaches/discover' then jsonb_build_object('type', 'discover')
    else null
  end;
$$;

create or replace function public.trg_notification_destination()
returns trigger
language plpgsql
as $$
begin
  if new.destination is null and new.link is not null then
    new.destination := public.notification_destination_from_link(new.link);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notification_destination on public.notifications;
create trigger trg_notification_destination
before insert on public.notifications
for each row execute function public.trg_notification_destination();

-- Backfill existing rows (small table).
update public.notifications set destination = public.notification_destination_from_link(link)
where destination is null and link is not null;

create or replace function public.mark_notifications_read(p_ids uuid[] default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  n integer;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  update public.notifications set read_at = now()
  where user_id = auth.uid() and read_at is null and (p_ids is null or id = any(p_ids));
  get diagnostics n = row_count;
  return n;
end;
$$;

create or replace function public.unread_notification_count()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer from public.notifications where user_id = auth.uid() and read_at is null;
$$;

-- ---------------------------------------------------------------------------
-- 4. Saved-search alerts (D13)
-- ---------------------------------------------------------------------------
alter table public.coach_saved_searches
  add column if not exists notified_athlete_ids uuid[],
  add column if not exists last_alert_at timestamptz;

-- Turning alerts on or changing the filters restarts the baseline so old
-- results are never replayed as "new".
create or replace function public.trg_saved_search_reseed()
returns trigger
language plpgsql
as $$
begin
  if (new.alerts_enabled and not coalesce(old.alerts_enabled, false))
     or new.filters is distinct from old.filters
     or new.program_id is distinct from old.program_id then
    new.notified_athlete_ids := null;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_saved_search_reseed on public.coach_saved_searches;
create trigger trg_saved_search_reseed
before update on public.coach_saved_searches
for each row execute function public.trg_saved_search_reseed();

create or replace function public.run_saved_search_alerts()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  s record;
  res jsonb;
  matches uuid[];
  fresh uuid[];
  names text;
  searched integer := 0;
  seeded integer := 0;
  notified integer := 0;
  skipped integer := 0;
begin
  for s in
    select ss.*, p.institution_name
    from public.coach_saved_searches ss
    join public.recruiting_programs p on p.id = ss.program_id
    where ss.alerts_enabled
    order by ss.created_at
  loop
    -- Eligibility is re-checked every run; the internal search returns empty
    -- for a suspended coach or a lost membership.
    if not public.is_active_coach(s.coach_user_id) then
      skipped := skipped + 1;
      continue;
    end if;
    searched := searched + 1;
    res := public.coach_search_athletes_internal(s.coach_user_id, s.program_id, coalesce(s.filters, '{}'::jsonb), null, 50);
    matches := array(select (it ->> 'athlete_id')::uuid from jsonb_array_elements(res -> 'items') it);

    if s.notified_athlete_ids is null then
      -- First run after enabling (or editing): baseline only.
      update public.coach_saved_searches
        set notified_athlete_ids = matches, last_run_at = now()
        where id = s.id;
      seeded := seeded + 1;
      continue;
    end if;

    fresh := array(select unnest(matches) except select unnest(s.notified_athlete_ids));
    if cardinality(fresh) > 0 then
      select string_agg(a.full_name, ', ' order by a.full_name) into names
      from public.athletes a where a.id = any(fresh[1:3]);
      insert into public.notifications (user_id, type, title, body, link, destination)
      values (
        s.coach_user_id, 'saved_search',
        case when cardinality(fresh) = 1 then '1 new athlete matches “' || s.name || '”'
             else cardinality(fresh) || ' new athletes match “' || s.name || '”' end,
        coalesce(names, '') || case when cardinality(fresh) > 3 then ' and ' || (cardinality(fresh) - 3) || ' more' else '' end,
        '/coaches/discover',
        jsonb_build_object('type', 'saved_search', 'saved_search_id', s.id, 'program_id', s.program_id)
      );
      notified := notified + 1;
    end if;

    update public.coach_saved_searches
      set notified_athlete_ids = (select array_agg(distinct x) from unnest(s.notified_athlete_ids || matches) x),
          last_run_at = now(),
          last_alert_at = case when cardinality(fresh) > 0 then now() else last_alert_at end
      where id = s.id;
  end loop;

  return jsonb_build_object('searched', searched, 'seeded', seeded, 'notified', notified, 'skipped', skipped);
end;
$$;

-- Hourly, at :15. Re-runnable: unschedule any prior copy first.
do $$
begin
  perform cron.unschedule(jobid) from cron.job where jobname = 'saved-search-alerts';
  perform cron.schedule('saved-search-alerts', '15 * * * *', 'select public.run_saved_search_alerts()');
end $$;

-- ---------------------------------------------------------------------------
-- 5. Grants
-- ---------------------------------------------------------------------------
revoke all on function public.coach_is_blocked_for(uuid, uuid) from public, anon;
grant execute on function public.coach_is_blocked_for(uuid, uuid) to authenticated;   -- used by coach_is_blocked inside policies
revoke all on function public.coach_search_athletes_internal(uuid, uuid, jsonb, jsonb, integer) from public, anon, authenticated;
revoke all on function public.notification_destination_from_link(text) from public, anon, authenticated;
revoke all on function public.trg_notification_destination() from public, anon, authenticated;
revoke all on function public.trg_saved_search_reseed() from public, anon, authenticated;
revoke all on function public.run_saved_search_alerts() from public, anon, authenticated;
revoke all on function public.mark_notifications_read(uuid[]) from public, anon;
grant execute on function public.mark_notifications_read(uuid[]) to authenticated;
revoke all on function public.unread_notification_count() from public, anon;
grant execute on function public.unread_notification_count() to authenticated;
