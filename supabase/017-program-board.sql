-- =============================================================================
-- 017 — Program-owned Recruiting Board, private notes, contact unlock.
--
-- Added 2026-10-01 per docs/COACH-MODE-WORKSPACE-SPEC.md §9, §10, §12
-- (decisions D11, D21, D25, D26, D30; W4–W6). Phase 2B of Coach Mode 2.0.
--
--   • program_board_entries   — the shared board: one row per (program, athlete),
--                               stage / tags / assignee, soft removal keeps history
--   • program_board_activity  — who did what, for every mutation
--   • coach_private_notes     — per coach per athlete, author-only, never shared
--
-- Every mutation goes through an RPC that asserts verified membership in the
-- entry's program, checks the athlete is published / gender-matched / not
-- blocked, and writes one activity row. Any active verified staff member may
-- save, change stage, tag, assign and remove (W5). Limits: 10 tags of ≤30
-- chars, notes ≤2,000 chars — enforced here, mirrored in the UI (D21).
--
-- Contact unlock (D25): a coach reads athlete_contacts only while an ACTIVE
-- entry exists for that athlete in a program the coach holds, and the coach
-- is not blocked. "Saved by" shown to athletes names the verified program and
-- the saving coach (W6). Blocks hide an entry from the blocked coach only;
-- colleagues keep it (W3/D26). Unblocking restores nothing by itself.
--
-- Legacy coach_saved_athletes (0 rows in prod) is backfilled only for coaches
-- with exactly one verified membership, then closed to new inserts; the table
-- stays readable for cleanup until a later migration drops it (D30).
--
-- Requires 015, 016. Re-runnable.
-- =============================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
create or replace function public.coach_tags_valid(p_tags text[])
returns boolean
language sql
immutable
as $$
  select p_tags is not null
    and cardinality(p_tags) <= 10
    and not exists (select 1 from unnest(p_tags) t where t is null or btrim(t) = '' or char_length(t) > 30);
$$;

create table if not exists public.program_board_entries (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.recruiting_programs (id) on delete cascade,
  athlete_id uuid not null references public.athletes (id) on delete cascade,
  stage text not null default 'watching'
    check (stage in ('watching', 'evaluating', 'contacted', 'offered', 'passed')),
  tags text[] not null default '{}' check (public.coach_tags_valid(tags)),
  assigned_to uuid references auth.users (id) on delete set null,
  saved_by uuid references auth.users (id) on delete set null,
  removed_at timestamptz,
  removed_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (program_id, athlete_id)
);
create index if not exists idx_board_entries_program_active
  on public.program_board_entries (program_id, stage) where removed_at is null;
create index if not exists idx_board_entries_athlete
  on public.program_board_entries (athlete_id);
drop trigger if exists set_updated_at on public.program_board_entries;
create trigger set_updated_at before update on public.program_board_entries
  for each row execute function public.set_updated_at();

create table if not exists public.program_board_activity (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.recruiting_programs (id) on delete cascade,
  entry_id uuid not null references public.program_board_entries (id) on delete cascade,
  actor_user_id uuid,
  action text not null check (action in (
    'saved', 'stage_changed', 'tags_changed', 'assigned', 'unassigned', 'removed', 'restored'
  )),
  from_value text,
  to_value text,
  created_at timestamptz not null default now()
);
create index if not exists idx_board_activity_program
  on public.program_board_activity (program_id, created_at desc);

create table if not exists public.coach_private_notes (
  id uuid primary key default gen_random_uuid(),
  coach_user_id uuid not null references auth.users (id) on delete cascade,
  athlete_id uuid not null references public.athletes (id) on delete cascade,
  body text not null check (char_length(body) <= 2000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (coach_user_id, athlete_id)
);
drop trigger if exists set_updated_at on public.coach_private_notes;
create trigger set_updated_at before update on public.coach_private_notes
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. Helpers
-- ---------------------------------------------------------------------------
create or replace function public.coach_display_name(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select up.display_name from public.user_profiles up where up.id = p_user_id),
    (select cr.full_name from public.coach_requests cr where cr.user_id = p_user_id),
    'Coach');
$$;

-- Trim, drop blanks, dedupe case-insensitively (first spelling wins), enforce limits.
create or replace function public.coach_tags_clean(p_tags text[])
returns text[]
language plpgsql
immutable
as $$
declare
  cleaned text[] := '{}';
  t text;
