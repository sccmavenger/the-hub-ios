-- =============================================================================
-- 010 — Recruiting Rules Engine: schema.
--
-- Added 2026-09-30 per docs/RECRUITING-RULES-ENGINE-SPEC.md. Moves recruiting
-- rule authority out of the iOS binary (Compliance.swift hard-coded June 15)
-- into versioned, sourced, effective-dated rows that a single deterministic
-- SQL evaluator (011) reads. No rule logic lives here — only storage.
--
-- Tables:
--   recruiting_rule_sources        official documents a rule cites
--   recruiting_rules               versioned rules (draft/published/retired)
--   recruiting_programs            normalized institution + sport + division
--   coach_program_memberships      verified coach ↔ program association
--   recruiting_compliance_decisions audit log for enforcement-path evaluations
-- Columns:
--   athletes.academic_calendar_type, athletes.sophomore_completed_on
-- Flags (app_settings):
--   recruiting_rules_engine_enabled       (seeded TRUE  — Stage A shadow/display)
--   recruiting_rules_enforcement_enabled  (seeded FALSE — Stage B hard-block)
--
-- Re-runnable.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Sources
-- ---------------------------------------------------------------------------
create table if not exists public.recruiting_rule_sources (
  id uuid primary key default gen_random_uuid(),
  governing_body text not null,
  title text not null,
  source_url text not null,
  source_reference text,
  published_at date,
  retrieved_at timestamptz not null,
  checksum text,
  notes text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 2. Rules
--
-- One row = one version of one rule. A rule is identified across versions by
-- rule_key (stable, human-readable). Only status = 'published' rows are ever
-- consulted by the evaluator; at most one published row per rule_key.
--
-- Timing model (evaluated by 011, never by clients):
--   academic_milestone_type
--     null                        untimed — `decision` applies for the whole
--                                 effective window
--     'grad_year_offset'          start = start_month/start_day of
--                                 (athlete.grad_year + start_year_offset_from_grad)
--                                 at start_time in start_time_zone
--     'sophomore_completed_offset' start = athlete.sophomore_completed_on
--                                 + start_day_offset days, at start_time
--     'absolute'                  start = absolute_start_at (end = absolute_end_at)
--   Before start: status = decision. From start on: status = decision_after_start.
--
-- conditions (jsonb) is matched key-by-key against the evaluation context.
-- Supported keys in this release: academic_calendar_type (string or array).
-- A condition whose context value is NULL is "unknown", which makes the
-- evaluator return needs_review rather than guessing.
-- ---------------------------------------------------------------------------
create table if not exists public.recruiting_rules (
  id uuid primary key default gen_random_uuid(),
  rule_key text not null,

  governing_body text not null,
  division text,
  sport text,
  sport_gender text,

  actor_type text not null
    check (actor_type in ('coach', 'athlete', 'institution')),
  action_type text not null,

  decision text not null
    check (decision in ('permitted', 'prohibited', 'permitted_with_restrictions')),
  decision_after_start text
    check (decision_after_start in ('permitted', 'permitted_with_restrictions')),
  enforcement_level text not null
    check (enforcement_level in ('hard_block', 'warning', 'informational', 'none')),

  academic_milestone_type text
    check (academic_milestone_type in ('grad_year_offset', 'sophomore_completed_offset', 'absolute')),
  start_month integer check (start_month between 1 and 12),
  start_day integer check (start_day between 1 and 31),
  start_year_offset_from_grad integer,
  start_day_offset integer,
  start_time time not null default '00:00',
  start_time_zone text not null default 'America/Indiana/Indianapolis',
  absolute_start_at timestamptz,
  absolute_end_at timestamptz,

  conditions jsonb not null default '{}'::jsonb,
  exception_priority integer not null default 0,

  plain_english_summary text not null,
  plain_english_summary_after text,

  source_id uuid not null references public.recruiting_rule_sources (id),

  effective_from date not null,
  effective_until date,

  rule_version integer not null,
  status text not null check (status in ('draft', 'published', 'retired')),

  last_verified_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  unique (rule_key, rule_version),
  check (effective_until is null or effective_until >= effective_from),
  check (absolute_end_at is null or absolute_start_at is null or absolute_end_at > absolute_start_at),
  check (
    academic_milestone_type is distinct from 'grad_year_offset'
    or (start_month is not null and start_day is not null and start_year_offset_from_grad is not null)
  ),
  check (
    academic_milestone_type is distinct from 'sophomore_completed_offset'
    or start_day_offset is not null
  ),
  check (
    academic_milestone_type is distinct from 'absolute'
    or absolute_start_at is not null
  ),
  check (academic_milestone_type is null or decision_after_start is not null)
);

-- One live version per rule.
create unique index if not exists uq_recruiting_rules_one_published
  on public.recruiting_rules (rule_key) where status = 'published';

-- Decision-path lookup.
create index if not exists idx_recruiting_rules_lookup
  on public.recruiting_rules (governing_body, actor_type, action_type, status)
  where status = 'published';

drop trigger if exists set_updated_at on public.recruiting_rules;
create trigger set_updated_at before update on public.recruiting_rules
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3. Programs and coach memberships
-- ---------------------------------------------------------------------------
create table if not exists public.recruiting_programs (
  id uuid primary key default gen_random_uuid(),
  institution_name text not null,
  normalized_institution_name text not null,
  governing_body text not null,
  division text,
  sport text not null,
  sport_gender text not null,
  external_id text,
  official_url text,
  active boolean not null default true,
  source_url text,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (normalized_institution_name, governing_body, sport, sport_gender)
);

create index if not exists idx_recruiting_programs_normalized
  on public.recruiting_programs (normalized_institution_name);

drop trigger if exists set_updated_at on public.recruiting_programs;
create trigger set_updated_at before update on public.recruiting_programs
  for each row execute function public.set_updated_at();

create table if not exists public.coach_program_memberships (
  id uuid primary key default gen_random_uuid(),
  coach_user_id uuid not null references auth.users (id) on delete cascade,
  program_id uuid not null references public.recruiting_programs (id) on delete cascade,
  title text,
  status text not null check (status in ('pending', 'verified', 'rejected', 'inactive')),
  verified_at timestamptz,
  verified_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (coach_user_id, program_id)
);

create index if not exists idx_coach_program_memberships_coach
  on public.coach_program_memberships (coach_user_id) where status = 'verified';

drop trigger if exists set_updated_at on public.coach_program_memberships;
create trigger set_updated_at before update on public.coach_program_memberships
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 4. Decision audit log (enforcement-sensitive evaluations only). Never
--    stores message bodies. context_snapshot holds only the non-identifying
--    rule inputs (division, sport, calendar type, grad year).
-- ---------------------------------------------------------------------------
create table if not exists public.recruiting_compliance_decisions (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid,
  athlete_id uuid,
  program_id uuid,
  action_type text not null,
  decision text not null,
  enforcement_level text not null,
  rule_id uuid,
  rule_version integer,
  missing_context text[],
  evaluated_at timestamptz not null default now(),
  evaluation_source text not null default 'rpc',
  context_snapshot jsonb
);

create index if not exists idx_recruiting_decisions_evaluated_at
  on public.recruiting_compliance_decisions (evaluated_at desc);
create index if not exists idx_recruiting_decisions_rule
  on public.recruiting_compliance_decisions (rule_id) where rule_id is not null;

-- ---------------------------------------------------------------------------
-- 5. Athlete academic context.
--    Default is traditional_us: The Hub serves U.S. high-school basketball
--    players, and the NCAA's standard rule formulation (grad-year math) is
--    written for that calendar. 'nontraditional' triggers the bylaws'
--    Southern-Hemisphere-style provisions, which need sophomore_completed_on;
--    'unknown' makes the evaluator return needs_review rather than guess.
-- ---------------------------------------------------------------------------
alter table public.athletes
  add column if not exists academic_calendar_type text not null default 'traditional_us';
alter table public.athletes
  add column if not exists sophomore_completed_on date;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'athletes_academic_calendar_type_check'
  ) then
    alter table public.athletes
      add constraint athletes_academic_calendar_type_check
      check (academic_calendar_type in ('traditional_us', 'nontraditional', 'unknown'));
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 6. RLS
-- ---------------------------------------------------------------------------
alter table public.recruiting_rule_sources enable row level security;
alter table public.recruiting_rules enable row level security;
alter table public.recruiting_programs enable row level security;
alter table public.coach_program_memberships enable row level security;
alter table public.recruiting_compliance_decisions enable row level security;

