-- =============================================================================
-- 019 — Coach messaging: program-scoped sends, durable denial audit, inbox,
--       revoked/blocked read cut-off, message-preview privacy.
--
-- Added 2026-10-01 per docs/COACH-MODE-WORKSPACE-SPEC.md §13 and the four
-- 2.1 confirmations (spec §2.3, Danny 2026-10-01):
--   1. No template system — a pre-window coach send is denied and the client
--      shows the rule, source and opening date.
--   2. needs_review stays "allowed with a warning".
--   3. Every coach send goes through ONE RPC, send_coach_message(), which
--      records a denied attempt BEFORE returning (no raise), so the audit row
--      commits even though no message was written (D29). The 013 trigger
--      remains the final guard for direct inserts.
--   4. Enforcement is switched ON at the 2.1 launch gate, not here.
--
-- Also:
--   • messages.program_id — the coach's representing program (D16). Set by
--     the RPC, validated by the trigger against current verified membership.
--   • evaluate_my_coach_action gains p_program_id so preflight and the final
--     check resolve the same program.
--   • Coaches read/mark threads only while they hold the coach role and are
--     not blocked by the athlete or a guardian (D4/D5, W3).
--   • coach_inbox(p_program_id): threads with allowlisted athlete cards.
--   • coach_block_athlete(): coaches never receive an athlete's user id, so
--     blocking resolves the owner server-side.
--   • user_settings.show_message_previews (default OFF, D10): the message
--     notification body carries text only for recipients who opted in.
--   • notifications.destination jsonb — typed destination (D28); message
--     notifications populate it now, the rest in 2F.
--
-- Requires 013, 016, 017. Re-runnable.
-- =============================================================================

set check_function_bodies = off;

-- ---------------------------------------------------------------------------
-- 1. Schema
-- ---------------------------------------------------------------------------
alter table public.messages
  add column if not exists program_id uuid references public.recruiting_programs (id) on delete set null;
create index if not exists idx_messages_coach_program
  on public.messages (coach_user_id, program_id, created_at desc);

-- Durable record of coach sends refused by a hard-block rule. Written by
-- send_coach_message() in the same transaction that RETURNS the denial, so it
-- commits. Never stores the message body.
create table if not exists public.recruiting_denied_attempts (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid,
  athlete_id uuid,
  program_id uuid,
  action_type text not null,
  decision text not null,
  enforcement_level text not null,
  rule_id uuid,
  rule_key text,
  rule_version integer,
  next_permitted_at timestamptz,
  context_snapshot jsonb,
  attempted_at timestamptz not null default now(),
  source text not null default 'send_rpc'
);
create index if not exists idx_denied_attempts_attempted
  on public.recruiting_denied_attempts (attempted_at desc);
alter table public.recruiting_denied_attempts enable row level security;
drop policy if exists "admins read denied attempts" on public.recruiting_denied_attempts;
create policy "admins read denied attempts" on public.recruiting_denied_attempts
  for select to authenticated using (public.has_role('admin'));

