-- =============================================================================
-- 002 — Web-app parity: safety tables, notification/enforcement triggers,
-- RLS tightening, private storage. Ported from athlete-connect migrations,
-- adapted to this project's table names (user_profiles, athlete_profile_views)
-- and helper signatures (has_role(text), can_manage_athlete(uuid)).
-- Re-runnable.
-- =============================================================================

set check_function_bodies = off;

-- =============================================================================
-- 1. Safety tables (Apple guideline 1.2)
-- =============================================================================

create table if not exists public.user_blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_user_id uuid not null references auth.users (id) on delete cascade,
  blocked_user_id uuid not null references auth.users (id) on delete cascade,
  reason text,
  created_at timestamptz not null default now(),
  unique (blocker_user_id, blocked_user_id),
  check (blocker_user_id <> blocked_user_id)
);

alter table public.user_blocks enable row level security;

drop policy if exists "users manage own blocks" on public.user_blocks;
create policy "users manage own blocks" on public.user_blocks
  for all to authenticated
  using (auth.uid() = blocker_user_id)
  with check (auth.uid() = blocker_user_id);

drop policy if exists "admins view all blocks" on public.user_blocks;
create policy "admins view all blocks" on public.user_blocks
  for select to authenticated
  using (public.has_role('admin'));

