-- =============================================================================
-- 013 — Recruiting Rules Engine: messaging enforcement at the database boundary.
--
-- Coach-sent rows in public.messages are evaluated by the same evaluator
-- (011) before insert. Athlete/guardian senders are never subject to the
-- coach-initiated restriction (spec §1.3). The trigger is ADDITIVE to the
-- existing controls, which keep firing in this order:
--   trg_enforce_message_blocks    (002) blocked pair → error (wins first)
--   trg_enforce_recruiting_rules  (013) this migration
--   RLS "messages insert"         (007) coach → published athletes only
--   trg_notify_on_message         (002) AFTER insert; never runs on a reject
--   trg_message_immutable         (007) extended here to the compliance columns
--
-- Behaviour (spec §14):
--   sender = athlete/guardian            → allow, compliance columns null
--   coach, no verified program           → needs_review → allow + audit row
--   coach, prohibited + hard_block       → reject with RECRUITING_ACTION_PROHIBITED
--                                          ONLY when recruiting_rules_enforcement_enabled
--                                          is true and the program context is verified;
--                                          otherwise shadow: allow + audit row
--   coach, permitted / with restrictions → allow, stamp compliance columns
--
-- Stable error: message = 'RECRUITING_ACTION_PROHIBITED', hint = user-facing
-- text, detail = decision JSON. PostgREST relays all three to clients.
-- Re-runnable.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Compliance metadata on messages (spec §15). Which rule allowed a coach
--    message at send time. Null for athlete/guardian messages.
-- ---------------------------------------------------------------------------
alter table public.messages add column if not exists compliance_status text;
alter table public.messages add column if not exists compliance_rule_id uuid references public.recruiting_rules (id);
alter table public.messages add column if not exists compliance_rule_version integer;
alter table public.messages add column if not exists compliance_evaluated_at timestamptz;

-- Immutable like body/identity (007). read_at remains the only mutable column.
create or replace function public.enforce_message_immutable()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.body is distinct from old.body
     or new.sender_user_id is distinct from old.sender_user_id
     or new.coach_user_id is distinct from old.coach_user_id
     or new.athlete_id is distinct from old.athlete_id
     or new.created_at is distinct from old.created_at
     or new.compliance_status is distinct from old.compliance_status
     or new.compliance_rule_id is distinct from old.compliance_rule_id
     or new.compliance_rule_version is distinct from old.compliance_rule_version
     or new.compliance_evaluated_at is distinct from old.compliance_evaluated_at then
    raise exception 'Messages cannot be edited after sending';
  end if;
  return new;
end;
$$;
-- Trigger trg_message_immutable (007) already points at this function.