create table if not exists public.user_settings (
  user_id uuid primary key references auth.users (id) on delete cascade,
  show_message_previews boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.user_settings enable row level security;
drop policy if exists "own settings" on public.user_settings;
create policy "own settings" on public.user_settings
  for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop trigger if exists set_updated_at on public.user_settings;
create trigger set_updated_at before update on public.user_settings
  for each row execute function public.set_updated_at();

alter table public.notifications add column if not exists destination jsonb;

-- ---------------------------------------------------------------------------
-- 2. Program-aware resolver. The coach names the program they represent; we
--    verify the membership and evaluate against THAT program. Zero guessing.
-- ---------------------------------------------------------------------------
create or replace function public.recruiting_enforce_coach_action_for_program(
  p_coach_user_id uuid,
  p_athlete_id uuid,
  p_action_type text,
  p_program_id uuid,
  p_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  a record;
  prog record;
  ctx jsonb;
begin
  select grad_year, sport_gender, academic_calendar_type, sophomore_completed_on
    into a
  from athletes where id = p_athlete_id;
  if not found then
    raise exception 'athlete not found';
  end if;

  select p.* into prog
  from coach_program_memberships m
  join recruiting_programs p on p.id = m.program_id
  where m.coach_user_id = p_coach_user_id
    and m.program_id = p_program_id
    and m.status = 'verified'
    and p.active
    and p.verified_at is not null;

  if not found then
    ctx := jsonb_build_object(
      'actor_type', recruiting_actor_for_action(p_action_type),
      'action_type', p_action_type,
      'context_source', 'none'
    );
    return recruiting_decision_json(
      ctx, p_at, 'needs_review',
      'Coach has no verified membership in the named program',
      'We don''t have a verified program and division for this coach yet, so The Hub can''t apply a recruiting rule to this message.',
      null, 'none', array['coach.verified_program'], false, null
    );
  end if;

  if a.sport_gender is not null and prog.sport_gender <> a.sport_gender then
    ctx := jsonb_build_object(
      'actor_type', recruiting_actor_for_action(p_action_type),
      'action_type', p_action_type,
      'context_source', 'verified_program',
      'program_id', prog.id
    );
    return recruiting_decision_json(
      ctx, p_at, 'needs_review',
      'Program gender does not match the athlete',
      'This program recruits a different sport/gender than this athlete''s profile, so no recruiting rule can be applied.',
      null, 'none', array['program.sport_gender.mismatch'], false, null
    );
  end if;

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
  return recruiting_evaluate_core(ctx, p_at) || jsonb_build_object('program_id', prog.id);
end;
$$;

-- Preflight (spec §13 / rules spec §18). With a program id it resolves the
-- same way send_coach_message() and the trigger do.
drop function if exists public.evaluate_my_coach_action(uuid, text);
create or replace function public.evaluate_my_coach_action(
  p_athlete_id uuid,
  p_action_type text default 'coach_send_recruiting_electronic_correspondence',
  p_program_id uuid default null
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
  if not (has_role('coach') and athlete_is_published(p_athlete_id) and not coach_is_blocked(p_athlete_id)) then
    raise exception 'not authorized';
  end if;
  if recruiting_actor_for_action(p_action_type) is distinct from 'coach' then
    raise exception 'not a coach action';
  end if;
  if p_program_id is not null then
    perform coach_assert_program(p_program_id);
    return recruiting_enforce_coach_action_for_program(auth.uid(), p_athlete_id, p_action_type, p_program_id, now());
  end if;
  return recruiting_enforce_coach_action(auth.uid(), p_athlete_id, p_action_type, now());
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. The trigger honors messages.program_id (validated), else falls back to
--    the 013 resolution. Otherwise unchanged from 013.
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
  new.compliance_status := null;
  new.compliance_rule_id := null;
  new.compliance_rule_version := null;
  new.compliance_evaluated_at := null;

  -- Athlete/guardian outreach is not restricted by coach-initiated rules.
  if new.sender_user_id is distinct from new.coach_user_id then
    new.program_id := null;   -- only coach sends carry a representing program
    return new;
  end if;

  if new.program_id is not null then
    if not exists (
      select 1 from coach_program_memberships m
      join recruiting_programs p on p.id = m.program_id
      where m.coach_user_id = new.sender_user_id and m.program_id = new.program_id
        and m.status = 'verified' and p.active and p.verified_at is not null
    ) then
      raise exception 'not authorized for this program';
    end if;
    decision := recruiting_enforce_coach_action_for_program(new.sender_user_id, new.athlete_id, action, new.program_id, now());
  else
    decision := recruiting_enforce_coach_action(new.sender_user_id, new.athlete_id, action, now());
  end if;

  select coalesce(bool_value, false) into enforcement_on
  from app_settings where key = 'recruiting_rules_enforcement_enabled';
  enforcement_on := coalesce(enforcement_on, false);

  missing := array(select jsonb_array_elements_text(coalesce(decision -> 'missing_context', '[]'::jsonb)));

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

  new.compliance_status := decision ->> 'status';
  new.compliance_rule_id := nullif(decision ->> 'rule_id', '')::uuid;
  new.compliance_rule_version := nullif(decision ->> 'rule_version', '')::integer;
  new.compliance_evaluated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. send_coach_message — the one supported coach send path (D29).
-- ---------------------------------------------------------------------------
create or replace function public.send_coach_message(
  p_program_id uuid,
  p_athlete_id uuid,
  p_body text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  action constant text := 'coach_send_recruiting_electronic_correspondence';
  prog public.recruiting_programs%rowtype;
  a public.athletes%rowtype;
  body text := btrim(coalesce(p_body, ''));
  decision jsonb;
  enforcement_on boolean;
  m public.messages%rowtype;
begin
  perform coach_assert_program(p_program_id);
  select * into prog from recruiting_programs where id = p_program_id;
  select * into a from athletes where id = p_athlete_id and is_published and sport_gender = prog.sport_gender;
  if not found or coach_is_blocked(p_athlete_id) then
    raise exception 'not found';
  end if;
  if body = '' then raise exception 'message is empty'; end if;
  if char_length(body) > 4000 then raise exception 'message is too long (4000 characters max)'; end if;

  decision := recruiting_enforce_coach_action_for_program(auth.uid(), p_athlete_id, action, p_program_id, now());
  select coalesce(bool_value, false) into enforcement_on
  from app_settings where key = 'recruiting_rules_enforcement_enabled';
  enforcement_on := coalesce(enforcement_on, false);

  if enforcement_on
     and decision ->> 'status' = 'prohibited'
     and decision ->> 'enforcement' = 'hard_block'
     and decision ->> 'context_source' = 'verified_program' then
    -- Durable: this row commits because we RETURN rather than RAISE.
    insert into recruiting_denied_attempts (
      actor_user_id, athlete_id, program_id, action_type, decision, enforcement_level,
      rule_id, rule_key, rule_version, next_permitted_at, context_snapshot, source
    ) values (
      auth.uid(), p_athlete_id, p_program_id, action, 'prohibited', 'hard_block',
      nullif(decision ->> 'rule_id', '')::uuid, decision ->> 'rule_key',
      nullif(decision ->> 'rule_version', '')::integer,
      nullif(decision ->> 'next_permitted_at', '')::timestamptz,
      jsonb_build_object(
        'governing_body', decision ->> 'governing_body', 'division', decision ->> 'division',
        'sport', decision ->> 'sport', 'sport_gender', decision ->> 'sport_gender',
        'athlete_grad_year', a.grad_year),
      'send_rpc'
    );
    return jsonb_build_object('status', 'denied', 'decision', decision);
  end if;

  -- Allowed (or shadow mode): the trigger re-evaluates with the same program,
  -- stamps compliance_*, and remains the final guard.
  insert into messages (athlete_id, coach_user_id, sender_user_id, body, program_id)
  values (p_athlete_id, auth.uid(), auth.uid(), body, p_program_id)
  returning * into m;

  return jsonb_build_object(
    'status', 'sent',
    'decision', decision,
    'message', jsonb_build_object(
      'id', m.id, 'athlete_id', m.athlete_id, 'coach_user_id', m.coach_user_id,
      'sender_user_id', m.sender_user_id, 'body', m.body, 'read_at', m.read_at,
      'created_at', m.created_at, 'program_id', m.program_id,
      'compliance_status', m.compliance_status)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Inbox and block helper
-- ---------------------------------------------------------------------------
create or replace function public.coach_inbox(p_program_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  prog public.recruiting_programs%rowtype;
begin
  perform coach_assert_program(p_program_id);
  select * into prog from recruiting_programs where id = p_program_id;
  return coalesce((
    select jsonb_agg(t order by t -> 'last_message' ->> 'created_at' desc)
    from (
      select jsonb_build_object(
        'athlete', coach_athlete_card_json(a, null),
        'last_message', (
          select jsonb_build_object('id', lm.id, 'body', lm.body, 'sender_user_id', lm.sender_user_id,
                                    'created_at', lm.created_at, 'compliance_status', lm.compliance_status)
          from messages lm
          where lm.athlete_id = a.id and lm.coach_user_id = auth.uid()
          order by lm.created_at desc limit 1),
        'unread_count', (
          select count(*) from messages um
          where um.athlete_id = a.id and um.coach_user_id = auth.uid()
            and um.sender_user_id <> auth.uid() and um.read_at is null),
        'board_stage', (
          select e.stage from program_board_entries e
          where e.program_id = p_program_id and e.athlete_id = a.id and e.removed_at is null)
      ) as t
      from athletes a
      where a.is_published
        and a.sport_gender = prog.sport_gender
        and not coach_is_blocked(a.id)
        and exists (select 1 from messages x where x.athlete_id = a.id and x.coach_user_id = auth.uid())
    ) threads
  ), '[]'::jsonb);
end;
$$;

-- Coaches never see an athlete's user id; blocking resolves it here.
create or replace function public.coach_block_athlete(p_athlete_id uuid, p_blocked boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid;
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if not has_role('coach') then raise exception 'not authorized'; end if;
  select user_id into owner from athletes where id = p_athlete_id;
  if owner is null then raise exception 'not found'; end if;
  if p_blocked then
    insert into user_blocks (blocker_user_id, blocked_user_id) values (auth.uid(), owner)
    on conflict (blocker_user_id, blocked_user_id) do nothing;
  else
    delete from user_blocks where blocker_user_id = auth.uid() and blocked_user_id = owner;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. RLS: coach reads require the role and no block (D4/D5/W3); coach inserts
--    must name a program they hold (direct inserts are still allowed only so
--    the trigger remains the final guard; the app uses send_coach_message).
-- ---------------------------------------------------------------------------
drop policy if exists "messages select" on public.messages;
create policy "messages select" on public.messages
  for select to authenticated
  using (
    (coach_user_id = auth.uid() and public.has_role('coach') and not public.coach_is_blocked(athlete_id))
    or public.can_manage_athlete(athlete_id)
  );

drop policy if exists "messages update" on public.messages;
create policy "messages update" on public.messages
  for update to authenticated
  using (
    (coach_user_id = auth.uid() and public.has_role('coach') and not public.coach_is_blocked(athlete_id))
    or public.can_manage_athlete(athlete_id)
  )
  with check (
    (coach_user_id = auth.uid() and public.has_role('coach') and not public.coach_is_blocked(athlete_id))
    or public.can_manage_athlete(athlete_id)
  );

drop policy if exists "messages insert" on public.messages;
create policy "messages insert" on public.messages
  for insert to authenticated
  with check (
    sender_user_id = auth.uid()
    and (
      (coach_user_id = auth.uid()
        and public.has_role('coach')
        and public.athlete_is_published(athlete_id)
        and not public.coach_is_blocked(athlete_id)
        and (program_id is null or public.coach_has_program(program_id)))
      or (public.can_manage_athlete(athlete_id) and public.is_active_coach(coach_user_id) and program_id is null)
    )
  );

-- ---------------------------------------------------------------------------
-- 7. Message notifications: previews only for recipients who opted in (D10);
--    typed destination (D28).
-- ---------------------------------------------------------------------------
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
  dest jsonb := jsonb_build_object('type', 'thread', 'athlete_id', new.athlete_id, 'coach_user_id', new.coach_user_id);
begin
  select a.user_id, a.full_name into athlete_owner, athlete_name from public.athletes a where a.id = new.athlete_id;
  sender_name := public.coach_display_name(new.sender_user_id);

  if new.sender_user_id = new.coach_user_id then
    if athlete_owner is not null then
      insert into public.notifications (user_id, type, title, body, link, destination)
      values (athlete_owner, 'message', 'New message from a college coach',
              public.message_preview_for(athlete_owner, sender_name, new.body), '/messages', dest);
    end if;
    for g in select user_id from public.athlete_guardians where athlete_id = new.athlete_id and user_id <> athlete_owner loop
      insert into public.notifications (user_id, type, title, body, link, destination)
      values (g.user_id, 'message', 'New message from a college coach',
              public.message_preview_for(g.user_id, sender_name, new.body), '/messages', dest);
    end loop;
  else
    insert into public.notifications (user_id, type, title, body, link, destination)
    values (new.coach_user_id, 'message', 'New message from an athlete',
            public.message_preview_for(new.coach_user_id, coalesce(athlete_name, 'An athlete'), new.body), '/coaches/messages', dest);
  end if;
  return new;
end;
$$;

create or replace function public.message_preview_for(p_recipient uuid, p_sender_label text, p_body text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when coalesce((select s.show_message_previews from public.user_settings s where s.user_id = p_recipient), false)
      then coalesce(p_sender_label, 'Someone') || ': ' || left(p_body, 120)
    else coalesce(p_sender_label, 'Someone') || ' sent you a message. Open Messages to read it.'
  end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Grants
-- ---------------------------------------------------------------------------
revoke all on function public.recruiting_enforce_coach_action_for_program(uuid, uuid, text, uuid, timestamptz) from public, anon, authenticated;
revoke all on function public.evaluate_my_coach_action(uuid, text, uuid) from public, anon;
grant execute on function public.evaluate_my_coach_action(uuid, text, uuid) to authenticated;
revoke all on function public.send_coach_message(uuid, uuid, text) from public, anon;
grant execute on function public.send_coach_message(uuid, uuid, text) to authenticated;
revoke all on function public.coach_inbox(uuid) from public, anon;
grant execute on function public.coach_inbox(uuid) to authenticated;
revoke all on function public.coach_block_athlete(uuid, boolean) from public, anon;
grant execute on function public.coach_block_athlete(uuid, boolean) to authenticated;
revoke all on function public.message_preview_for(uuid, text, text) from public, anon, authenticated;
