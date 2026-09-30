-- =============================================================================
-- 014 — Coach onboarding, verification and Coach Mode access.
--
-- Added 2026-09-30 per COACH-MODE-ONBOARDING-AND-VERIFICATION-SPEC.md.
-- Reintroduces College Coach sign-up on iOS as an *application*, not access:
--
--   sign up (signup_role = coach) → handle_new_user creates user_profiles +
--   a PENDING coach_requests row and nothing else → admin reviews in the app →
--   approve_coach_request() atomically verifies the program, creates the
--   membership, grants user_roles.coach and notifies the coach.
--
-- The coach role is derived: sync_coach_role() keeps user_roles.coach equal
-- to "has ≥1 verified membership in an active, verified program". Suspending
-- or inactivating a membership removes the role in the same statement.
--
-- Guards (BEFORE triggers) make the atomic path the *only* path for
-- authenticated clients — including the web admin portal:
--   • coach_requests.status / review columns change only via the RPCs,
--   • user_roles(role = 'coach') is inserted only via sync_coach_role(),
--   • coach_program_memberships are verified only via the RPCs.
-- Server-side contexts (migrations, service role, SQL editor: auth.uid() is
-- null) are exempt so maintenance and tests keep working.
--
-- Builds on 010 (recruiting_programs, coach_program_memberships already exist
-- — this file ALTERs them) and 013 (enforcement reads verified memberships).
-- Nothing here re-enables the 003 auto-approval; that stays removed (007).
--
-- Re-runnable.
-- =============================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- 1. coach_requests — the application. Claims awaiting review, never
--    authorization attributes.
-- ---------------------------------------------------------------------------
alter table public.coach_requests
  add column if not exists governing_body text,
  add column if not exists division text,
  add column if not exists sport text not null default 'basketball',
  add column if not exists sport_gender text,
  add column if not exists athletics_url text,
  add column if not exists program_url text,
  add column if not exists phone text,
  add column if not exists rejection_reason text,          -- user-visible
  add column if not exists info_request_message text,      -- user-visible
  add column if not exists resubmitted_at timestamptz,
  add column if not exists approved_program_id uuid references public.recruiting_programs (id) on delete set null,
  add column if not exists approved_membership_id uuid references public.coach_program_memberships (id) on delete set null,
  add column if not exists updated_at timestamptz not null default now();

alter table public.coach_requests drop constraint if exists coach_requests_status_check;
alter table public.coach_requests add constraint coach_requests_status_check
  check (status in ('pending', 'approved', 'rejected', 'withdrawn', 'needs_more_information'));

alter table public.coach_requests drop constraint if exists coach_requests_sport_gender_check;
alter table public.coach_requests add constraint coach_requests_sport_gender_check
  check (sport_gender is null or sport_gender in ('mens', 'womens'));

alter table public.coach_requests drop constraint if exists coach_requests_governing_body_check;
alter table public.coach_requests add constraint coach_requests_governing_body_check
  check (governing_body is null or governing_body in ('NCAA', 'NAIA', 'NJCAA', 'Other', 'Unknown'));

-- setup.sql's reviewed_by FK had no ON DELETE action, so deleting an admin
-- account that had reviewed any request would fail. Reviewer identity is
-- audit metadata; losing it must not block account deletion.
alter table public.coach_requests drop constraint if exists coach_requests_reviewed_by_fkey;
alter table public.coach_requests add constraint coach_requests_reviewed_by_fkey
  foreign key (reviewed_by) references auth.users (id) on delete set null;

-- One application per account; resubmission edits it in place.
create unique index if not exists uq_coach_requests_user on public.coach_requests (user_id);
create index if not exists idx_coach_requests_status on public.coach_requests (status, created_at);

drop trigger if exists set_updated_at on public.coach_requests;
create trigger set_updated_at before update on public.coach_requests
  for each row execute function public.set_updated_at();

-- Review audit trail. Internal notes live here (admin-only), never on the
-- request row the applicant can read.
create table if not exists public.coach_request_reviews (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.coach_requests (id) on delete cascade,
  action text not null check (action in (
    'submitted', 'resubmitted', 'approved', 'rejected', 'info_requested',
    'withdrawn', 'membership_suspended', 'membership_inactivated', 'membership_reinstated'
  )),
  actor_user_id uuid,   -- audit metadata, deliberately no FK (like recruiting_compliance_decisions.actor_user_id)
  public_message text,
  internal_note text,
  created_at timestamptz not null default now()
);
-- An earlier revision had an ON DELETE SET NULL FK here; the set-null update
-- races the request cascade inside one transaction and fails the request_id
-- FK check. Audit rows don't need referential integrity to auth.users.
alter table public.coach_request_reviews drop constraint if exists coach_request_reviews_actor_user_id_fkey;
create index if not exists idx_coach_request_reviews_request
  on public.coach_request_reviews (request_id, created_at);