-- ---------------------------------------------------------------------------
-- 2. Enforcement-path resolver. Program context comes ONLY from a verified
--    coach_program_memberships row joined to a verified recruiting_programs
--    row. Zero or ambiguous memberships → needs_review; nothing is guessed
--    from coach_requests.college.
-- ---------------------------------------------------------------------------
create or replace function public.recruiting_enforce_coach_action(
  p_coach_user_id uuid,
  p_athlete_id uuid,
  p_action_type text,
  p_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
  n_programs integer;
  prog record;
  ctx jsonb;
  result jsonb;
begin
  select grad_year, sport_gender, academic_calendar_type, sophomore_completed_on
    into a
  from athletes where id = p_athlete_id;
  if not found then
    raise exception 'athlete not found';
  end if;

  select count(*) into n_programs
  from coach_program_memberships m
  join recruiting_programs p on p.id = m.program_id
  where m.coach_user_id = p_coach_user_id
    and m.status = 'verified'
    and p.active
    and p.verified_at is not null
    and p.sport = 'basketball'
    and (a.sport_gender is null or p.sport_gender = a.sport_gender);

  if n_programs = 0 then
    ctx := jsonb_build_object(
      'actor_type', recruiting_actor_for_action(p_action_type),
      'action_type', p_action_type,
      'context_source', 'none'
    );
    return recruiting_decision_json(
      ctx, p_at, 'needs_review',
      'Coach has no verified program membership for this athlete''s sport',
      'We don''t have a verified program and division for this coach yet, so The Hub can''t apply a recruiting rule to this message.',
      null, 'none', array['coach.verified_program'], false, null
    );
  elsif n_programs > 1 then
    ctx := jsonb_build_object(
      'actor_type', recruiting_actor_for_action(p_action_type),
      'action_type', p_action_type,
      'context_source', 'none'
    );
    return recruiting_decision_json(
      ctx, p_at, 'needs_review',
      'Coach has ' || n_programs || ' verified programs for this sport; cannot choose one',
      'This coach is verified with more than one program, so The Hub can''t tell which recruiting rule applies to this message.',
      null, 'none', array['coach.verified_program.ambiguous'], false, null
    );
  end if;

  select p.* into prog
  from coach_program_memberships m
  join recruiting_programs p on p.id = m.program_id
  where m.coach_user_id = p_coach_user_id
    and m.status = 'verified'
    and p.active
    and p.verified_at is not null
    and p.sport = 'basketball'
    and (a.sport_gender is null or p.sport_gender = a.sport_gender);

  ctx := jsonb_build_object(
    'governing_body', prog.governing_body,
    'division', prog.division,
    'sport', prog.sport,
    'sport_gender', prog.sport_gender,
    'program_id', prog.id,
    'context_source', 'verified_program',
    'actor_type', recruiting_actor_for_action(p_action_type),
    'action_type', p_action_type,
    'athlete_grad_year', a.grad_year,
    'athlete_academic_calendar_type', a.academic_calendar_type,
    'athlete_sophomore_completed_on', a.sophomore_completed_on
  );

  result := recruiting_evaluate_core(ctx, p_at);
  return result || jsonb_build_object('program_id', prog.id);
end;
$$;

-- Coach preflight RPC (spec §18): the signed-in coach asks about their own
-- send before sending. Same resolver the trigger uses, so preflight and
-- enforcement cannot disagree except by the passage of time.
create or replace function public.evaluate_my_coach_action(
  p_athlete_id uuid,
  p_action_type text default 'coach_send_recruiting_electronic_correspondence'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not (has_role('coach') and athlete_is_published(p_athlete_id)) then
    raise exception 'not authorized';
  end if;
  if recruiting_actor_for_action(p_action_type) is distinct from 'coach' then
    raise exception 'not a coach action';
  end if;
  return recruiting_enforce_coach_action(auth.uid(), p_athlete_id, p_action_type, now());
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. BEFORE INSERT trigger on messages
-- ---------------------------------------------------------------------------
create or replace function public.enforce_recruiting_rules_on_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  action constant text := 'coach_send_recruiting_electronic_correspondence';
  decision jsonb;
  enforcement_on boolean;
  missing text[];
begin
  -- Clients never set compliance columns; the trigger owns them.
  new.compliance_status := null;
  new.compliance_rule_id := null;
  new.compliance_rule_version := null;
  new.compliance_evaluated_at := null;

  -- Athlete/guardian outreach is not restricted by coach-initiated rules.
  if new.sender_user_id is distinct from new.coach_user_id then
    return new;
  end if;

  decision := recruiting_enforce_coach_action(new.sender_user_id, new.athlete_id, action, now());

  select coalesce(bool_value, false) into enforcement_on
  from app_settings where key = 'recruiting_rules_enforcement_enabled';
  enforcement_on := coalesce(enforcement_on, false);

  missing := array(select jsonb_array_elements_text(coalesce(decision -> 'missing_context', '[]'::jsonb)));

  -- Audit every coach evaluation (no message body; spec §16).
  insert into recruiting_compliance_decisions (
    actor_user_id, athlete_id, program_id, action_type, decision, enforcement_level,
    rule_id, rule_version, missing_context, evaluated_at, evaluation_source, context_snapshot
  ) values (
    new.sender_user_id, new.athlete_id, nullif(decision ->> 'program_id', '')::uuid, action,
    decision ->> 'status', coalesce(decision ->> 'enforcement', 'none'),
    nullif(decision ->> 'rule_id', '')::uuid, nullif(decision ->> 'rule_version', '')::integer,
    missing, now(),
    case when enforcement_on then 'message_trigger' else 'message_trigger_shadow' end,
    jsonb_build_object(
      'governing_body', decision ->> 'governing_body',
      'division', decision ->> 'division',
      'sport', decision ->> 'sport',
      'sport_gender', decision ->> 'sport_gender',
      'context_source', decision ->> 'context_source',
      'next_permitted_at', decision ->> 'next_permitted_at'
    )
  );

  if enforcement_on
     and decision ->> 'status' = 'prohibited'
     and decision ->> 'enforcement' = 'hard_block'
     and decision ->> 'context_source' = 'verified_program' then
    -- The audit row above rolls back with the rejected insert, so also write a
    -- server-log line (survives rollback) for hard-block observability (§32).
    raise log 'RECRUITING_ACTION_PROHIBITED coach=% athlete=% rule=% v% next=%',
      new.sender_user_id, new.athlete_id, decision ->> 'rule_key',
      decision ->> 'rule_version', decision ->> 'next_permitted_at';
    raise exception using
      errcode = 'P0001',
      message = 'RECRUITING_ACTION_PROHIBITED',
      hint = coalesce(decision ->> 'user_message',
                      'This recruiting message can''t be sent yet under the rule currently applicable to this program and athlete.'),
      detail = decision::text;
  end if;

  -- needs_review, permitted, permitted_with_restrictions, or shadow mode: allow.
  new.compliance_status := decision ->> 'status';
  new.compliance_rule_id := nullif(decision ->> 'rule_id', '')::uuid;
  new.compliance_rule_version := nullif(decision ->> 'rule_version', '')::integer;
  new.compliance_evaluated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_enforce_recruiting_rules on public.messages;
create trigger trg_enforce_recruiting_rules
before insert on public.messages
for each row execute function public.enforce_recruiting_rules_on_message();

-- ---------------------------------------------------------------------------
-- 4. Grants
-- ---------------------------------------------------------------------------
revoke all on function public.recruiting_enforce_coach_action(uuid, uuid, text, timestamptz) from public, anon, authenticated;
revoke all on function public.enforce_recruiting_rules_on_message() from public, anon, authenticated;
revoke all on function public.evaluate_my_coach_action(uuid, text) from public, anon;
grant execute on function public.evaluate_my_coach_action(uuid, text) to authenticated;