begin
  if p_tags is null then return cleaned; end if;
  foreach t in array p_tags loop
    t := btrim(regexp_replace(t, '\s+', ' ', 'g'));
    if t = '' then continue; end if;
    if char_length(t) > 30 then raise exception 'tags must be 30 characters or fewer'; end if;
    if not exists (select 1 from unnest(cleaned) c where lower(c) = lower(t)) then
      cleaned := cleaned || t;
    end if;
  end loop;
  if cardinality(cleaned) > 10 then raise exception 'a prospect can have at most 10 tags'; end if;
  return cleaned;
end;
$$;

-- Does the caller currently hold ANY verified program with an active entry for
-- this athlete? Drives contact unlock.
create or replace function public.coach_has_board_entry(p_athlete_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.program_board_entries e
    where e.athlete_id = p_athlete_id
      and e.removed_at is null
      and public.coach_has_program(e.program_id)
  );
$$;

create or replace function public.board_entry_json(e public.program_board_entries)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'id', e.id,
    'program_id', e.program_id,
    'athlete_id', e.athlete_id,
    'stage', e.stage,
    'tags', to_jsonb(e.tags),
    'assigned_to', e.assigned_to,
    'assigned_to_name', case when e.assigned_to is null then null else public.coach_display_name(e.assigned_to) end,
    'saved_by', e.saved_by,
    'saved_by_name', case when e.saved_by is null then null else public.coach_display_name(e.saved_by) end,
    'removed_at', e.removed_at,
    'created_at', e.created_at,
    'updated_at', e.updated_at
  );
$$;

-- Loads an entry the caller may act on, or raises.
create or replace function public.board_entry_for_update(p_entry_id uuid)
returns public.program_board_entries
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.program_board_entries%rowtype;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  select * into e from public.program_board_entries where id = p_entry_id for update;
  if not found then raise exception 'not found'; end if;
  if not public.coach_has_program(e.program_id) or public.coach_is_blocked(e.athlete_id) then
    raise exception 'not found';
  end if;
  return e;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. RPCs — mutations (each writes one activity row)