-- ---------------------------------------------------------------------------
-- 2. recruiting_programs / coach_program_memberships — extend 010.
-- ---------------------------------------------------------------------------
alter table public.recruiting_programs
  add column if not exists verified_by uuid references auth.users (id) on delete set null,
  add column if not exists athletics_url text,
  add column if not exists program_url text;

alter table public.recruiting_programs drop constraint if exists recruiting_programs_sport_gender_check;
alter table public.recruiting_programs add constraint recruiting_programs_sport_gender_check
  check (sport_gender in ('mens', 'womens'));

alter table public.recruiting_programs drop constraint if exists recruiting_programs_governing_body_check;
alter table public.recruiting_programs add constraint recruiting_programs_governing_body_check
  check (governing_body in ('NCAA', 'NAIA', 'NJCAA', 'Other'));

alter table public.recruiting_programs drop constraint if exists recruiting_programs_ncaa_division_check;
alter table public.recruiting_programs add constraint recruiting_programs_ncaa_division_check
  check (governing_body <> 'NCAA' or division in ('D1', 'D2', 'D3'));

alter table public.coach_program_memberships
  add column if not exists membership_role text,
  add column if not exists started_at date,
  add column if not exists ended_at date;

-- Same reviewer-deletion hazard as coach_requests.reviewed_by (010 had no action).
alter table public.coach_program_memberships drop constraint if exists coach_program_memberships_verified_by_fkey;
alter table public.coach_program_memberships add constraint coach_program_memberships_verified_by_fkey
  foreign key (verified_by) references auth.users (id) on delete set null;

alter table public.coach_program_memberships drop constraint if exists coach_program_memberships_status_check;
alter table public.coach_program_memberships add constraint coach_program_memberships_status_check
  check (status in ('pending', 'verified', 'suspended', 'inactive', 'rejected'));

alter table public.coach_program_memberships drop constraint if exists coach_program_memberships_role_check;
alter table public.coach_program_memberships add constraint coach_program_memberships_role_check
  check (membership_role is null or membership_role in (
    'head_coach', 'assistant_coach', 'recruiting_coordinator', 'operations', 'staff', 'other'
  ));

