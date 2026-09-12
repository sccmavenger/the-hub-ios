-- =============================================================================
-- The Hub — full database setup for a fresh Supabase project
--
-- Run this in the Supabase Dashboard → SQL Editor → New query → paste → Run.
-- The script is re-runnable: it uses IF NOT EXISTS and drops policies before
-- recreating them.
--
-- Column names/types mirror the Swift models' CodingKeys exactly.
-- =============================================================================

create extension if not exists pgcrypto;

-- Helper functions are declared before the tables they reference.
set check_function_bodies = off;

-- =============================================================================
-- Helper functions
-- =============================================================================

-- Keeps updated_at current on row updates.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Role check. SECURITY DEFINER so policies on user_roles itself don't recurse.
create or replace function public.has_role(check_role text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role = check_role
  );
$$;

create or replace function public.owns_athlete(aid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.athletes
    where id = aid and user_id = auth.uid()
  );
$$;

create or replace function public.is_guardian_of(aid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.athlete_guardians
    where athlete_id = aid and user_id = auth.uid()
  );
$$;

-- Owner, linked guardian, or admin.
create or replace function public.can_manage_athlete(aid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.owns_athlete(aid)
      or public.is_guardian_of(aid)
      or public.has_role('admin');
$$;

create or replace function public.athlete_is_published(aid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.athletes
    where id = aid and is_published = true
  );
$$;

-- =============================================================================
-- Tables
-- =============================================================================

create table if not exists public.user_profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('admin', 'coach', 'athlete', 'parent')),
  created_at timestamptz not null default now(),
  unique (user_id, role)
);

create table if not exists public.athletes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users (id) on delete cascade,
  full_name text not null,
  bio text,
  date_of_birth date,
  profile_photo_url text,
  high_school text,
  grad_year int,
  gpa numeric(4, 2),
  sat_score int,
  act_score int,
  height_inches int,
  weight_lbs int,
  position text,
  jersey_number text,
  sport_gender text check (sport_gender in ('mens', 'womens')),
  instagram_handle text,
  tiktok_handle text,
  intended_major text,
  hometown text,
  state text,
  zip_code text,
  latitude double precision,
  longitude double precision,
  ncaa_id text,
  is_published boolean not null default false,
  guardian_consent_at timestamptz,
  guardian_consent_email text,
  guardian_consent_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.athlete_photos (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references public.athletes (id) on delete cascade,
  url text not null,
  caption text,
  created_at timestamptz not null default now()
);

create table if not exists public.athlete_videos (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references public.athletes (id) on delete cascade,
  url text not null,
  title text,
  created_at timestamptz not null default now()
);