-- ---------------------------------------------------------------------------
create or replace function public.board_save_athlete(
  p_program_id uuid,
  p_athlete_id uuid,
  p_stage text default 'watching'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  prog public.recruiting_programs%rowtype;
  a public.athletes%rowtype;
  e public.program_board_entries%rowtype;
  coach_name text;
  label text;
  g uuid;
begin
  perform public.coach_assert_program(p_program_id);
  select * into prog from public.recruiting_programs where id = p_program_id;
  select * into a from public.athletes
    where id = p_athlete_id and is_published and sport_gender = prog.sport_gender;
  if not found or public.coach_is_blocked(p_athlete_id) then
    raise exception 'not found';
  end if;
  if p_stage not in ('watching', 'evaluating', 'contacted', 'offered', 'passed') then
    raise exception 'invalid stage';
  end if;

  select * into e from public.program_board_entries
    where program_id = p_program_id and athlete_id = p_athlete_id for update;

  if found and e.removed_at is null then
    return public.board_entry_json(e);   -- already on the board: no-op
  elsif found then
    update public.program_board_entries
      set removed_at = null, removed_by = null, stage = p_stage, saved_by = auth.uid()
      where id = e.id returning * into e;
    insert into public.program_board_activity (program_id, entry_id, actor_user_id, action, to_value)
      values (p_program_id, e.id, auth.uid(), 'restored', p_stage);
  else
    insert into public.program_board_entries (program_id, athlete_id, stage, saved_by)
      values (p_program_id, p_athlete_id, p_stage, auth.uid()) returning * into e;
    insert into public.program_board_activity (program_id, entry_id, actor_user_id, action, to_value)
      values (p_program_id, e.id, auth.uid(), 'saved', p_stage);
  end if;

  -- Athlete + guardians learn which PROGRAM saved them, and by whom (W6).
  coach_name := public.coach_display_name(auth.uid());
  label := public.coach_program_label(prog.institution_name, prog.sport_gender, prog.sport);
  insert into public.notifications (user_id, type, title, body, link)
  values (a.user_id, 'bookmark', label || ' saved your profile',
          'Coach ' || coach_name || ' added ' || a.full_name || ' to the program''s recruiting board.',
          '/a/' || a.id);
  for g in select user_id from public.athlete_guardians where athlete_id = a.id and user_id <> a.user_id loop
    insert into public.notifications (user_id, type, title, body, link)
    values (g, 'bookmark', label || ' saved ' || a.full_name,
            'Coach ' || coach_name || ' added this athlete to the program''s recruiting board.',
            '/a/' || a.id);
  end loop;

  return public.board_entry_json(e);
end;
$$;

create or replace function public.board_set_stage(p_entry_id uuid, p_stage text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.program_board_entries%rowtype;
  prev text;
begin
  e := public.board_entry_for_update(p_entry_id);
  if e.removed_at is not null then raise exception 'entry was removed'; end if;
  if p_stage not in ('watching', 'evaluating', 'contacted', 'offered', 'passed') then
    raise exception 'invalid stage';
  end if;
  if e.stage = p_stage then return public.board_entry_json(e); end if;
  prev := e.stage;
  update public.program_board_entries set stage = p_stage where id = e.id returning * into e;
  insert into public.program_board_activity (program_id, entry_id, actor_user_id, action, from_value, to_value)
    values (e.program_id, e.id, auth.uid(), 'stage_changed', prev, p_stage);
  return public.board_entry_json(e);
end;
$$;

create or replace function public.board_set_tags(p_entry_id uuid, p_tags text[])
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.program_board_entries%rowtype;
  cleaned text[] := public.coach_tags_clean(p_tags);
  prev text[];
begin
  e := public.board_entry_for_update(p_entry_id);
  if e.removed_at is not null then raise exception 'entry was removed'; end if;
  if e.tags = cleaned then return public.board_entry_json(e); end if;
  prev := e.tags;
  update public.program_board_entries set tags = cleaned where id = e.id returning * into e;
  insert into public.program_board_activity (program_id, entry_id, actor_user_id, action, from_value, to_value)
    values (e.program_id, e.id, auth.uid(), 'tags_changed', array_to_string(prev, ', '), array_to_string(cleaned, ', '));
  return public.board_entry_json(e);
end;
$$;

create or replace function public.board_assign(p_entry_id uuid, p_user_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.program_board_entries%rowtype;
  prev uuid;
begin
  e := public.board_entry_for_update(p_entry_id);
  if e.removed_at is not null then raise exception 'entry was removed'; end if;
  if p_user_id is not null and not exists (
       select 1 from public.coach_program_memberships m
       where m.program_id = e.program_id and m.coach_user_id = p_user_id and m.status = 'verified'
         and public.is_active_coach(p_user_id)) then
    raise exception 'assignee is not active staff of this program';
  end if;
  if e.assigned_to is not distinct from p_user_id then return public.board_entry_json(e); end if;
  prev := e.assigned_to;
  update public.program_board_entries set assigned_to = p_user_id where id = e.id returning * into e;
  insert into public.program_board_activity (program_id, entry_id, actor_user_id, action, from_value, to_value)
    values (e.program_id, e.id, auth.uid(),
            case when p_user_id is null then 'unassigned' else 'assigned' end,
            case when prev is null then null else public.coach_display_name(prev) end,
            case when p_user_id is null then null else public.coach_display_name(p_user_id) end);
  return public.board_entry_json(e);
end;
$$;

create or replace function public.board_remove(p_entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.program_board_entries%rowtype;
begin
  e := public.board_entry_for_update(p_entry_id);
  if e.removed_at is not null then return public.board_entry_json(e); end if;
  update public.program_board_entries set removed_at = now(), removed_by = auth.uid() where id = e.id returning * into e;
  insert into public.program_board_activity (program_id, entry_id, actor_user_id, action, from_value)
    values (e.program_id, e.id, auth.uid(), 'removed', e.stage);
  return public.board_entry_json(e);
end;
$$;

create or replace function public.board_restore(p_entry_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  e public.program_board_entries%rowtype;
begin
  e := public.board_entry_for_update(p_entry_id);
  if e.removed_at is null then return public.board_entry_json(e); end if;
  if not exists (select 1 from public.athletes a where a.id = e.athlete_id and a.is_published) then
    raise exception 'athlete is no longer published';
  end if;
  update public.program_board_entries set removed_at = null, removed_by = null where id = e.id returning * into e;
  insert into public.program_board_activity (program_id, entry_id, actor_user_id, action, to_value)
    values (e.program_id, e.id, auth.uid(), 'restored', e.stage);
  return public.board_entry_json(e);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. RPCs — reads
-- ---------------------------------------------------------------------------
create or replace function public.board_list(
  p_program_id uuid,
  p_stage text default null,
  p_assigned_to uuid default null,
  p_include_removed boolean default false,
  p_cursor jsonb default null,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  lim integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  cur_u timestamptz := nullif(p_cursor ->> 'u', '')::timestamptz;
  cur_id uuid := nullif(p_cursor ->> 'id', '')::uuid;
  items jsonb := '[]'::jsonb;
  next_cursor jsonb := null;
  n integer := 0;
  r record;
begin
  perform public.coach_assert_program(p_program_id);

  for r in
    select e.*, a.*
    from public.program_board_entries e
    join public.athletes a on a.id = e.athlete_id
    where e.program_id = p_program_id
      and (p_include_removed or e.removed_at is null)
      and (p_stage is null or e.stage = p_stage)
      and (p_assigned_to is null or e.assigned_to = p_assigned_to)
      and a.is_published
      and not public.coach_is_blocked(e.athlete_id)
      and (cur_u is null or (e.updated_at, e.id) < (cur_u, cur_id))
    order by e.updated_at desc, e.id desc
    limit lim + 1
  loop
    n := n + 1;
    if n > lim then exit; end if;
    items := items || jsonb_build_object(
      'entry', public.board_entry_json((select pe from public.program_board_entries pe where pe.id = r.id)),
      'athlete', public.coach_athlete_card_json((select pa from public.athletes pa where pa.id = r.athlete_id), null),
      'has_private_note', exists (select 1 from public.coach_private_notes pn
                                  where pn.coach_user_id = auth.uid() and pn.athlete_id = r.athlete_id)
    );
    next_cursor := jsonb_build_object('u', r.updated_at, 'id', r.id);
  end loop;
  if n <= lim then next_cursor := null; end if;

  return jsonb_build_object(
    'items', items,
    'next_cursor', next_cursor,
    'stage_counts', (
      select coalesce(jsonb_object_agg(s.stage, s.c), '{}'::jsonb)
      from (select e.stage, count(*) as c
            from public.program_board_entries e
            where e.program_id = p_program_id and e.removed_at is null
              and not public.coach_is_blocked(e.athlete_id)
            group by e.stage) s),
    'assigned_to_me', (
      select count(*) from public.program_board_entries e
      where e.program_id = p_program_id and e.removed_at is null and e.assigned_to = auth.uid()
        and not public.coach_is_blocked(e.athlete_id))
  );
end;
$$;

create or replace function public.board_activity(
  p_program_id uuid,
  p_entry_id uuid default null,
  p_limit integer default 50
)
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
      'id', act.id,
      'entry_id', act.entry_id,
      'athlete_id', e.athlete_id,
      'athlete_name', a.full_name,
      'actor_user_id', act.actor_user_id,
      'actor_name', public.coach_display_name(act.actor_user_id),
      'action', act.action,
      'from_value', act.from_value,
      'to_value', act.to_value,
      'created_at', act.created_at
    ) order by act.created_at desc)
    from (
      select * from public.program_board_activity x
      where x.program_id = p_program_id
        and (p_entry_id is null or x.entry_id = p_entry_id)
      order by x.created_at desc
      limit least(greatest(coalesce(p_limit, 50), 1), 200)
    ) act
    join public.program_board_entries e on e.id = act.entry_id
    join public.athletes a on a.id = e.athlete_id
    where not public.coach_is_blocked(e.athlete_id)
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Detail + Home now carry board state; contact unlock keys on the board.
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
  e public.program_board_entries%rowtype;
  contact_unlocked boolean;
  contact jsonb := null;
  note text;
begin
  perform public.coach_assert_program(p_program_id);
  select * into prog from public.recruiting_programs where id = p_program_id;

  select * into a from public.athletes
  where id = p_athlete_id and is_published and sport_gender = prog.sport_gender;
  if not found or public.coach_is_blocked(p_athlete_id) then
    raise exception 'not found';
  end if;

  select * into e from public.program_board_entries
    where program_id = p_program_id and athlete_id = p_athlete_id;
  contact_unlocked := found and e.removed_at is null;
  if contact_unlocked then
    select jsonb_build_object(
      'athlete_email', c.athlete_email, 'athlete_phone', c.athlete_phone,
      'guardian_name', c.guardian_name, 'guardian_email', c.guardian_email, 'guardian_phone', c.guardian_phone,
      'club_coach_name', c.club_coach_name, 'club_coach_phone', c.club_coach_phone
    ) into contact
    from public.athlete_contacts c where c.athlete_id = p_athlete_id;
  end if;
  select body into note from public.coach_private_notes
    where coach_user_id = auth.uid() and athlete_id = p_athlete_id;

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
      select jsonb_agg(jsonb_build_object('id', ev.id, 'event_date', ev.event_date, 'event_time', ev.event_time,
                                          'opponent', ev.opponent, 'location', ev.location, 'notes', ev.notes, 'is_mayb', ev.is_mayb)
                       order by ev.event_date, ev.event_time)
      from public.athlete_events ev
      where ev.athlete_id = a.id
        and ev.event_date between (now() at time zone 'America/Chicago')::date
                              and (now() at time zone 'America/Chicago')::date + 30), '[]'::jsonb),
    'contact_unlocked', contact_unlocked,
    'contact', contact,
    'board', case when e.id is null then null else public.board_entry_json(e) end,
    'private_note', note,
    'program_id', p_program_id
  );
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
    'board_counts', (
      select coalesce(jsonb_object_agg(s.stage, s.c), '{}'::jsonb)
      from (select e.stage, count(*) as c
            from public.program_board_entries e
            where e.program_id = p_program_id and e.removed_at is null
              and not public.coach_is_blocked(e.athlete_id)
            group by e.stage) s),
    'assigned_to_me', (
      select count(*) from public.program_board_entries e
      where e.program_id = p_program_id and e.removed_at is null and e.assigned_to = auth.uid()
        and not public.coach_is_blocked(e.athlete_id)),
    'recent_activity', public.board_activity(p_program_id, null, 10)
  );