-- ---------------------------------------------------------------------------
-- 3. Internal helpers (never callable by clients).
-- ---------------------------------------------------------------------------
create or replace function public.coach_clean_text(p text, p_max integer)
returns text
language sql
immutable
as $$
  select nullif(left(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g')), p_max), '');
$$;

create or replace function public.coach_clean_url(p text)
returns text
language sql
immutable
as $$
  select case
    when coalesce(btrim(p), '') ~* '^https?://[^\s]+$' then left(btrim(p), 500)
    else null
  end;
$$;

create or replace function public.coach_clean_governing_body(p text)
returns text
language sql
immutable
as $$
  select case upper(btrim(coalesce(p, '')))
    when 'NCAA' then 'NCAA'
    when 'NAIA' then 'NAIA'
    when 'NJCAA' then 'NJCAA'
    when 'OTHER' then 'Other'
    when 'UNKNOWN' then 'Unknown'
    else null
  end;
$$;

-- Division is only controlled for NCAA (D1/D2/D3); other bodies store a short
-- free-text level or null. Never guess.
create or replace function public.coach_clean_division(p_governing_body text, p text)
returns text
language sql
immutable
as $$
  select case
    when p_governing_body = 'NCAA' then
      case upper(replace(btrim(coalesce(p, '')), ' ', ''))
        when 'D1' then 'D1' when 'DI' then 'D1' when 'DIVISION1' then 'D1' when 'DIVISIONI' then 'D1'
        when 'D2' then 'D2' when 'DII' then 'D2' when 'DIVISION2' then 'D2' when 'DIVISIONII' then 'D2'
        when 'D3' then 'D3' when 'DIII' then 'D3' when 'DIVISION3' then 'D3' when 'DIVISIONIII' then 'D3'
        else null
      end
    else public.coach_clean_text(p, 40)
  end;
$$;

create or replace function public.coach_clean_sport_gender(p text)
returns text
language sql
immutable
as $$
  select case lower(btrim(coalesce(p, '')))
    when 'mens' then 'mens' when 'men' then 'mens' when 'men''s' then 'mens' when 'male' then 'mens'
    when 'womens' then 'womens' when 'women' then 'womens' when 'women''s' then 'womens' when 'female' then 'womens'
    else null
  end;
$$;

create or replace function public.coach_normalize_institution(p text)
returns text
language sql
immutable
as $$
  select lower(public.coach_clean_text(p, 200));
$$;

-- "University X Men's Basketball"
create or replace function public.coach_program_label(p_institution text, p_sport_gender text, p_sport text)
returns text
language sql
immutable
as $$
  select p_institution || ' '
    || case p_sport_gender when 'mens' then 'Men''s ' when 'womens' then 'Women''s ' else '' end
    || initcap(coalesce(p_sport, 'basketball'));
$$;

create or replace function public.coach_notify(p_user_id uuid, p_type text, p_title text, p_body text, p_link text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.notifications (user_id, type, title, body, link)
  values (p_user_id, p_type, p_title, p_body, p_link);
$$;

create or replace function public.coach_notify_admins(p_type text, p_title text, p_body text, p_link text)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.notifications (user_id, type, title, body, link)
  select ur.user_id, p_type, p_title, p_body, p_link
  from public.user_roles ur where ur.role = 'admin';
$$;

-- ---------------------------------------------------------------------------
-- 4. sync_coach_role — the coach role is a projection of verified membership.
--    Touches ONLY role = 'coach'; admin/athlete/parent rows are never read
--    or written here.
-- ---------------------------------------------------------------------------
create or replace function public.sync_coach_role(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  should_have boolean;
begin
  select exists (
    select 1
    from public.coach_program_memberships m
    join public.recruiting_programs p on p.id = m.program_id
    where m.coach_user_id = p_user_id
      and m.status = 'verified'
      and p.active
      and p.verified_at is not null
  ) into should_have;

  if should_have then
    perform set_config('thehub.coach_grant', 'rpc', true);
    insert into public.user_roles (user_id, role)
    values (p_user_id, 'coach')
    on conflict (user_id, role) do nothing;
  else
    delete from public.user_roles where user_id = p_user_id and role = 'coach';
  end if;
  return should_have;
end;
$$;

-- Any membership or program change re-derives the affected coaches' role, so
-- the invariant holds no matter which path changed the row.
create or replace function public.trg_sync_coach_role_from_membership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.sync_coach_role(old.coach_user_id);
    return old;
  end if;
  perform public.sync_coach_role(new.coach_user_id);
  if tg_op = 'UPDATE' and new.coach_user_id is distinct from old.coach_user_id then
    perform public.sync_coach_role(old.coach_user_id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_membership_sync_coach_role on public.coach_program_memberships;
create trigger trg_membership_sync_coach_role
after insert or update or delete on public.coach_program_memberships
for each row execute function public.trg_sync_coach_role_from_membership();

create or replace function public.trg_sync_coach_role_from_program()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  u uuid;
begin
  if new.active is distinct from old.active or new.verified_at is distinct from old.verified_at then
    for u in select distinct coach_user_id from public.coach_program_memberships where program_id = new.id loop
      perform public.sync_coach_role(u);
    end loop;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_program_sync_coach_role on public.recruiting_programs;
create trigger trg_program_sync_coach_role
after update on public.recruiting_programs
for each row execute function public.trg_sync_coach_role_from_program();

-- ---------------------------------------------------------------------------
-- 5. Guards — authenticated clients cannot take the shortcuts. A missing GUC
--    reads as null; the RPCs set it for their own transaction.
-- ---------------------------------------------------------------------------
create or replace function public.guard_coach_role_grant()
returns trigger
language plpgsql
as $$
begin
  if new.role = 'coach'
     and auth.uid() is not null
     and current_setting('thehub.coach_grant', true) is distinct from 'rpc' then
    raise exception 'coach role is granted only by approving a coach request (approve_coach_request)';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_coach_role_grant on public.user_roles;
create trigger trg_guard_coach_role_grant
before insert on public.user_roles
for each row execute function public.guard_coach_role_grant();

create or replace function public.guard_coach_request_review()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is not null
     and current_setting('thehub.coach_review', true) is distinct from 'rpc'
     and (
       new.status is distinct from old.status
       or new.reviewed_at is distinct from old.reviewed_at
       or new.reviewed_by is distinct from old.reviewed_by
       or new.approved_program_id is distinct from old.approved_program_id
       or new.approved_membership_id is distinct from old.approved_membership_id
       or new.user_id is distinct from old.user_id
     ) then
    raise exception 'coach request review fields change only via approve_coach_request / reject_coach_request / request_coach_info / update_coach_application';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_coach_request_review on public.coach_requests;
create trigger trg_guard_coach_request_review
before update on public.coach_requests
for each row execute function public.guard_coach_request_review();

create or replace function public.guard_membership_verification()
returns trigger
language plpgsql
as $$
begin
  if auth.uid() is null or current_setting('thehub.coach_review', true) = 'rpc' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    if new.status = 'verified' or new.verified_at is not null or new.verified_by is not null then
      raise exception 'memberships are verified only via approve_coach_request';
    end if;
  elsif new.status is distinct from old.status
     or new.verified_at is distinct from old.verified_at
     or new.verified_by is distinct from old.verified_by
     or new.program_id is distinct from old.program_id
     or new.coach_user_id is distinct from old.coach_user_id then
    raise exception 'membership status/verification changes only via approve_coach_request / set_coach_membership_status';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_membership_verification on public.coach_program_memberships;
create trigger trg_guard_membership_verification
before insert or update on public.coach_program_memberships
for each row execute function public.guard_membership_verification();

-- ---------------------------------------------------------------------------
-- 6. Signup trigger: coach branch. Creates the profile and a PENDING
--    application from sanitized metadata. Grants NO role. Every value is a
--    claim; the status is forced regardless of what the client sent.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  meta_role text := meta ->> 'signup_role';
  meta_dob date := nullif(meta ->> 'date_of_birth', '')::date;
  gb text;
  req_id uuid;
begin
  if meta_role = 'athlete'
     and meta_dob is not null
     and meta_dob > (current_date - interval '13 years') then
    raise exception 'athletes under 13 cannot create their own account';
  end if;

  insert into public.user_profiles (id, email, display_name)
  values (new.id, new.email, meta ->> 'full_name')
  on conflict (id) do nothing;

  if meta_role in ('athlete', 'parent') then
    insert into public.user_roles (user_id, role)
    values (new.id, meta_role)
    on conflict (user_id, role) do nothing;
  end if;

  if meta_role = 'athlete'
     and coalesce(meta ->> 'full_name', '') <> '' then
    insert into public.athletes (user_id, full_name, date_of_birth, is_published)
    values (new.id, meta ->> 'full_name', meta_dob, false)
    on conflict (user_id) do nothing;
  end if;

  if meta_role = 'coach' then
    gb := public.coach_clean_governing_body(meta ->> 'governing_body');
    insert into public.coach_requests (
      user_id, full_name, email, title, college, message, status,
      governing_body, division, sport, sport_gender, athletics_url, program_url, phone
    )
    values (
      new.id,
      coalesce(public.coach_clean_text(meta ->> 'full_name', 200), split_part(new.email, '@', 1)),
      new.email,
      public.coach_clean_text(meta ->> 'coach_title', 120),
      public.coach_clean_text(meta ->> 'institution', 200),
      public.coach_clean_text(meta ->> 'verification_note', 2000),
      'pending',
      gb,
      public.coach_clean_division(gb, meta ->> 'division'),
      'basketball',
      public.coach_clean_sport_gender(meta ->> 'sport_gender'),
      public.coach_clean_url(meta ->> 'athletics_url'),
      public.coach_clean_url(meta ->> 'program_url'),
      public.coach_clean_text(meta ->> 'phone', 40)
    )
    on conflict (user_id) do nothing
    returning id into req_id;

    if req_id is not null then
      insert into public.coach_request_reviews (request_id, action, actor_user_id)
      values (req_id, 'submitted', new.id);
      perform public.coach_notify_admins(
        'coach_application_submitted',
        'New coach application',
        coalesce(public.coach_clean_text(meta ->> 'full_name', 200), new.email)
          || ' applied as ' || coalesce(public.coach_clean_text(meta ->> 'coach_title', 120), 'coach')
          || ' at ' || coalesce(public.coach_clean_text(meta ->> 'institution', 200), 'an unspecified institution') || '.',
        '/admin/coaches'
      );
    end if;
  end if;

  return new;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 7. Applicant RPCs
-- ---------------------------------------------------------------------------

-- Edit the caller's own application while it is editable; a rejected /
-- needs-info / withdrawn application returns to pending (resubmission).
-- Also creates the application for a role-less account that has none (e.g.
-- signup metadata was dropped) — never for an account that already holds a
-- role.
create or replace function public.update_coach_application(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r public.coach_requests%rowtype;
  gb text;
  was text;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  perform set_config('thehub.coach_review', 'rpc', true);

  select * into r from public.coach_requests where user_id = uid for update;
  if not found then
    if exists (select 1 from public.user_roles where user_id = uid) then
      raise exception 'not authorized';
    end if;
    insert into public.coach_requests (user_id, full_name, email, status)
    select uid, coalesce(public.coach_clean_text(p ->> 'full_name', 200), coalesce(up.display_name, u.email)), u.email, 'pending'
    from auth.users u left join public.user_profiles up on up.id = u.id
    where u.id = uid
    returning * into r;
    was := null;
  else
    was := r.status;
    if r.status not in ('pending', 'rejected', 'needs_more_information', 'withdrawn') then
      raise exception 'application is not editable in status %', r.status;
    end if;
  end if;

  gb := case when p ? 'governing_body' then public.coach_clean_governing_body(p ->> 'governing_body') else r.governing_body end;
  if p ? 'governing_body' and (p ->> 'governing_body') is not null and gb is null then
    raise exception 'invalid governing_body';
  end if;
  if p ? 'sport_gender' and (p ->> 'sport_gender') is not null
     and public.coach_clean_sport_gender(p ->> 'sport_gender') is null then
    raise exception 'invalid sport_gender';
  end if;

  update public.coach_requests set
    full_name = coalesce(public.coach_clean_text(p ->> 'full_name', 200), full_name),
    title = case when p ? 'title' then public.coach_clean_text(p ->> 'title', 120) else title end,
    college = case when p ? 'college' then public.coach_clean_text(p ->> 'college', 200) else college end,
    message = case when p ? 'message' then public.coach_clean_text(p ->> 'message', 2000) else message end,
    governing_body = gb,
    -- An explicit null clears the division; an absent key keeps (re-cleans) it.
    division = case
      when p ? 'division' then public.coach_clean_division(gb, p ->> 'division')
      when p ? 'governing_body' then public.coach_clean_division(gb, division)
      else division end,
    sport_gender = case when p ? 'sport_gender' then public.coach_clean_sport_gender(p ->> 'sport_gender') else sport_gender end,
    athletics_url = case when p ? 'athletics_url' then public.coach_clean_url(p ->> 'athletics_url') else athletics_url end,
    program_url = case when p ? 'program_url' then public.coach_clean_url(p ->> 'program_url') else program_url end,
    phone = case when p ? 'phone' then public.coach_clean_text(p ->> 'phone', 40) else phone end,
    status = 'pending',
    resubmitted_at = case when was in ('rejected', 'needs_more_information', 'withdrawn') then now() else resubmitted_at end,
    reviewed_at = case when was in ('rejected', 'needs_more_information', 'withdrawn') then null else reviewed_at end,
    reviewed_by = case when was in ('rejected', 'needs_more_information', 'withdrawn') then null else reviewed_by end,
    rejection_reason = null,
    info_request_message = null
  where id = r.id
  returning * into r;

  if was is null or was in ('rejected', 'needs_more_information', 'withdrawn') then
    insert into public.coach_request_reviews (request_id, action, actor_user_id)
    values (r.id, case when was is null then 'submitted' else 'resubmitted' end, uid);
    perform public.coach_notify_admins(
      'coach_application_submitted',
      case when was is null then 'New coach application' else 'Coach application resubmitted' end,
      r.full_name || ' — ' || coalesce(r.title, 'coach') || ' at ' || coalesce(r.college, 'an unspecified institution') || '.',
      '/admin/coaches'
    );
  end if;

  return to_jsonb(r);
end;
$$;

create or replace function public.withdraw_coach_application()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r public.coach_requests%rowtype;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  perform set_config('thehub.coach_review', 'rpc', true);
  select * into r from public.coach_requests where user_id = uid for update;
  if not found then
    raise exception 'no coach application';
  end if;
  if r.status not in ('pending', 'needs_more_information') then
    raise exception 'application cannot be withdrawn in status %', r.status;
  end if;
  update public.coach_requests set status = 'withdrawn' where id = r.id returning * into r;
  insert into public.coach_request_reviews (request_id, action, actor_user_id)
  values (r.id, 'withdrawn', uid);
  return to_jsonb(r);
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Admin RPCs
-- ---------------------------------------------------------------------------

-- Atomic approval. Either p_program_id (an existing program, which becomes
-- verified if it wasn't) or p_program (admin-confirmed attributes; created or
-- matched on the 010 uniqueness key). Any failure rolls back everything.
create or replace function public.approve_coach_request(
  p_request_id uuid,
  p_program_id uuid default null,
  p_program jsonb default null,
  p_membership_role text default null,
  p_title text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_id uuid := auth.uid();
  r public.coach_requests%rowtype;
  prog public.recruiting_programs%rowtype;
  gb text;
  div text;
  gender text;
  inst text;
  mem_id uuid;
  has_role_now boolean;
begin
  if admin_id is null then
    raise exception 'not authenticated';
  end if;
  if not public.has_role('admin') then
    raise exception 'not authorized';
  end if;
  perform set_config('thehub.coach_review', 'rpc', true);

  select * into r from public.coach_requests where id = p_request_id for update;
  if not found then
    raise exception 'coach request not found';
  end if;
  if r.status not in ('pending', 'needs_more_information') then
    raise exception 'coach request is % — only pending or needs_more_information requests can be approved', r.status;
  end if;
  if not exists (select 1 from auth.users where id = r.user_id) then
    raise exception 'applicant account no longer exists';
  end if;
  if p_membership_role is not null and p_membership_role not in
     ('head_coach', 'assistant_coach', 'recruiting_coordinator', 'operations', 'staff', 'other') then
    raise exception 'invalid membership_role';
  end if;

  -- Program -----------------------------------------------------------------
  if p_program_id is not null then
    select * into prog from public.recruiting_programs where id = p_program_id for update;
    if not found then
      raise exception 'program not found';
    end if;
    if not prog.active then
      raise exception 'program is inactive';
    end if;
    update public.recruiting_programs
      set verified_at = coalesce(verified_at, now()),
          verified_by = coalesce(verified_by, admin_id)
      where id = prog.id
      returning * into prog;
  elsif p_program is not null then
    inst := public.coach_clean_text(p_program ->> 'institution_name', 200);
    gb := public.coach_clean_governing_body(p_program ->> 'governing_body');
    gender := public.coach_clean_sport_gender(p_program ->> 'sport_gender');
    if inst is null then raise exception 'program institution_name is required'; end if;
    if gb is null or gb = 'Unknown' then raise exception 'program governing_body must be NCAA, NAIA, NJCAA or Other'; end if;
    if gender is null then raise exception 'program sport_gender must be mens or womens'; end if;
    div := public.coach_clean_division(gb, p_program ->> 'division');
    if gb = 'NCAA' and div is null then raise exception 'NCAA programs need a division (D1, D2 or D3)'; end if;

    insert into public.recruiting_programs (
      institution_name, normalized_institution_name, governing_body, division, sport, sport_gender,
      athletics_url, program_url, official_url, active, verified_at, verified_by
    )
    values (
      inst, public.coach_normalize_institution(inst), gb, div,
      coalesce(public.coach_clean_text(p_program ->> 'sport', 40), 'basketball'), gender,
      public.coach_clean_url(p_program ->> 'athletics_url'),
      public.coach_clean_url(p_program ->> 'program_url'),
      public.coach_clean_url(p_program ->> 'program_url'),
      true, now(), admin_id
    )
    on conflict (normalized_institution_name, governing_body, sport, sport_gender) do update set
      institution_name = excluded.institution_name,
      division = coalesce(excluded.division, public.recruiting_programs.division),
      athletics_url = coalesce(excluded.athletics_url, public.recruiting_programs.athletics_url),
      program_url = coalesce(excluded.program_url, public.recruiting_programs.program_url),
      active = true,
      verified_at = coalesce(public.recruiting_programs.verified_at, now()),
      verified_by = coalesce(public.recruiting_programs.verified_by, admin_id)
    returning * into prog;
  else
    raise exception 'approval requires p_program_id or p_program';
  end if;

  -- Membership ------------------------------------------------------------------
  insert into public.coach_program_memberships (
    coach_user_id, program_id, title, membership_role, status, verified_at, verified_by, started_at, ended_at
  )
  values (
    r.user_id, prog.id, coalesce(public.coach_clean_text(p_title, 120), r.title), p_membership_role,
    'verified', now(), admin_id, current_date, null
  )
  on conflict (coach_user_id, program_id) do update set
    title = excluded.title,
    membership_role = coalesce(excluded.membership_role, public.coach_program_memberships.membership_role),
    status = 'verified',
    verified_at = now(),
    verified_by = admin_id,
    started_at = coalesce(public.coach_program_memberships.started_at, current_date),
    ended_at = null
  returning id into mem_id;

  -- Role (also re-derived by the membership trigger; explicit for clarity) ------
  has_role_now := public.sync_coach_role(r.user_id);
  if not has_role_now then
    raise exception 'coach role could not be derived after approval';
  end if;

  -- Request ---------------------------------------------------------------------
  update public.coach_requests set
    status = 'approved',
    reviewed_at = now(),
    reviewed_by = admin_id,
    approved_program_id = prog.id,
    approved_membership_id = mem_id,
    rejection_reason = null,
    info_request_message = null
  where id = r.id
  returning * into r;

  insert into public.coach_request_reviews (request_id, action, actor_user_id, internal_note)
  values (r.id, 'approved', admin_id, public.coach_clean_text(p_note, 2000));

  perform public.coach_notify(
    r.user_id,
    'coach_application_approved',
    'Coach access approved',
    'Your ' || public.coach_program_label(prog.institution_name, prog.sport_gender, prog.sport)
      || ' affiliation has been verified. Coach Mode is now available.',
    '/coach'
  );

  return jsonb_build_object(
    'request_id', r.id,
    'user_id', r.user_id,
    'program_id', prog.id,
    'membership_id', mem_id,
    'status', r.status
  );
end;
$$;

create or replace function public.reject_coach_request(
  p_request_id uuid,
  p_reason text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_id uuid := auth.uid();
  r public.coach_requests%rowtype;
  reason text := public.coach_clean_text(p_reason, 2000);
begin
  if admin_id is null then raise exception 'not authenticated'; end if;
  if not public.has_role('admin') then raise exception 'not authorized'; end if;
  if reason is null then raise exception 'a user-visible rejection reason is required'; end if;
  perform set_config('thehub.coach_review', 'rpc', true);

  select * into r from public.coach_requests where id = p_request_id for update;
  if not found then raise exception 'coach request not found'; end if;
  if r.status not in ('pending', 'needs_more_information') then
    raise exception 'coach request is % — only pending or needs_more_information requests can be rejected', r.status;
  end if;

  update public.coach_requests set
    status = 'rejected',
    reviewed_at = now(),
    reviewed_by = admin_id,
    rejection_reason = reason,
    info_request_message = null
  where id = r.id
  returning * into r;

  insert into public.coach_request_reviews (request_id, action, actor_user_id, public_message, internal_note)
  values (r.id, 'rejected', admin_id, reason, public.coach_clean_text(p_note, 2000));

  perform public.coach_notify(
    r.user_id,
    'coach_application_rejected',
    'Coach application needs attention',
    'We couldn''t verify the program information provided. Review your application for details.',
    '/coach/application'
  );

  return to_jsonb(r);
end;
$$;

create or replace function public.request_coach_info(
  p_request_id uuid,
  p_message text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_id uuid := auth.uid();
  r public.coach_requests%rowtype;
  msg text := public.coach_clean_text(p_message, 2000);
begin
  if admin_id is null then raise exception 'not authenticated'; end if;
  if not public.has_role('admin') then raise exception 'not authorized'; end if;
  if msg is null then raise exception 'a user-visible message is required'; end if;
  perform set_config('thehub.coach_review', 'rpc', true);

  select * into r from public.coach_requests where id = p_request_id for update;
  if not found then raise exception 'coach request not found'; end if;
  if r.status <> 'pending' then
    raise exception 'coach request is % — only pending requests can be sent back for more information', r.status;
  end if;

  update public.coach_requests set
    status = 'needs_more_information',
    reviewed_at = now(),
    reviewed_by = admin_id,
    info_request_message = msg
  where id = r.id
  returning * into r;

  insert into public.coach_request_reviews (request_id, action, actor_user_id, public_message, internal_note)
  values (r.id, 'info_requested', admin_id, msg, public.coach_clean_text(p_note, 2000));

  perform public.coach_notify(
    r.user_id,
    'coach_application_needs_information',
    'Coach application: more information needed',
    'We need a bit more to verify your affiliation. Open your application to see what''s missing.',
    '/coach/application'
  );

  return to_jsonb(r);
end;
$$;

-- Suspend / inactivate / reinstate a membership. The role follows in the same
-- statement via sync_coach_role. History is never deleted.
create or replace function public.set_coach_membership_status(
  p_membership_id uuid,
  p_status text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  admin_id uuid := auth.uid();
  m public.coach_program_memberships%rowtype;
  prog public.recruiting_programs%rowtype;
  req_id uuid;
  still_coach boolean;
begin
  if admin_id is null then raise exception 'not authenticated'; end if;
  if not public.has_role('admin') then raise exception 'not authorized'; end if;
  if p_status not in ('verified', 'suspended', 'inactive') then
    raise exception 'status must be verified, suspended or inactive';
  end if;
  perform set_config('thehub.coach_review', 'rpc', true);

  select * into m from public.coach_program_memberships where id = p_membership_id for update;
  if not found then raise exception 'membership not found'; end if;
  select * into prog from public.recruiting_programs where id = m.program_id;

  update public.coach_program_memberships set
    status = p_status,
    verified_at = case when p_status = 'verified' then now() else verified_at end,
    verified_by = case when p_status = 'verified' then admin_id else verified_by end,
    ended_at = case when p_status = 'inactive' then current_date else null end
  where id = m.id
  returning * into m;

  still_coach := public.sync_coach_role(m.coach_user_id);

  select id into req_id from public.coach_requests where user_id = m.coach_user_id;
  if req_id is not null then
    insert into public.coach_request_reviews (request_id, action, actor_user_id, internal_note)
    values (
      req_id,
      case p_status when 'verified' then 'membership_reinstated'
                    when 'suspended' then 'membership_suspended'
                    else 'membership_inactivated' end,
      admin_id,
      public.coach_clean_text(p_note, 2000)
    );
  end if;

  if p_status <> 'verified' then
    perform public.coach_notify(
      m.coach_user_id,
      'coach_membership_suspended',
      'Coach access paused',
      'Your ' || public.coach_program_label(prog.institution_name, prog.sport_gender, prog.sport)
        || ' membership is no longer active. Contact support if you believe this is an error.',
      '/coach'
    );
  end if;

  return jsonb_build_object('membership_id', m.id, 'status', m.status, 'has_coach_role', still_coach);
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. RLS
-- ---------------------------------------------------------------------------
alter table public.coach_request_reviews enable row level security;

drop policy if exists "admins read coach request reviews" on public.coach_request_reviews;
create policy "admins read coach request reviews" on public.coach_request_reviews
  for select to authenticated using (public.has_role('admin'));

-- Applications are created by the signup trigger or update_coach_application;
-- no client inserts (this also stops athletes/parents filing coach requests).
drop policy if exists "coach request insert" on public.coach_requests;

-- "coach request select" (own or admin) and "coach request admin update"
-- (admin) from setup.sql stay; the BEFORE UPDATE guard limits the admin
-- update policy to claim fields.

-- Found by supabase/tests/coach-onboarding.test.sql (§37): 007 rewrote the
-- bookmark insert policy without the coach-role check that 002 had, so any
-- signed-in account (pending coach, athlete) could bookmark a published
-- athlete. Contact info stayed gated (contacts select requires the role), but
-- the bookmark itself surfaces to the athlete as "a coach saved you".
-- Restore the role requirement; select/update/delete stay owner-only so a
-- revoked coach's rows remain cleanable.
drop policy if exists "saved athletes insert" on public.coach_saved_athletes;
create policy "saved athletes insert" on public.coach_saved_athletes
  for insert to authenticated
  with check (
    coach_user_id = auth.uid()
    and public.has_role('coach')
    and public.athlete_is_published(athlete_id)
  );

-- ---------------------------------------------------------------------------
-- 10. Grants
-- ---------------------------------------------------------------------------
revoke all on function public.coach_clean_text(text, integer) from public, anon, authenticated;
revoke all on function public.coach_clean_url(text) from public, anon, authenticated;
revoke all on function public.coach_clean_governing_body(text) from public, anon, authenticated;
revoke all on function public.coach_clean_division(text, text) from public, anon, authenticated;
revoke all on function public.coach_clean_sport_gender(text) from public, anon, authenticated;
revoke all on function public.coach_normalize_institution(text) from public, anon, authenticated;
revoke all on function public.coach_program_label(text, text, text) from public, anon, authenticated;
revoke all on function public.coach_notify(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function public.coach_notify_admins(text, text, text, text) from public, anon, authenticated;
revoke all on function public.sync_coach_role(uuid) from public, anon, authenticated;
revoke all on function public.trg_sync_coach_role_from_membership() from public, anon, authenticated;
revoke all on function public.trg_sync_coach_role_from_program() from public, anon, authenticated;
revoke all on function public.guard_coach_role_grant() from public, anon, authenticated;
revoke all on function public.guard_coach_request_review() from public, anon, authenticated;
revoke all on function public.guard_membership_verification() from public, anon, authenticated;

revoke all on function public.update_coach_application(jsonb) from public, anon;
grant execute on function public.update_coach_application(jsonb) to authenticated;
revoke all on function public.withdraw_coach_application() from public, anon;
grant execute on function public.withdraw_coach_application() to authenticated;
revoke all on function public.approve_coach_request(uuid, uuid, jsonb, text, text, text) from public, anon;
grant execute on function public.approve_coach_request(uuid, uuid, jsonb, text, text, text) to authenticated;
revoke all on function public.reject_coach_request(uuid, text, text) from public, anon;
grant execute on function public.reject_coach_request(uuid, text, text) to authenticated;
revoke all on function public.request_coach_info(uuid, text, text) from public, anon;
grant execute on function public.request_coach_info(uuid, text, text) to authenticated;
revoke all on function public.set_coach_membership_status(uuid, text, text) from public, anon;
grant execute on function public.set_coach_membership_status(uuid, text, text) to authenticated;
