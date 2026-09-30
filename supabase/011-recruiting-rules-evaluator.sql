-- =============================================================================
-- 011 — Recruiting Rules Engine: deterministic evaluator.
--
-- The ONLY place recruiting rules are interpreted. iOS, web, and the
-- messages trigger (013) all call into here; clients deserialize the result
-- and never reimplement it. No AI, no heuristics: a rule either matches the
-- context or the answer is needs_review.
--
-- Layers:
--   recruiting_evaluate_core(ctx, at)     pure: reads recruiting_rules only,
--                                          every athlete/program fact comes in
--                                          via ctx. Unit-testable without
--                                          fixture users.
--   evaluate_recruiting_action(...)        RPC for signed-in clients: resolves
--                                          athlete + program facts from tables
--                                          (never trusts client-supplied
--                                          division for anything but display)
--                                          and calls the core.
--   recruiting_rules_validate()            operational lint for the rule set.
--
-- Precedence (spec §12): exception_priority desc, then specificity
-- (division, sport, sport_gender, has-conditions) desc. Ties → needs_review.
-- Re-runnable.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. Helpers
-- ---------------------------------------------------------------------------

-- Actor is derived from the action taxonomy (spec §5), never from the client.
create or replace function public.recruiting_actor_for_action(p_action text)
returns text
language sql
immutable
as $$
  select case
    when p_action like 'coach\_%' then 'coach'
    when p_action like 'athlete\_%' then 'athlete'
    when p_action like 'institution\_%' then 'institution'
    else null
  end;
$$;

-- Matches a rule's `conditions` against the context, key by key.
-- Returns {"result": "match" | "no_match" | "unknown", "unknown_keys": [...]}.
-- A context value that is NULL is "unknown" (we cannot tell whether the rule
-- applies); a present value that differs is "no_match".
create or replace function public.recruiting_conditions_match(p_conditions jsonb, p_ctx jsonb)
returns jsonb
language plpgsql
immutable
as $$
declare
  k text;
  v jsonb;
  cv text;
  unknown_keys text[] := '{}';
  any_no_match boolean := false;