end;
$$;

drop policy if exists "contacts select" on public.athlete_contacts;
create policy "contacts select" on public.athlete_contacts
  for select to authenticated
  using (
    public.can_manage_athlete(athlete_id)
    or (
      public.has_role('coach')
      and public.athlete_is_published(athlete_id)
      and not public.coach_is_blocked(athlete_id)
      and public.coach_has_board_entry(athlete_id)
    )
  );

-- ---------------------------------------------------------------------------
-- 6. Athlete side: "Saved by" names the program + coach (W6).
--    Return shape kept for the iOS BookmarkSummary model; `college` now
--    carries the program label.
-- ---------------------------------------------------------------------------
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
    e.saved_by,
    public.coach_display_name(e.saved_by),
    public.coach_program_label(p.institution_name, p.sport_gender, p.sport),
    (select m.title from public.coach_program_memberships m
      where m.coach_user_id = e.saved_by and m.program_id = e.program_id limit 1),
    e.created_at
  from public.program_board_entries e
  join public.recruiting_programs p on p.id = e.program_id
  where e.athlete_id = _athlete_id
    and e.removed_at is null
    and public.can_manage_athlete(_athlete_id)
  order by e.created_at desc
$$;

-- Directory labels: a board relation counts as a relationship (016 §9).
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
      or exists (select 1 from public.messages msg
                 where msg.coach_user_id = u.id and public.can_manage_athlete(msg.athlete_id))
      or exists (select 1 from public.program_board_entries e
                 where e.saved_by = u.id and e.removed_at is null and public.can_manage_athlete(e.athlete_id))
      or exists (select 1 from public.coach_saved_athletes s
                 where s.coach_user_id = u.id and public.can_manage_athlete(s.athlete_id))
      or exists (select 1 from public.user_blocks b
                 where b.blocker_user_id = auth.uid() and b.blocked_user_id = u.id)
    )
