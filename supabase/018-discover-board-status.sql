-- =============================================================================
-- 018 — Discover results carry board state and the next event date.
--
-- Added 2026-10-01 (Coach Mode 2C, spec §8.2). Same signature as 016's
-- search_published_athletes; each item gains:
--   board_stage      stage of the program's ACTIVE board entry, or null
--   next_event_date  the athlete's next event on/after today (America/Chicago), or null
-- Both are already visible to the coach through other RPCs; this avoids a
-- second round-trip per page. No change to filters, allowlist or pagination.
--
-- Requires 016, 017. Re-runnable.
-- =============================================================================

set check_function_bodies = off;

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
      when 'weekend' then today + ((7 - extract(isodow from today)::integer) % 7)
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
      exit;
    end if;
    items := items || (
      public.coach_athlete_card_json((select a from public.athletes a where a.id = r.id), r.dist)
      || jsonb_build_object(
           'board_stage', (select e.stage from public.program_board_entries e
                           where e.program_id = p_program_id and e.athlete_id = r.id and e.removed_at is null),
           'next_event_date', (select min(ev.event_date) from public.athlete_events ev
                               where ev.athlete_id = r.id and ev.event_date >= today)
         )
    );
    next_cursor := jsonb_build_object('k', r.k, 'id', r.id);
  end loop;

  if n <= lim then
    next_cursor := null;
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

-- Grants unchanged (016): authenticated may execute.