create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_user_id uuid not null references auth.users (id) on delete cascade,
  target_type text not null check (target_type in ('message', 'athlete_profile', 'user')),
  target_id text not null,
  athlete_id uuid references public.athletes (id) on delete set null,
  reported_user_id uuid references auth.users (id) on delete set null,
  reason text not null,
  details text,
  status text not null default 'open' check (status in ('open', 'reviewed', 'actioned', 'dismissed')),
  resolution_note text,
  reviewed_by uuid references auth.users (id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_content_reports_status on public.content_reports (status, created_at desc);

alter table public.content_reports enable row level security;

drop policy if exists "users file reports" on public.content_reports;
create policy "users file reports" on public.content_reports
  for insert to authenticated
  with check (auth.uid() = reporter_user_id);

drop policy if exists "users view own reports" on public.content_reports;
create policy "users view own reports" on public.content_reports
  for select to authenticated
  using (auth.uid() = reporter_user_id);

drop policy if exists "admins view all reports" on public.content_reports;
create policy "admins view all reports" on public.content_reports
  for select to authenticated
  using (public.has_role('admin'));

drop policy if exists "admins update reports" on public.content_reports;
create policy "admins update reports" on public.content_reports
  for update to authenticated
  using (public.has_role('admin'))
  with check (public.has_role('admin'));

drop trigger if exists set_updated_at on public.content_reports;
create trigger set_updated_at before update on public.content_reports
  for each row execute function public.set_updated_at();

-- =============================================================================
-- 2. College-name normalization + interest limit (web parity, verbatim logic)
-- =============================================================================

create or replace function public.normalize_college(_name text)
returns text
language sql
immutable
set search_path = public
as $$
  select regexp_replace(
    lower(coalesce(_name, '')),
    '(university of |the university of |university|college|state college|\s|[^a-z0-9])',
    '',
    'g'
  )
$$;

create or replace function public.enforce_college_interest_limit()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  cnt int;
begin
  select count(*) into cnt from public.athlete_college_interests where athlete_id = new.athlete_id;
  if cnt >= 10 then
    raise exception 'You can track up to 10 colleges. Remove one before adding another.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_college_interest_limit on public.athlete_college_interests;
create trigger trg_college_interest_limit
before insert on public.athlete_college_interests
for each row execute function public.enforce_college_interest_limit();

-- =============================================================================
-- 3. Notification fan-out triggers (web parity)
-- =============================================================================

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
  published boolean;
  c record;
begin
  select a.full_name, a.position, a.grad_year, a.is_published
    into athlete_name, athlete_pos, athlete_grad, published
  from public.athletes a where a.id = _athlete_id;

  if not coalesce(published, false) then
    return;
  end if;

  for c in
    select distinct cr.user_id
    from public.coach_requests cr
    where cr.status = 'approved'
      and cr.college is not null
      and public.normalize_college(cr.college) = public.normalize_college(_college_name)
      and public.normalize_college(cr.college) <> ''
  loop
    insert into public.notifications (user_id, type, title, body, link)
    values (
      c.user_id,
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

create or replace function public.notify_on_college_interest()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.notify_coaches_of_interest(new.athlete_id, new.college_name);
  return new;
end;
$$;

drop trigger if exists trg_notify_college_interest on public.athlete_college_interests;
create trigger trg_notify_college_interest
after insert on public.athlete_college_interests
for each row execute function public.notify_on_college_interest();

create or replace function public.notify_coaches_on_publish()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  if new.is_published and not coalesce(old.is_published, false) then
    for r in select college_name from public.athlete_college_interests where athlete_id = new.id loop
      perform public.notify_coaches_of_interest(new.id, r.college_name);
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_coaches_on_publish on public.athletes;
create trigger trg_notify_coaches_on_publish
after update on public.athletes
for each row execute function public.notify_coaches_on_publish();

create or replace function public.notify_athlete_on_save()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  athlete_owner uuid;
  athlete_name text;
  coach_name text;
  guardian_user uuid;
begin
  select a.user_id, a.full_name into athlete_owner, athlete_name
  from public.athletes a where a.id = new.athlete_id;

  if athlete_owner is null then
    return new;
  end if;

  select coalesce(p.display_name, 'A college coach') into coach_name
  from public.user_profiles p where p.id = new.coach_user_id;

  insert into public.notifications (user_id, type, title, body, link)
  values (
    athlete_owner,
    'bookmark',
    'A coach bookmarked your profile',
    coalesce(coach_name, 'A college coach') || ' added ' || coalesce(athlete_name, 'your profile') || ' to their recruiting shortlist.',
    '/a/' || new.athlete_id
  );

  select p.id into guardian_user
  from public.athlete_contacts c
  join public.user_profiles p on lower(p.email) = lower(c.guardian_email)
  where c.athlete_id = new.athlete_id and c.guardian_email is not null and p.id <> athlete_owner
  limit 1;

  if guardian_user is not null then
    insert into public.notifications (user_id, type, title, body, link)
    values (
      guardian_user,
      'bookmark',
      'A coach bookmarked ' || coalesce(athlete_name, 'your athlete'),
      coalesce(coach_name, 'A college coach') || ' added this athlete to their recruiting shortlist.',
      '/a/' || new.athlete_id
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notify_athlete_on_save on public.coach_saved_athletes;
create trigger trg_notify_athlete_on_save
after insert on public.coach_saved_athletes
for each row execute function public.notify_athlete_on_save();

create or replace function public.notify_on_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  athlete_owner uuid;
  athlete_name text;
  sender_name text;
  g record;
begin
  select a.user_id, a.full_name into athlete_owner, athlete_name from public.athletes a where a.id = new.athlete_id;
  select coalesce(p.display_name, 'Someone') into sender_name from public.user_profiles p where p.id = new.sender_user_id;

  if new.sender_user_id = new.coach_user_id then
    if athlete_owner is not null then
      insert into public.notifications (user_id, type, title, body, link)
      values (athlete_owner, 'message', 'New message from a college coach',
              coalesce(sender_name, 'A coach') || ': ' || left(new.body, 120), '/messages');
    end if;
    for g in select user_id from public.athlete_guardians where athlete_id = new.athlete_id loop
      insert into public.notifications (user_id, type, title, body, link)
      values (g.user_id, 'message', 'New message from a college coach',
              coalesce(sender_name, 'A coach') || ': ' || left(new.body, 120), '/messages');
    end loop;
  else
    insert into public.notifications (user_id, type, title, body, link)
    values (new.coach_user_id, 'message', 'New message from an athlete',
            coalesce(athlete_name, 'An athlete') || ': ' || left(new.body, 120), '/coaches/messages');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_on_message on public.messages;
create trigger trg_notify_on_message
after insert on public.messages
for each row execute function public.notify_on_message();

-- =============================================================================
-- 4. Enforcement triggers: under-13 publish gate, blocked-pair messaging
-- =============================================================================

create or replace function public.enforce_guardian_consent()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.is_published
     and new.date_of_birth is not null
     and new.date_of_birth > (current_date - interval '13 years')
     and new.guardian_consent_at is null then
    raise exception 'Athletes under 13 need verified guardian consent before the profile can be published';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guardian_consent on public.athletes;
create trigger trg_guardian_consent
before insert or update on public.athletes
for each row execute function public.enforce_guardian_consent();

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
  ) into blocked;

  if blocked then
    raise exception 'This conversation is blocked. Unblock to send messages.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_enforce_message_blocks on public.messages;
create trigger trg_enforce_message_blocks
before insert on public.messages
for each row execute function public.enforce_message_blocks();

revoke all on function public.normalize_college(text) from anon;
revoke all on function public.enforce_college_interest_limit() from public, anon, authenticated;
revoke all on function public.notify_coaches_of_interest(uuid, text) from public, anon, authenticated;
revoke all on function public.notify_on_college_interest() from public, anon, authenticated;
revoke all on function public.notify_coaches_on_publish() from public, anon, authenticated;
revoke all on function public.notify_athlete_on_save() from public, anon, authenticated;
revoke all on function public.notify_on_message() from public, anon, authenticated;
revoke all on function public.enforce_guardian_consent() from public, anon, authenticated;
revoke all on function public.enforce_message_blocks() from public, anon, authenticated;

-- =============================================================================
-- 5. RLS tightening (web parity)
-- =============================================================================

-- Contacts: coach must be approved AND have the athlete saved AND published
drop policy if exists "contacts select" on public.athlete_contacts;
create policy "contacts select" on public.athlete_contacts
  for select to authenticated
  using (
    public.can_manage_athlete(athlete_id)
    or (
      public.has_role('coach')
      and public.athlete_is_published(athlete_id)
      and exists (
        select 1 from public.coach_saved_athletes s
        where s.athlete_id = athlete_contacts.athlete_id
          and s.coach_user_id = auth.uid()
      )
    )
  );

-- Pipeline tables require the coach role, not just ownership
drop policy if exists "saved athletes all" on public.coach_saved_athletes;
create policy "saved athletes all" on public.coach_saved_athletes
  for all to authenticated
  using (coach_user_id = auth.uid() and public.has_role('coach'))
  with check (coach_user_id = auth.uid() and public.has_role('coach'));

drop policy if exists "saved searches all" on public.coach_saved_searches;
create policy "saved searches all" on public.coach_saved_searches
  for all to authenticated
  using (coach_user_id = auth.uid() and public.has_role('coach'))
  with check (coach_user_id = auth.uid() and public.has_role('coach'));

-- Profile views are recorded only by the record-profile-view edge function
drop policy if exists "views insert" on public.athlete_profile_views;

-- Users may clear their own notifications (web parity)
drop policy if exists "notifications delete" on public.notifications;
create policy "notifications delete" on public.notifications
  for delete to authenticated
  using (user_id = auth.uid());

-- Invites expire 30 days out by default (web parity)
alter table public.athlete_invites
  alter column expires_at set default (now() + interval '30 days');

-- =============================================================================
-- 6. Private storage (web parity): flip bucket private, owner+coach+admin reads
-- =============================================================================

update storage.buckets set public = false where id = 'athlete-media';

drop policy if exists "athlete media public read" on storage.objects;

drop policy if exists "athlete media owner read" on storage.objects;
create policy "athlete media owner read" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'athlete-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "admins read athlete media" on storage.objects;
create policy "admins read athlete media" on storage.objects
  for select to authenticated
  using (bucket_id = 'athlete-media' and public.has_role('admin'));

drop policy if exists "coaches read published athlete media" on storage.objects;
create policy "coaches read published athlete media" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'athlete-media'
    and public.has_role('coach')
    and exists (
      select 1 from public.athletes a
      where a.is_published
        and (
          a.user_id::text = (storage.foldername(name))[1]
          or exists (
            select 1 from public.athlete_guardians g
            where g.athlete_id = a.id
              and g.user_id::text = (storage.foldername(name))[1]
          )
        )
    )
  );