$$;

-- ---------------------------------------------------------------------------
-- 7. RLS
-- ---------------------------------------------------------------------------
alter table public.program_board_entries enable row level security;
alter table public.program_board_activity enable row level security;
alter table public.coach_private_notes enable row level security;

drop policy if exists "board entries select" on public.program_board_entries;
create policy "board entries select" on public.program_board_entries
  for select to authenticated
  using (
    public.has_role('admin')
    or (public.coach_has_program(program_id) and not public.coach_is_blocked(athlete_id))
  );
-- Mutations go through the RPCs (activity log). Owner delete stays for
-- post-revocation cleanup (D5).
drop policy if exists "board entries owner delete" on public.program_board_entries;
create policy "board entries owner delete" on public.program_board_entries
  for delete to authenticated
  using (saved_by = auth.uid());
drop policy if exists "board entries admin write" on public.program_board_entries;
create policy "board entries admin write" on public.program_board_entries
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "board activity select" on public.program_board_activity;
create policy "board activity select" on public.program_board_activity
  for select to authenticated
  using (public.has_role('admin') or public.coach_has_program(program_id));

-- Private notes: author only. Not even admins (D11: "truly private").
drop policy if exists "private notes owner" on public.coach_private_notes;
create policy "private notes owner" on public.coach_private_notes
  for all to authenticated
  using (coach_user_id = auth.uid())
  with check (coach_user_id = auth.uid() and public.has_role('coach'));

