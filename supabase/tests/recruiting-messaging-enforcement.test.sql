-- =============================================================================
-- Recruiting Rules Engine — messaging enforcement tests (spec §29.2).
--
-- Run:   scripts/db-query.sh < supabase/tests/recruiting-messaging-enforcement.test.sql
-- Pass:  the final row reads "ALL RECRUITING MESSAGING TESTS PASSED".
--
-- Creates throwaway auth users (@recruiting-test.invalid), a verified TEST
-- program + membership, flips the enforcement flag, and removes everything
-- at the end. The whole DO block is one statement, so a failed assert rolls
-- back every fixture AND the flag change. Runs as the migration role, so
-- RLS does not apply here — triggers do. RLS itself is unchanged by 013.
-- =============================================================================

do $$
declare
  coach_id uuid := gen_random_uuid();
  coach_nomembership_id uuid := gen_random_uuid();
  athlete_user_2029 uuid := gen_random_uuid();   -- sophomore-ish: window opens 2027-06-15
  athlete_user_2027 uuid := gen_random_uuid();   -- window opened 2025-06-15
  athlete_2029 uuid;
  athlete_2027 uuid;
  program_id uuid;
  flag_before boolean;
  msg_id uuid;
  n integer;
  err_msg text;
  err_hint text;
  err_detail text;
  got_status text;