-- Sources and rules: every signed-in client may read (the UI shows source
-- attribution); only admins may write. Publication is expected to happen via
-- migrations (docs/RECRUITING-RULE-MAINTENANCE.md), but the admin policy
-- keeps a future admin portal possible without weakening anything.
drop policy if exists "rule sources readable" on public.recruiting_rule_sources;
create policy "rule sources readable" on public.recruiting_rule_sources
  for select to authenticated using (true);
drop policy if exists "admins write rule sources" on public.recruiting_rule_sources;
create policy "admins write rule sources" on public.recruiting_rule_sources
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "rules readable" on public.recruiting_rules;
create policy "rules readable" on public.recruiting_rules
  for select to authenticated using (true);
drop policy if exists "admins write rules" on public.recruiting_rules;
create policy "admins write rules" on public.recruiting_rules
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

drop policy if exists "programs readable" on public.recruiting_programs;
create policy "programs readable" on public.recruiting_programs
  for select to authenticated using (true);
drop policy if exists "admins write programs" on public.recruiting_programs;
create policy "admins write programs" on public.recruiting_programs
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

-- Memberships: a coach sees their own; admins see and manage all. Verification
-- is admin-controlled — coaches cannot insert or flip their own status.
drop policy if exists "coach reads own memberships" on public.coach_program_memberships;
create policy "coach reads own memberships" on public.coach_program_memberships
  for select to authenticated
  using (coach_user_id = auth.uid() or public.has_role('admin'));
drop policy if exists "admins write memberships" on public.coach_program_memberships;
create policy "admins write memberships" on public.coach_program_memberships
  for all to authenticated
  using (public.has_role('admin')) with check (public.has_role('admin'));

-- Audit log: admin read only. Rows are written by security-definer functions.
drop policy if exists "admins read compliance decisions" on public.recruiting_compliance_decisions;
create policy "admins read compliance decisions" on public.recruiting_compliance_decisions
  for select to authenticated using (public.has_role('admin'));

-- ---------------------------------------------------------------------------
-- 7. Feature flags (extends 008-app-settings). Never overwrite existing values.
-- ---------------------------------------------------------------------------
insert into public.app_settings (key, bool_value, description)
values
  (
    'recruiting_rules_engine_enabled',
    true,
    'Recruiting Rules Engine: clients call evaluate_recruiting_action and show action-specific recruiting status (NCAA Journey, Colleges, Messages). OFF shows "Recruiting status unavailable" — never a guessed date.'
  ),
  (
    'recruiting_rules_enforcement_enabled',
    false,
    'Recruiting Rules Engine: when ON, a verified coach''s in-app message is rejected (RECRUITING_ACTION_PROHIBITED) if a published hard-block rule says the action is prohibited for that verified program and athlete. OFF = shadow mode (evaluate + log only).'
  )
on conflict (key) do nothing;
