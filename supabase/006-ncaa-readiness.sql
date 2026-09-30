-- =============================================================================
-- 006 — NCAA Journey v1: self-reported eligibility readiness per athlete.
-- Everything here is athlete/guardian-entered planning data, never an NCAA
-- determination — the `source` column records provenance so future
-- integrations (school-verified, NCAA-verified) can upgrade rows in place.
-- Coaches get NO read access in v1; readiness surfaces on the coach side
-- later, with provenance labels, once coach verification ships.
-- Re-runnable.
-- =============================================================================

create table if not exists public.athlete_ncaa_readiness (
  athlete_id uuid primary key references public.athletes (id) on delete cascade,
  intended_division text not null default 'Unsure'
    check (intended_division in ('D1', 'D2', 'D3', 'Unsure')),
  ec_account_status text not null default 'not_started'
    check (ec_account_status in ('not_started', 'profile_page', 'certification')),
  core_courses_completed int not null default 0
    check (core_courses_completed between 0 and 16),
  estimated_core_gpa numeric(3,2)
    check (estimated_core_gpa is null or (estimated_core_gpa >= 0 and estimated_core_gpa <= 5)),
  transcript_sent boolean not null default false,
  amateurism_done boolean not null default false,
  final_cert_requested boolean not null default false,
  source text not null default 'self_reported'
    check (source in ('self_reported', 'guardian_verified', 'school_verified', 'ncaa_verified')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.athlete_ncaa_readiness enable row level security;

drop policy if exists "managers manage ncaa readiness" on public.athlete_ncaa_readiness;
create policy "managers manage ncaa readiness" on public.athlete_ncaa_readiness
  for all to authenticated
  using (public.can_manage_athlete(athlete_id))
  with check (public.can_manage_athlete(athlete_id));

drop policy if exists "admins view ncaa readiness" on public.athlete_ncaa_readiness;
create policy "admins view ncaa readiness" on public.athlete_ncaa_readiness
  for select to authenticated
  using (public.has_role('admin'));

drop trigger if exists set_updated_at on public.athlete_ncaa_readiness;
create trigger set_updated_at before update on public.athlete_ncaa_readiness
  for each row execute function public.set_updated_at();