create table if not exists public.athlete_events (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references public.athletes (id) on delete cascade,
  event_date date not null,
  event_time text,
  opponent text,
  location text,
  notes text,
  is_mayb boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.athlete_college_interests (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references public.athletes (id) on delete cascade,
  college_name text not null,
  division text,
  state text,
  status text not null default 'interested'
    check (status in ('interested', 'applied', 'contacted', 'visiting', 'offered', 'committed')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.athlete_contacts (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null unique references public.athletes (id) on delete cascade,
  athlete_email text,
  athlete_phone text,
  guardian_name text,
  guardian_email text,
  guardian_phone text,
  club_coach_name text,
  club_coach_phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.athlete_guardians (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references public.athletes (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  relationship text,
  created_at timestamptz not null default now(),
  unique (athlete_id, user_id)
);

create table if not exists public.athlete_invites (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references public.athletes (id) on delete cascade,
  code text not null unique,
  invited_email text,
  relationship text,
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users (id),
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists public.athlete_profile_views (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references public.athletes (id) on delete cascade,
  viewer_user_id uuid references auth.users (id) on delete set null,
  viewer_role text not null,
  viewer_label text,
  created_at timestamptz not null default now()
);

create table if not exists public.coach_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  full_name text not null,
  email text not null,
  title text,
  college text,
  message text,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

create table if not exists public.coach_saved_athletes (
  id uuid primary key default gen_random_uuid(),
  coach_user_id uuid not null references auth.users (id) on delete cascade,
  athlete_id uuid not null references public.athletes (id) on delete cascade,
  stage text not null default 'watching'
    check (stage in ('watching', 'evaluating', 'contacted', 'offered', 'passed')),
  tags text[] not null default '{}',
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (coach_user_id, athlete_id)
);

create table if not exists public.coach_saved_searches (
  id uuid primary key default gen_random_uuid(),
  coach_user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  filters jsonb not null default '{}',
  alerts_enabled boolean not null default false,
  last_run_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  athlete_id uuid not null references public.athletes (id) on delete cascade,
  coach_user_id uuid not null references auth.users (id) on delete cascade,
  sender_user_id uuid not null references auth.users (id) on delete cascade,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  body text,
  type text not null,
  link text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

-- =============================================================================
-- Indexes
-- =============================================================================

create index if not exists idx_user_roles_user on public.user_roles (user_id);
create index if not exists idx_athletes_published on public.athletes (is_published) where is_published;
create index if not exists idx_athlete_photos_athlete on public.athlete_photos (athlete_id);
create index if not exists idx_athlete_videos_athlete on public.athlete_videos (athlete_id);
create index if not exists idx_athlete_events_athlete on public.athlete_events (athlete_id, event_date);
create index if not exists idx_college_interests_athlete on public.athlete_college_interests (athlete_id);
create index if not exists idx_guardians_user on public.athlete_guardians (user_id);
create index if not exists idx_profile_views_athlete on public.athlete_profile_views (athlete_id, created_at);
create index if not exists idx_saved_athletes_athlete on public.coach_saved_athletes (athlete_id);
create index if not exists idx_saved_athletes_coach on public.coach_saved_athletes (coach_user_id);
create index if not exists idx_messages_athlete on public.messages (athlete_id, created_at);
create index if not exists idx_messages_coach on public.messages (coach_user_id, created_at);
create index if not exists idx_notifications_user on public.notifications (user_id, created_at);

-- =============================================================================
-- updated_at triggers
-- =============================================================================

drop trigger if exists set_updated_at on public.user_profiles;
create trigger set_updated_at before update on public.user_profiles
  for each row execute function public.set_updated_at();

drop trigger if exists set_updated_at on public.athletes;
create trigger set_updated_at before update on public.athletes
  for each row execute function public.set_updated_at();

drop trigger if exists set_updated_at on public.athlete_college_interests;
create trigger set_updated_at before update on public.athlete_college_interests
  for each row execute function public.set_updated_at();

drop trigger if exists set_updated_at on public.athlete_contacts;
create trigger set_updated_at before update on public.athlete_contacts
  for each row execute function public.set_updated_at();

drop trigger if exists set_updated_at on public.coach_saved_athletes;
create trigger set_updated_at before update on public.coach_saved_athletes
  for each row execute function public.set_updated_at();

drop trigger if exists set_updated_at on public.coach_saved_searches;
create trigger set_updated_at before update on public.coach_saved_searches
  for each row execute function public.set_updated_at();

-- Auto-create a user_profiles row for every new auth user.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_profiles (id, email, display_name)
  values (new.id, new.email, new.raw_user_meta_data ->> 'full_name')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- =============================================================================
-- Row Level Security
-- =============================================================================

alter table public.user_profiles enable row level security;
alter table public.user_roles enable row level security;
alter table public.athletes enable row level security;
alter table public.athlete_photos enable row level security;
alter table public.athlete_videos enable row level security;
alter table public.athlete_events enable row level security;
alter table public.athlete_college_interests enable row level security;
alter table public.athlete_contacts enable row level security;
alter table public.athlete_guardians enable row level security;
alter table public.athlete_invites enable row level security;
alter table public.athlete_profile_views enable row level security;
alter table public.coach_requests enable row level security;
alter table public.coach_saved_athletes enable row level security;
alter table public.coach_saved_searches enable row level security;
alter table public.messages enable row level security;
alter table public.notifications enable row level security;

-- ---------------------------------------------------------------------------
-- user_profiles
-- ---------------------------------------------------------------------------
drop policy if exists "own profile select" on public.user_profiles;
create policy "own profile select" on public.user_profiles
  for select to authenticated
  using (id = auth.uid() or public.has_role('admin'));

drop policy if exists "own profile update" on public.user_profiles;
create policy "own profile update" on public.user_profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- user_roles — users self-assign only athlete/parent; coach/admin are granted
-- by an admin (or manually in the dashboard).
-- ---------------------------------------------------------------------------
drop policy if exists "own roles select" on public.user_roles;
create policy "own roles select" on public.user_roles
  for select to authenticated
  using (user_id = auth.uid() or public.has_role('admin'));

drop policy if exists "self assign basic role" on public.user_roles;
create policy "self assign basic role" on public.user_roles
  for insert to authenticated
  with check (user_id = auth.uid() and role in ('athlete', 'parent'));

drop policy if exists "admin manage roles" on public.user_roles;
create policy "admin manage roles" on public.user_roles
  for all to authenticated
  using (public.has_role('admin'))
  with check (public.has_role('admin'));

-- ---------------------------------------------------------------------------
-- athletes
-- ---------------------------------------------------------------------------
drop policy if exists "athletes select" on public.athletes;
create policy "athletes select" on public.athletes
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.is_guardian_of(id)
    or public.has_role('admin')
    or (is_published and public.has_role('coach'))
  );

drop policy if exists "athletes insert" on public.athletes;
create policy "athletes insert" on public.athletes
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "athletes update" on public.athletes;
create policy "athletes update" on public.athletes
  for update to authenticated
  using (user_id = auth.uid() or public.is_guardian_of(id) or public.has_role('admin'))
  with check (user_id = auth.uid() or public.is_guardian_of(id) or public.has_role('admin'));

drop policy if exists "athletes delete" on public.athletes;
create policy "athletes delete" on public.athletes
  for delete to authenticated
  using (user_id = auth.uid() or public.has_role('admin'));

-- ---------------------------------------------------------------------------
-- Athlete child tables. Photos, videos, events, and contact info are visible
-- to coaches when the athlete is published; the college list stays private.
-- ---------------------------------------------------------------------------
drop policy if exists "photos select" on public.athlete_photos;
create policy "photos select" on public.athlete_photos
  for select to authenticated
  using (
    public.can_manage_athlete(athlete_id)
    or (public.athlete_is_published(athlete_id) and public.has_role('coach'))
  );

drop policy if exists "photos write" on public.athlete_photos;
create policy "photos write" on public.athlete_photos
  for all to authenticated
  using (public.can_manage_athlete(athlete_id))
  with check (public.can_manage_athlete(athlete_id));

drop policy if exists "videos select" on public.athlete_videos;
create policy "videos select" on public.athlete_videos
  for select to authenticated
  using (
    public.can_manage_athlete(athlete_id)
    or (public.athlete_is_published(athlete_id) and public.has_role('coach'))
  );

drop policy if exists "videos write" on public.athlete_videos;
create policy "videos write" on public.athlete_videos
  for all to authenticated
  using (public.can_manage_athlete(athlete_id))
  with check (public.can_manage_athlete(athlete_id));

drop policy if exists "events select" on public.athlete_events;
create policy "events select" on public.athlete_events
  for select to authenticated
  using (
    public.can_manage_athlete(athlete_id)
    or (public.athlete_is_published(athlete_id) and public.has_role('coach'))
  );

drop policy if exists "events write" on public.athlete_events;
create policy "events write" on public.athlete_events
  for all to authenticated
  using (public.can_manage_athlete(athlete_id))
  with check (public.can_manage_athlete(athlete_id));

drop policy if exists "college interests all" on public.athlete_college_interests;
create policy "college interests all" on public.athlete_college_interests
  for all to authenticated
  using (public.can_manage_athlete(athlete_id))
  with check (public.can_manage_athlete(athlete_id));

drop policy if exists "contacts select" on public.athlete_contacts;
create policy "contacts select" on public.athlete_contacts
  for select to authenticated
  using (
    public.can_manage_athlete(athlete_id)
    or (public.athlete_is_published(athlete_id) and public.has_role('coach'))
  );

drop policy if exists "contacts write" on public.athlete_contacts;
create policy "contacts write" on public.athlete_contacts
  for all to authenticated
  using (public.can_manage_athlete(athlete_id))
  with check (public.can_manage_athlete(athlete_id));

-- ---------------------------------------------------------------------------
-- athlete_guardians / athlete_invites
-- ---------------------------------------------------------------------------
drop policy if exists "guardians select" on public.athlete_guardians;
create policy "guardians select" on public.athlete_guardians
  for select to authenticated
  using (user_id = auth.uid() or public.can_manage_athlete(athlete_id));

drop policy if exists "guardians write" on public.athlete_guardians;
create policy "guardians write" on public.athlete_guardians
  for all to authenticated
  using (public.owns_athlete(athlete_id) or public.has_role('admin'))
  with check (public.owns_athlete(athlete_id) or public.has_role('admin'));

drop policy if exists "invites all" on public.athlete_invites;
create policy "invites all" on public.athlete_invites
  for all to authenticated
  using (public.can_manage_athlete(athlete_id))
  with check (public.can_manage_athlete(athlete_id));

-- ---------------------------------------------------------------------------
-- athlete_profile_views — anyone signed in can record a view; only the
-- athlete's side can read them.
-- ---------------------------------------------------------------------------
drop policy if exists "views insert" on public.athlete_profile_views;
create policy "views insert" on public.athlete_profile_views
  for insert to authenticated
  with check (true);

drop policy if exists "views select" on public.athlete_profile_views;
create policy "views select" on public.athlete_profile_views
  for select to authenticated
  using (public.can_manage_athlete(athlete_id));

-- ---------------------------------------------------------------------------
-- coach_requests
-- ---------------------------------------------------------------------------
drop policy if exists "coach request insert" on public.coach_requests;
create policy "coach request insert" on public.coach_requests
  for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "coach request select" on public.coach_requests;
create policy "coach request select" on public.coach_requests
  for select to authenticated
  using (user_id = auth.uid() or public.has_role('admin'));

drop policy if exists "coach request admin update" on public.coach_requests;
create policy "coach request admin update" on public.coach_requests
  for update to authenticated
  using (public.has_role('admin'))
  with check (public.has_role('admin'));

-- ---------------------------------------------------------------------------
-- coach_saved_athletes / coach_saved_searches
-- ---------------------------------------------------------------------------
drop policy if exists "saved athletes all" on public.coach_saved_athletes;
create policy "saved athletes all" on public.coach_saved_athletes
  for all to authenticated
  using (coach_user_id = auth.uid())
  with check (coach_user_id = auth.uid());

drop policy if exists "saved searches all" on public.coach_saved_searches;
create policy "saved searches all" on public.coach_saved_searches
  for all to authenticated
  using (coach_user_id = auth.uid())
  with check (coach_user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- messages — visible to the coach on the thread and the athlete's side.
-- ---------------------------------------------------------------------------
drop policy if exists "messages select" on public.messages;
create policy "messages select" on public.messages
  for select to authenticated
  using (coach_user_id = auth.uid() or public.can_manage_athlete(athlete_id));

drop policy if exists "messages insert" on public.messages;
create policy "messages insert" on public.messages
  for insert to authenticated
  with check (
    sender_user_id = auth.uid()
    and (
      (coach_user_id = auth.uid() and public.has_role('coach'))
      or public.can_manage_athlete(athlete_id)
    )
  );

drop policy if exists "messages update" on public.messages;
create policy "messages update" on public.messages
  for update to authenticated
  using (coach_user_id = auth.uid() or public.can_manage_athlete(athlete_id))
  with check (coach_user_id = auth.uid() or public.can_manage_athlete(athlete_id));

-- ---------------------------------------------------------------------------
-- notifications
-- ---------------------------------------------------------------------------
drop policy if exists "notifications select" on public.notifications;
create policy "notifications select" on public.notifications
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "notifications update" on public.notifications;
create policy "notifications update" on public.notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- =============================================================================
-- Storage — public athlete-media bucket; each user writes only inside a
-- folder named with their own user id ("<uid>/...").
-- =============================================================================

insert into storage.buckets (id, name, public)
values ('athlete-media', 'athlete-media', true)
on conflict (id) do nothing;

drop policy if exists "athlete media public read" on storage.objects;
create policy "athlete media public read" on storage.objects
  for select
  using (bucket_id = 'athlete-media');

drop policy if exists "athlete media owner insert" on storage.objects;
create policy "athlete media owner insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'athlete-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "athlete media owner update" on storage.objects;
create policy "athlete media owner update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'athlete-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'athlete-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "athlete media owner delete" on storage.objects;
create policy "athlete media owner delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'athlete-media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