begin
  for k, v in select * from jsonb_each(coalesce(p_conditions, '{}'::jsonb)) loop
    cv := nullif(p_ctx ->> k, '');
    if cv is null then
      unknown_keys := unknown_keys || k;
    elsif jsonb_typeof(v) = 'array' then
      if not (v ? cv) then any_no_match := true; end if;
    elsif (v #>> '{}') is distinct from cv then
      any_no_match := true;
    end if;
  end loop;

  if any_no_match then
    return jsonb_build_object('result', 'no_match', 'unknown_keys', '[]'::jsonb);
  elsif cardinality(unknown_keys) > 0 then
    return jsonb_build_object('result', 'unknown', 'unknown_keys', to_jsonb(unknown_keys));
  end if;
  return jsonb_build_object('result', 'match', 'unknown_keys', '[]'::jsonb);
end;
$$;

-- Computes when a timed rule's restricted window starts, or NULL when the
-- athlete fact the rule depends on is missing.
create or replace function public.recruiting_rule_start_at(p_rule public.recruiting_rules, p_ctx jsonb)
returns timestamptz
language plpgsql
immutable
as $$
declare
  grad integer;
  soph date;
  d date;
  h integer := extract(hour from p_rule.start_time)::integer;
  m integer := extract(minute from p_rule.start_time)::integer;
begin
  case p_rule.academic_milestone_type
    when 'grad_year_offset' then
      grad := nullif(p_ctx ->> 'athlete_grad_year', '')::integer;
      if grad is null then return null; end if;
      return make_timestamptz(
        grad + p_rule.start_year_offset_from_grad, p_rule.start_month, p_rule.start_day,
        h, m, 0, p_rule.start_time_zone
      );
    when 'sophomore_completed_offset' then
      soph := nullif(p_ctx ->> 'athlete_sophomore_completed_on', '')::date;
      if soph is null then return null; end if;
      d := soph + p_rule.start_day_offset;
      return make_timestamptz(
        extract(year from d)::integer, extract(month from d)::integer, extract(day from d)::integer,
        h, m, 0, p_rule.start_time_zone
      );
    when 'absolute' then
      return p_rule.absolute_start_at;
    else
      return null;
  end case;
end;
$$;

create or replace function public.recruiting_iso(p_at timestamptz)
returns text
language sql
immutable
as $$
  select case when p_at is null then null
              else to_char(p_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') end;
$$;

-- Builds the decision document. Rule/source attribution is attached when
-- p_rule_id is given, including for needs_review results so the UI can show
-- the closest authoritative source (spec §1.4).
create or replace function public.recruiting_decision_json(
  p_ctx jsonb,
  p_at timestamptz,
  p_status text,
  p_reason text,
  p_user_message text,
  p_next timestamptz,
  p_enforcement text,
  p_missing text[],
  p_conflict boolean,
  p_rule_id uuid
)
returns jsonb
language sql
stable
set search_path = public
as $$
  select jsonb_build_object(
    'status', p_status,
    'action', p_ctx ->> 'action_type',
    'actor', p_ctx ->> 'actor_type',
    'reason', p_reason,
    'user_message', p_user_message,
    'next_permitted_at', recruiting_iso(p_next),
    -- Calendar date in the rule's own time zone, so clients in other zones
    -- show "June 15", not "June 14 9 PM".
    'next_permitted_on', case when p_next is null then null
                              else to_char(p_next at time zone coalesce(r.start_time_zone, 'UTC'), 'YYYY-MM-DD') end,
    'rule_time_zone', r.start_time_zone,
    'enforcement', p_enforcement,
    'missing_context', to_jsonb(coalesce(p_missing, '{}'::text[])),
    'conflict', coalesce(p_conflict, false),
    'governing_body', p_ctx ->> 'governing_body',
    'division', p_ctx ->> 'division',
    'sport', p_ctx ->> 'sport',
    'sport_gender', p_ctx ->> 'sport_gender',
    'context_source', coalesce(p_ctx ->> 'context_source', 'none'),
    'evaluated_at', recruiting_iso(p_at),
    'rule_id', r.id,
    'rule_key', r.rule_key,
    'rule_version', r.rule_version,
    'source_title', s.title,
    'source_url', s.source_url,
    'source_reference', s.source_reference,
    'effective_from', r.effective_from,
    'effective_until', r.effective_until,
    'last_verified_at', recruiting_iso(r.last_verified_at)
  )
  from (select 1) x
  left join recruiting_rules r on r.id = p_rule_id
  left join recruiting_rule_sources s on s.id = r.source_id;
$$;

-- ---------------------------------------------------------------------------
-- 2. Core evaluator (pure over ctx + recruiting_rules)
--
-- ctx keys: governing_body, division, sport, sport_gender, actor_type,
--   action_type, athlete_grad_year, athlete_academic_calendar_type,
--   athlete_sophomore_completed_on, context_source, program_id
-- ---------------------------------------------------------------------------
create or replace function public.recruiting_evaluate_core(p_ctx jsonb, p_at timestamptz)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_gb text := nullif(p_ctx ->> 'governing_body', '');
  v_div text := nullif(p_ctx ->> 'division', '');
  v_sport text := nullif(p_ctx ->> 'sport', '');
  v_gender text := nullif(p_ctx ->> 'sport_gender', '');
  v_actor text := nullif(p_ctx ->> 'actor_type', '');
  v_action text := nullif(p_ctx ->> 'action_type', '');
  missing text[] := '{}';
  unknown_msg constant text :=
    'We don''t have enough verified information to determine this recruiting action. The Hub won''t guess.';

  r record;
  m jsonb;
  candidates integer := 0;
  found_best boolean := false;
  best_id uuid;
  best_prio integer;
  best_spec integer;
  tier_count integer := 0;
  skipped_keys text[] := '{}';

  rule public.recruiting_rules%rowtype;
  start_at timestamptz;
  in_window boolean;
  v_status text;
  v_summary text;
  v_next timestamptz;
  v_enf text;
begin
  -- 2a. Required context. Division is required only where the governing body
  --     has divisions (NCAA); NAIA/NJCAA rules are keyed on governing body.
  if v_actor is null then missing := missing || 'actor_type'::text; end if;
  if v_action is null then missing := missing || 'action_type'::text; end if;
  if v_gb is null then missing := missing || 'program.governing_body'::text; end if;
  if v_gb = 'NCAA' and v_div is null then missing := missing || 'program.division'::text; end if;
  if v_sport is null then missing := missing || 'program.sport'::text; end if;
  if v_gender is null then missing := missing || 'athlete.sport_gender'::text; end if;

  if cardinality(missing) > 0 then
    return recruiting_decision_json(
      p_ctx, p_at, 'needs_review',
      'Required context is missing: ' || array_to_string(missing, ', '),
      unknown_msg, null, 'none', missing, false, null
    );
  end if;

  -- 2b. Walk published, effective candidates from most to least specific.
  for r in
    select rr.id, rr.rule_key, rr.conditions, rr.exception_priority,
           (rr.division is not null)::integer
           + (rr.sport is not null)::integer
           + (rr.sport_gender is not null)::integer
           + (rr.conditions <> '{}'::jsonb)::integer as specificity
    from recruiting_rules rr
    where rr.status = 'published'
      and rr.governing_body = v_gb
      and (rr.division is null or rr.division = v_div)
      and (rr.sport is null or rr.sport = v_sport)
      and (rr.sport_gender is null or rr.sport_gender = v_gender)
      and rr.actor_type = v_actor
      and rr.action_type = v_action
      and rr.effective_from <= (p_at at time zone rr.start_time_zone)::date
      and (rr.effective_until is null
           or rr.effective_until >= (p_at at time zone rr.start_time_zone)::date)
    order by rr.exception_priority desc, specificity desc, rr.rule_key
  loop
    candidates := candidates + 1;

    -- A more specific rule already matched; everything below it is ignored.
    if found_best and (r.exception_priority, r.specificity) < (best_prio, best_spec) then
      exit;
    end if;

    m := recruiting_conditions_match(r.conditions, p_ctx);

    if m ->> 'result' = 'no_match' then
      skipped_keys := skipped_keys || array(select jsonb_object_keys(r.conditions));
      continue;
    end if;

    if m ->> 'result' = 'unknown' then
      -- We cannot tell whether this rule applies; never guess.
      missing := array(select jsonb_array_elements_text(m -> 'unknown_keys'));
      return recruiting_decision_json(
        p_ctx, p_at, 'needs_review',
        'Cannot determine whether rule ' || r.rule_key || ' applies; missing '
          || array_to_string(missing, ', '),
        unknown_msg, null, 'none', missing, false, r.id
      );
    end if;

    -- match
    if not found_best then
      found_best := true;
      best_id := r.id;
      best_prio := r.exception_priority;
      best_spec := r.specificity;
      tier_count := 1;
    else
      -- Same tier as the chosen rule (a lower tier would have exited above).
      tier_count := tier_count + 1;
    end if;
  end loop;

  if not found_best then
    if candidates = 0 then
      return recruiting_decision_json(
        p_ctx, p_at, 'needs_review',
        'No published rule covers ' || v_gb || coalesce(' ' || v_div, '') || ' ' || v_sport
          || ' ' || v_gender || ' / ' || v_actor || ' / ' || v_action,
        unknown_msg, null, 'none', array['rule'], false, null
      );
    end if;
    missing := array(select distinct k from unnest(skipped_keys) k);
    return recruiting_decision_json(
      p_ctx, p_at, 'needs_review',
      'No published rule matches the athlete context (' || array_to_string(missing, ', ') || ')',
      unknown_msg, null, 'none', missing, false, null
    );
  end if;

  if tier_count > 1 then
    -- Configuration defect: equally specific published rules. Do not pick one.
    return recruiting_decision_json(
      p_ctx, p_at, 'needs_review',
      'Configuration defect: ' || tier_count || ' equally specific published rules match',
      unknown_msg, null, 'none', array['rule.conflict'], true, best_id
    );
  end if;

  select * into rule from recruiting_rules where id = best_id;

  -- 2c. Apply the rule's timing.
  if rule.academic_milestone_type is null then
    v_status := rule.decision;
    v_summary := rule.plain_english_summary;
    v_next := null;
  else
    start_at := recruiting_rule_start_at(rule, p_ctx);
    if start_at is null then
      missing := array[case rule.academic_milestone_type
                         when 'grad_year_offset' then 'athlete.grad_year'
                         when 'sophomore_completed_offset' then 'athlete.sophomore_completed_on'
                         else 'rule.absolute_start_at' end];
      return recruiting_decision_json(
        p_ctx, p_at, 'needs_review',
        'Rule ' || rule.rule_key || ' requires ' || missing[1],
        unknown_msg, null, 'none', missing, false, rule.id
      );
    end if;

    if rule.academic_milestone_type = 'absolute' then
      -- Period rule: the decision applies inside [start, end).
      in_window := p_at >= start_at
                   and (rule.absolute_end_at is null or p_at < rule.absolute_end_at);
      v_next := case when in_window then rule.absolute_end_at else null end;
    else
      -- Milestone rule: the decision applies before the start.
      in_window := p_at < start_at;
      v_next := case when in_window then start_at else null end;
    end if;

    if in_window then
      v_status := rule.decision;
      v_summary := rule.plain_english_summary;
    else
      v_status := rule.decision_after_start;
      v_summary := coalesce(rule.plain_english_summary_after, rule.plain_english_summary);
    end if;
  end if;

  v_enf := case
    when v_status = 'permitted' then 'none'
    when v_status = rule.decision then rule.enforcement_level
    else 'informational'
  end;

  return recruiting_decision_json(
    p_ctx, p_at, v_status,
    'Rule ' || rule.rule_key || ' v' || rule.rule_version,
    v_summary, v_next, v_enf, '{}'::text[], false, rule.id
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. RPC for signed-in clients (informational surfaces).
--
-- Trusted facts (athlete grad year, gender, calendar; program governing body
-- and division) are read from tables. p_governing_body/p_division are
-- accepted ONLY when no program is given, and the result is labeled
-- context_source = 'client_supplied' so nothing downstream treats it as
-- verified. Enforcement (013) never uses this path.
-- ---------------------------------------------------------------------------
create or replace function public.evaluate_recruiting_action(
  p_athlete_id uuid,
  p_action_type text,
  p_program_id uuid default null,
  p_governing_body text default null,
  p_division text default null,
  p_evaluation_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
  p record;
  ctx jsonb;
  at_time timestamptz := coalesce(p_evaluation_at, now());
  result jsonb;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if not (
    can_manage_athlete(p_athlete_id)
    or has_role('admin')
    or (has_role('coach') and athlete_is_published(p_athlete_id))
  ) then
    raise exception 'not authorized';
  end if;

  select grad_year, sport_gender, academic_calendar_type, sophomore_completed_on
    into a
  from athletes where id = p_athlete_id;
  if not found then
    raise exception 'athlete not found';
  end if;

  if p_program_id is not null then
    select * into p from recruiting_programs where id = p_program_id and active;
    if not found then
      raise exception 'program not found';
    end if;
    ctx := jsonb_build_object(
      'governing_body', p.governing_body,
      'division', p.division,
      'sport', p.sport,
      'sport_gender', p.sport_gender,
      'program_id', p.id,
      'context_source', case when p.verified_at is not null then 'verified_program'
                             else 'unverified_program' end
    );
  else
    -- The Hub is basketball-only today; the rules/programs tables carry sport
    -- so other sports can be added without touching this function's shape.
    ctx := jsonb_build_object(
      'governing_body', p_governing_body,
      'division', p_division,
      'sport', 'basketball',
      'sport_gender', a.sport_gender,
      'context_source', case when p_governing_body is null then 'none' else 'client_supplied' end
    );
  end if;

  ctx := ctx || jsonb_build_object(
    'actor_type', recruiting_actor_for_action(p_action_type),
    'action_type', p_action_type,
    'athlete_grad_year', a.grad_year,
    'athlete_academic_calendar_type', a.academic_calendar_type,
    'athlete_sophomore_completed_on', a.sophomore_completed_on
  );

  result := recruiting_evaluate_core(ctx, at_time);

  -- Conflicting rules are a configuration defect worth an audit row.
  if coalesce((result ->> 'conflict')::boolean, false) then
    insert into recruiting_compliance_decisions (
      actor_user_id, athlete_id, program_id, action_type, decision, enforcement_level,
      missing_context, evaluated_at, evaluation_source, context_snapshot
    ) values (
      auth.uid(), p_athlete_id, p_program_id, p_action_type, 'needs_review', 'none',
      array['rule.conflict'], at_time, 'rpc_conflict',
      ctx - 'athlete_sophomore_completed_on' - 'program_id'
    );
  end if;

  return result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Rule-set validation (operations lint; see docs/RECRUITING-RULE-MAINTENANCE.md)
-- ---------------------------------------------------------------------------
create or replace function public.recruiting_rules_validate(p_stale_after_days integer default 180)
returns table (severity text, rule_key text, rule_id uuid, issue text)
language plpgsql
stable
set search_path = public
as $$
declare
  r record;
begin
  -- Published rule whose source lacks a usable URL or retrieval timestamp.
  return query
    select 'error', rr.rule_key, rr.id, 'source has no https URL'
    from recruiting_rules rr join recruiting_rule_sources s on s.id = rr.source_id
    where rr.status = 'published' and s.source_url not like 'https://%';

  -- Hard-block rules must cite a source reference (bylaw/section).
  return query
    select 'error', rr.rule_key, rr.id, 'hard_block rule without source_reference'
    from recruiting_rules rr join recruiting_rule_sources s on s.id = rr.source_id
    where rr.status = 'published' and rr.enforcement_level = 'hard_block'
      and coalesce(s.source_reference, '') = '';

  -- Verification timestamps.
  return query
    select 'error', rr.rule_key, rr.id, 'last_verified_at is in the future'
    from recruiting_rules rr
    where rr.status = 'published' and rr.last_verified_at > now();

  return query
    select 'warning', rr.rule_key, rr.id,
           'last verified ' || (now()::date - rr.last_verified_at::date) || ' days ago (> '
             || p_stale_after_days || ')'
    from recruiting_rules rr
    where rr.status = 'published'
      and rr.last_verified_at < now() - make_interval(days => p_stale_after_days);

  -- Impossible calendar dates (e.g. June 31).
  for r in
    select rr.rule_key, rr.id, rr.start_month, rr.start_day
    from recruiting_rules rr
    where rr.status <> 'retired' and rr.academic_milestone_type = 'grad_year_offset'
  loop
    begin
      perform make_date(2001, r.start_month, r.start_day);
    exception when others then
      severity := 'error'; rule_key := r.rule_key; rule_id := r.id;
      issue := 'impossible start date ' || r.start_month || '/' || r.start_day;
      return next;
    end;
  end loop;

  -- Duplicate live versions (belt-and-braces: the unique index prevents this).
  return query
    select 'error', rr.rule_key, null::uuid, count(*) || ' published versions'
    from recruiting_rules rr
    where rr.status = 'published'
    group by rr.rule_key having count(*) > 1;

  -- Equally specific published rules for the same scope and conditions: the
  -- evaluator would return needs_review for every athlete they cover.
  return query
    select 'error', a.rule_key, a.id,
           'conflicts with ' || b.rule_key || ' (same scope, priority, specificity and conditions)'
    from recruiting_rules a
    join recruiting_rules b
      on a.id <> b.id
     and a.status = 'published' and b.status = 'published'
     and a.governing_body = b.governing_body
     and a.division is not distinct from b.division
     and a.sport is not distinct from b.sport
     and a.sport_gender is not distinct from b.sport_gender
     and a.actor_type = b.actor_type
     and a.action_type = b.action_type
     and a.exception_priority = b.exception_priority
     and a.conditions = b.conditions
     and (a.effective_until is null or b.effective_from <= a.effective_until)
     and (b.effective_until is null or a.effective_from <= b.effective_until);

  -- Draft rules whose key already has a published version: fine, but worth a note.
  return query
    select 'info', d.rule_key, d.id, 'draft pending; published v' || p.rule_version || ' is live'
    from recruiting_rules d join recruiting_rules p
      on p.rule_key = d.rule_key and p.status = 'published'
    where d.status = 'draft';

  return;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Grants. Only the RPC is callable by clients; everything else is internal.
-- ---------------------------------------------------------------------------
revoke all on function public.recruiting_actor_for_action(text) from public, anon, authenticated;
revoke all on function public.recruiting_conditions_match(jsonb, jsonb) from public, anon, authenticated;
revoke all on function public.recruiting_rule_start_at(public.recruiting_rules, jsonb) from public, anon, authenticated;
revoke all on function public.recruiting_iso(timestamptz) from public, anon, authenticated;
revoke all on function public.recruiting_decision_json(jsonb, timestamptz, text, text, text, timestamptz, text, text[], boolean, uuid) from public, anon, authenticated;
revoke all on function public.recruiting_evaluate_core(jsonb, timestamptz) from public, anon, authenticated;
revoke all on function public.recruiting_rules_validate(integer) from public, anon, authenticated;
revoke all on function public.evaluate_recruiting_action(uuid, text, uuid, text, text, timestamptz) from public, anon;
grant execute on function public.evaluate_recruiting_action(uuid, text, uuid, text, text, timestamptz) to authenticated;