-- ---------------------------------------------------------------------------
-- 8. Legacy coach_saved_athletes (D30): backfill deterministic rows, close
--    inserts. 0 rows in prod on 2026-10-01; this is for completeness.
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
  pid uuid;
  mapped integer := 0;
  skipped integer := 0;
begin
  for r in select * from public.coach_saved_athletes loop
    select m.program_id into pid
    from public.coach_program_memberships m
    join public.recruiting_programs p on p.id = m.program_id
    where m.coach_user_id = r.coach_user_id and m.status = 'verified' and p.active and p.verified_at is not null;
    if not found or (select count(*) from public.coach_program_memberships m2
                     where m2.coach_user_id = r.coach_user_id and m2.status = 'verified') <> 1 then
      skipped := skipped + 1;
      raise notice 'board backfill: legacy save % left in place (0 or >1 verified memberships)', r.id;
      continue;
    end if;
    insert into public.program_board_entries (program_id, athlete_id, stage, tags, saved_by, created_at)
      values (pid, r.athlete_id, r.stage, case when public.coach_tags_valid(r.tags) then r.tags else '{}' end, r.coach_user_id, r.created_at)
      on conflict (program_id, athlete_id) do nothing;
    if r.notes is not null and btrim(r.notes) <> '' then
      insert into public.coach_private_notes (coach_user_id, athlete_id, body)
        values (r.coach_user_id, r.athlete_id, left(r.notes, 2000))
        on conflict (coach_user_id, athlete_id) do nothing;
    end if;
    mapped := mapped + 1;
  end loop;
  raise notice 'board backfill: mapped=% skipped=%', mapped, skipped;
end $$;

drop policy if exists "saved athletes insert" on public.coach_saved_athletes;
-- select/update/delete (owner-only, 007) remain for cleanup until the table is dropped.

-- ---------------------------------------------------------------------------
-- 9. Grants
-- ---------------------------------------------------------------------------
revoke all on function public.coach_tags_valid(text[]) from public, anon;
grant execute on function public.coach_tags_valid(text[]) to authenticated;   -- used by the check constraint
revoke all on function public.coach_tags_clean(text[]) from public, anon, authenticated;
revoke all on function public.coach_display_name(uuid) from public, anon, authenticated;
revoke all on function public.coach_has_board_entry(uuid) from public, anon;
grant execute on function public.coach_has_board_entry(uuid) to authenticated;   -- used by the contacts policy
revoke all on function public.board_entry_json(public.program_board_entries) from public, anon, authenticated;
revoke all on function public.board_entry_for_update(uuid) from public, anon, authenticated;

revoke all on function public.board_save_athlete(uuid, uuid, text) from public, anon;
grant execute on function public.board_save_athlete(uuid, uuid, text) to authenticated;
revoke all on function public.board_set_stage(uuid, text) from public, anon;
grant execute on function public.board_set_stage(uuid, text) to authenticated;
revoke all on function public.board_set_tags(uuid, text[]) from public, anon;
grant execute on function public.board_set_tags(uuid, text[]) to authenticated;
revoke all on function public.board_assign(uuid, uuid) from public, anon;
grant execute on function public.board_assign(uuid, uuid) to authenticated;
revoke all on function public.board_remove(uuid) from public, anon;
grant execute on function public.board_remove(uuid) to authenticated;
revoke all on function public.board_restore(uuid) from public, anon;
grant execute on function public.board_restore(uuid) to authenticated;
revoke all on function public.board_list(uuid, text, uuid, boolean, jsonb, integer) from public, anon;
grant execute on function public.board_list(uuid, text, uuid, boolean, jsonb, integer) to authenticated;
revoke all on function public.board_activity(uuid, uuid, integer) from public, anon;
grant execute on function public.board_activity(uuid, uuid, integer) to authenticated;