begin
  -- Fixtures ------------------------------------------------------------------
  select bool_value into flag_before from public.app_settings where key = 'recruiting_rules_enforcement_enabled';

  insert into auth.users (id, email, raw_user_meta_data, aud, role)
  values
    (coach_id, 'coach-' || coach_id || '@recruiting-test.invalid',
     '{"signup_role": "coach", "full_name": "Test Coach"}'::jsonb, 'authenticated', 'authenticated'),
    (coach_nomembership_id, 'coach2-' || coach_nomembership_id || '@recruiting-test.invalid',
     '{"signup_role": "coach", "full_name": "Unverified Coach"}'::jsonb, 'authenticated', 'authenticated'),
    (athlete_user_2029, 'ath29-' || athlete_user_2029 || '@recruiting-test.invalid',
     '{"signup_role": "athlete", "full_name": "Test Athlete 2029", "date_of_birth": "2009-01-01"}'::jsonb, 'authenticated', 'authenticated'),
    (athlete_user_2027, 'ath27-' || athlete_user_2027 || '@recruiting-test.invalid',
     '{"signup_role": "athlete", "full_name": "Test Athlete 2027", "date_of_birth": "2007-01-01"}'::jsonb, 'authenticated', 'authenticated');

  insert into public.user_roles (user_id, role) values (coach_id, 'coach'), (coach_nomembership_id, 'coach')
  on conflict do nothing;

  -- handle_new_user created the athlete rows; set the recruiting facts.
  update public.athletes set grad_year = 2029, sport_gender = 'mens', academic_calendar_type = 'traditional_us'
  where user_id = athlete_user_2029 returning id into athlete_2029;
  update public.athletes set grad_year = 2027, sport_gender = 'mens', academic_calendar_type = 'traditional_us'
  where user_id = athlete_user_2027 returning id into athlete_2027;
  assert athlete_2029 is not null and athlete_2027 is not null, 'fixture athletes missing';

  insert into public.recruiting_programs
    (institution_name, normalized_institution_name, governing_body, division, sport, sport_gender, verified_at, source_url)
  values ('Recruiting Test University', 'recruiting test university ' || coach_id, 'NCAA', 'D1', 'basketball', 'mens', now(), 'https://example.test')
  returning id into program_id;

  insert into public.coach_program_memberships (coach_user_id, program_id, status, verified_at)
  values (coach_id, program_id, 'verified', now());

  update public.app_settings set bool_value = true where key = 'recruiting_rules_enforcement_enabled';

  -- 1. Coach → 2029 athlete before June 15 2027: REJECTED, no row, no notification --
  err_msg := null;
  begin
    insert into public.messages (athlete_id, coach_user_id, sender_user_id, body)
    values (athlete_2029, coach_id, coach_id, 'TEST BODY MUST NOT BE LOGGED');
  exception when others then
    get stacked diagnostics err_msg = message_text, err_hint = pg_exception_hint, err_detail = pg_exception_detail;
  end;
  assert err_msg = 'RECRUITING_ACTION_PROHIBITED', '1 expected stable error, got: ' || coalesce(err_msg, '<none>');
  assert err_hint like '%June 15%', '1 hint should be user-facing: ' || coalesce(err_hint, '<none>');
  assert (err_detail::jsonb ->> 'status') = 'prohibited', '1 detail should carry the decision';
  assert (err_detail::jsonb ->> 'next_permitted_at') = '2027-06-15T04:00:00Z', '1 next date: ' || (err_detail::jsonb ->> 'next_permitted_at');
  select count(*) into n from public.messages where athlete_id = athlete_2029;
  assert n = 0, '1 no message row expected, found ' || n;
  select count(*) into n from public.notifications where user_id = athlete_user_2029 and type = 'message';
  assert n = 0, '1 no notification expected, found ' || n;
  -- The failed insert's audit row rolled back with the statement (same
  -- transaction), which is expected: the rejection itself is the record.

  -- 2. Coach → 2027 athlete (window open): allowed, stamped, notification created --
  insert into public.messages (athlete_id, coach_user_id, sender_user_id, body,
                               compliance_status, compliance_rule_version)
  values (athlete_2027, coach_id, coach_id, 'Hello from a permitted coach', 'CLIENT_SUPPLIED', 999)
  returning id into msg_id;
  select compliance_status into got_status from public.messages where id = msg_id;
  assert got_status = 'permitted', '2 status: ' || coalesce(got_status, '<null>');
  select count(*) into n from public.messages where id = msg_id
    and compliance_rule_id = 'b1b2c3d4-0002-4000-8000-000000000001' and compliance_rule_version = 1
    and compliance_evaluated_at is not null;
  assert n = 1, '2 compliance columns should be trigger-owned (client values overwritten)';
  select count(*) into n from public.notifications where user_id = athlete_user_2027 and type = 'message';
  assert n = 1, '2 notification expected, found ' || n;
  select count(*) into n from public.recruiting_compliance_decisions
    where actor_user_id = coach_id and athlete_id = athlete_2027 and decision = 'permitted'
      and evaluation_source = 'message_trigger';
  assert n = 1, '2 audit row expected';
  select count(*) into n from public.recruiting_compliance_decisions d
    where d.actor_user_id = coach_id and d.context_snapshot::text like '%Hello from%';
  assert n = 0, '2 audit log must not contain message body';

  -- 3. Athlete → coach before the coach window: allowed, no compliance stamp --------
  insert into public.messages (athlete_id, coach_user_id, sender_user_id, body)
  values (athlete_2029, coach_id, athlete_user_2029, 'Hi coach, I would like to introduce myself')
  returning id into msg_id;
  select count(*) into n from public.messages where id = msg_id and compliance_status is null and compliance_rule_id is null;
  assert n = 1, '3 athlete message should carry no compliance stamp';
  select count(*) into n from public.notifications where user_id = coach_id and type = 'message';
  assert n = 1, '3 coach should be notified of athlete outreach';

  -- 4. Coach with NO verified membership → needs_review → allowed under Phase 1 -----
  insert into public.messages (athlete_id, coach_user_id, sender_user_id, body)
  values (athlete_2029, coach_nomembership_id, coach_nomembership_id, 'Unverified coach message')
  returning id into msg_id;
  select compliance_status into got_status from public.messages where id = msg_id;
  assert got_status = 'needs_review', '4 status: ' || coalesce(got_status, '<null>');
  select count(*) into n from public.recruiting_compliance_decisions
    where actor_user_id = coach_nomembership_id and decision = 'needs_review'
      and 'coach.verified_program' = any(missing_context);
  assert n = 1, '4 audit row with missing coach.verified_program expected';

  -- 5. Enforcement flag OFF → shadow mode: prohibited send is allowed but recorded --
  update public.app_settings set bool_value = false where key = 'recruiting_rules_enforcement_enabled';
  insert into public.messages (athlete_id, coach_user_id, sender_user_id, body)
  values (athlete_2029, coach_id, coach_id, 'Shadow-mode message')
  returning id into msg_id;
  select compliance_status into got_status from public.messages where id = msg_id;
  assert got_status = 'prohibited', '5 shadow status: ' || coalesce(got_status, '<null>');
  select count(*) into n from public.recruiting_compliance_decisions
    where actor_user_id = coach_id and athlete_id = athlete_2029 and decision = 'prohibited'
      and evaluation_source = 'message_trigger_shadow';
  assert n = 1, '5 shadow audit row expected';
  update public.app_settings set bool_value = true where key = 'recruiting_rules_enforcement_enabled';

  -- 6. Immutability: compliance columns and body cannot be rewritten ----------------
  err_msg := null;
  begin
    update public.messages set compliance_status = 'permitted' where id = msg_id;
  exception when others then
    get stacked diagnostics err_msg = message_text;
  end;
  assert err_msg = 'Messages cannot be edited after sending', '6a compliance_status: ' || coalesce(err_msg, '<no error>');
  err_msg := null;
  begin
    update public.messages set body = 'rewritten' where id = msg_id;
  exception when others then
    get stacked diagnostics err_msg = message_text;
  end;
  assert err_msg = 'Messages cannot be edited after sending', '6b body: ' || coalesce(err_msg, '<no error>');
  -- read_at stays mutable
  update public.messages set read_at = now() where id = msg_id;

  -- 7. Blocked pair still wins over the recruiting trigger ---------------------------
  insert into public.user_blocks (blocker_user_id, blocked_user_id) values (athlete_user_2027, coach_id);
  err_msg := null;
  begin
    insert into public.messages (athlete_id, coach_user_id, sender_user_id, body)
    values (athlete_2027, coach_id, coach_id, 'Should be blocked');
  exception when others then
    get stacked diagnostics err_msg = message_text;
  end;
  assert err_msg = 'This conversation is blocked. Unblock to send messages.', '7 block should win: ' || coalesce(err_msg, '<no error>');

  -- 8. Coach preflight resolver matches the trigger's decision ------------------------
  got_status := public.recruiting_enforce_coach_action(coach_id, athlete_2029,
                  'coach_send_recruiting_electronic_correspondence', now()) ->> 'status';
  assert got_status = 'prohibited', '8 preflight 2029: ' || got_status;
  got_status := public.recruiting_enforce_coach_action(coach_id, athlete_2027,
                  'coach_send_recruiting_electronic_correspondence', now()) ->> 'status';
  assert got_status = 'permitted', '8 preflight 2027: ' || got_status;
  got_status := public.recruiting_enforce_coach_action(coach_nomembership_id, athlete_2027,
                  'coach_send_recruiting_electronic_correspondence', now()) ->> 'status';
  assert got_status = 'needs_review', '8 preflight unverified: ' || got_status;

  -- Cleanup ---------------------------------------------------------------------------
  update public.app_settings set bool_value = flag_before where key = 'recruiting_rules_enforcement_enabled';
  delete from public.recruiting_compliance_decisions where actor_user_id in (coach_id, coach_nomembership_id);
  -- Since 014, signup_role = coach files a pending application and notifies
  -- every admin; those admin notifications don't cascade with the users.
  delete from public.notifications where type = 'coach_application_submitted'
    and (body like 'Test Coach applied%' or body like 'Unverified Coach applied%');
  delete from auth.users where id in (coach_id, coach_nomembership_id, athlete_user_2029, athlete_user_2027);
  delete from public.recruiting_programs where id = program_id;
end $$;

select 'ALL RECRUITING MESSAGING TESTS PASSED' as result;
