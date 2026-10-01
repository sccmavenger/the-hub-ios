-- =============================================================================
-- Coach Workspace 2E — coach messaging (019).
--
-- Run:   scripts/db-query.sh < supabase/tests/coach-messaging.test.sql
-- Pass:  final row reads "ALL COACH MESSAGING TESTS PASSED".
--
-- Fixtures: NCAA D1 men's program A with coach1 (+ coach2 colleague); athlete
-- 2029 (electronic correspondence opens 2027-06-15 → prohibited today),
-- athlete 2027 (opened 2025-06-15 → permitted); guardian of 2027 who later
-- blocks coach1. Enforcement flag flipped ON inside the block and restored.
-- Runs as `authenticated` with JWT claims.
-- =============================================================================

do $$
declare
  admin_id uuid := gen_random_uuid();
  coach1 uuid := gen_random_uuid();
  coach2 uuid := gen_random_uuid();
  ath29_user uuid := gen_random_uuid();
  ath27_user uuid := gen_random_uuid();
  guardian_user uuid := gen_random_uuid();
  ath29 uuid; ath27 uuid;
  prog_a uuid; prog_b uuid; mem1 uuid;
  flag_before boolean;
  j jsonb;
  err text;
  n integer;
  k text;
  msg_id uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  select bool_value into flag_before from public.app_settings where key = 'recruiting_rules_enforcement_enabled';

  -- Fixtures -------------------------------------------------------------------
  insert into auth.users (id, email, raw_user_meta_data, aud, role) values
    (admin_id, 'admin-' || admin_id || '@cm-test.invalid', '{}'::jsonb, 'authenticated', 'authenticated');
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');
  insert into auth.users (id, email, raw_user_meta_data, aud, role) values
    (coach1, 'c1-' || coach1 || '@cm-test.invalid', '{"signup_role":"coach","full_name":"Msg Coach One","institution":"CM Test University","governing_body":"NCAA","division":"D1","sport_gender":"mens"}'::jsonb, 'authenticated', 'authenticated'),
    (coach2, 'c2-' || coach2 || '@cm-test.invalid', '{"signup_role":"coach","full_name":"Msg Coach Two","institution":"CM Test University","governing_body":"NCAA","division":"D1","sport_gender":"mens"}'::jsonb, 'authenticated', 'authenticated'),
    (ath29_user, 'a29-' || ath29_user || '@cm-test.invalid', '{"signup_role":"athlete","full_name":"Soph Athlete","date_of_birth":"2009-01-01"}'::jsonb, 'authenticated', 'authenticated'),
    (ath27_user, 'a27-' || ath27_user || '@cm-test.invalid', '{"signup_role":"athlete","full_name":"Senior Athlete","date_of_birth":"2007-01-01"}'::jsonb, 'authenticated', 'authenticated'),
    (guardian_user, 'g-' || guardian_user || '@cm-test.invalid', '{"signup_role":"parent","full_name":"Msg Guardian"}'::jsonb, 'authenticated', 'authenticated');
  select id into ath29 from public.athletes where user_id = ath29_user;
  select id into ath27 from public.athletes where user_id = ath27_user;
  update public.athletes set grad_year = 2029, sport_gender = 'mens', academic_calendar_type = 'traditional_us',
    guardian_consent_at = now(), guardian_consent_name = 'G', guardian_consent_email = 'g@cm-test.invalid' where id = ath29;
  update public.athletes set grad_year = 2027, sport_gender = 'mens', academic_calendar_type = 'traditional_us',
    guardian_consent_at = now(), guardian_consent_name = 'G', guardian_consent_email = 'g@cm-test.invalid' where id = ath27;
  insert into public.athlete_guardians (athlete_id, user_id, relationship) values (ath27, guardian_user, 'parent');
  update public.athletes set is_published = true where id in (ath29, ath27);

  insert into public.recruiting_programs (institution_name, normalized_institution_name, governing_body, division, sport, sport_gender, verified_at, active)
  values ('CM Test University', 'cm test university ' || coach1, 'NCAA', 'D1', 'basketball', 'mens', now(), true) returning id into prog_a;
  insert into public.recruiting_programs (institution_name, normalized_institution_name, governing_body, division, sport, sport_gender, verified_at, active)
  values ('CM Test University', 'cm test university w ' || coach1, 'NCAA', 'D1', 'basketball', 'womens', now(), true) returning id into prog_b;
  insert into public.coach_program_memberships (coach_user_id, program_id, status, verified_at, title, membership_role)
    values (coach1, prog_a, 'verified', now(), 'Assistant Coach', 'assistant_coach') returning id into mem1;
  insert into public.coach_program_memberships (coach_user_id, program_id, status, verified_at)
    values (coach2, prog_a, 'verified', now());
  delete from public.notifications where user_id in (ath29_user, ath27_user, guardian_user, coach1, coach2);

  update public.app_settings set bool_value = true where key = 'recruiting_rules_enforcement_enabled';

  -- ===========================================================================
  -- A. Preflight with program
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', coach1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach1::text, true);
  execute 'set local role authenticated';

  j := public.evaluate_my_coach_action(ath29, 'coach_send_recruiting_electronic_correspondence', prog_a);
  assert (j ->> 'status') = 'prohibited' and (j ->> 'context_source') = 'verified_program', 'A1 preflight prohibited for 2029: ' || (j ->> 'status');
  assert (j ->> 'next_permitted_on') = '2027-06-15', 'A1 next permitted: ' || coalesce(j ->> 'next_permitted_on', '<null>');
  j := public.evaluate_my_coach_action(ath27, 'coach_send_recruiting_electronic_correspondence', prog_a);
  assert (j ->> 'status') = 'permitted', 'A2 preflight permitted for 2027: ' || (j ->> 'status');
  err := null;
  begin j := public.evaluate_my_coach_action(ath27, 'coach_send_recruiting_electronic_correspondence', prog_b);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not authorized', 'A3 preflight with a program the coach lacks: ' || coalesce(err, '<none>');

  -- ===========================================================================
  -- B. Denied send is durable; nothing delivered
  -- ===========================================================================
  j := public.send_coach_message(prog_a, ath29, 'TEST BODY MUST NOT BE STORED');
  assert (j ->> 'status') = 'denied', 'B1 send denied: ' || j::text;
  assert (j -> 'decision' ->> 'status') = 'prohibited', 'B1 decision carried';
  select count(*) into n from public.messages where athlete_id = ath29;
  assert n = 0, 'B2 no message row';
  execute 'reset role';
  select count(*) into n from public.recruiting_denied_attempts where actor_user_id = coach1 and athlete_id = ath29 and program_id = prog_a and source = 'send_rpc';
  assert n = 1, 'B3 denied attempt recorded durably';
  select count(*) into n from public.recruiting_denied_attempts where actor_user_id = coach1 and (context_snapshot::text like '%TEST BODY%');
  assert n = 0, 'B3 no body in audit';
  select count(*) into n from public.notifications where user_id = ath29_user and type = 'message';
  assert n = 0, 'B4 no notification for a denied send';
  -- Direct insert is still refused by the trigger (final guard), with program_id
  execute 'set local role authenticated';
  err := null;
  begin insert into public.messages (athlete_id, coach_user_id, sender_user_id, body, program_id) values (ath29, coach1, coach1, 'direct', prog_a);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'RECRUITING_ACTION_PROHIBITED', 'B5 direct insert blocked by trigger: ' || coalesce(err, '<none>');
  -- Forged program on a direct insert
  err := null;
  begin insert into public.messages (athlete_id, coach_user_id, sender_user_id, body, program_id) values (ath27, coach1, coach1, 'direct', prog_b);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err is not null, 'B6 forged program_id refused';

  -- ===========================================================================
  -- C. Permitted send: stored with program, stamped, notified without preview
  -- ===========================================================================
  j := public.send_coach_message(prog_a, ath27, 'Hello Senior, we would love to talk.');
  assert (j ->> 'status') = 'sent', 'C1 sent: ' || j::text;
  msg_id := (j -> 'message' ->> 'id')::uuid;
  assert (j -> 'message' ->> 'program_id')::uuid = prog_a, 'C1 program stored';
  assert (j -> 'message' ->> 'compliance_status') = 'permitted', 'C1 stamped permitted';
  err := null;
  begin j := public.send_coach_message(prog_a, ath27, '   ');
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'message is empty', 'C2 empty refused';
  execute 'reset role';
  select body into k from public.notifications where user_id = ath27_user and type = 'message' order by created_at desc limit 1;
  assert k like 'Msg Coach One sent you a message%' and k not like '%Senior, we would%', 'C3 preview OFF by default: ' || coalesce(k, '<null>');
  select destination ->> 'type' into k from public.notifications where user_id = ath27_user and type = 'message' order by created_at desc limit 1;
  assert k = 'thread', 'C3 typed destination';
  select count(*) into n from public.notifications where user_id = guardian_user and type = 'message';
  assert n = 1, 'C4 guardian notified';
  -- Opt in → preview appears for the next message
  insert into public.user_settings (user_id, show_message_previews) values (ath27_user, true);
  execute 'set local role authenticated';
  j := public.send_coach_message(prog_a, ath27, 'Second note with preview');
  execute 'reset role';
  -- (same-transaction rows share created_at, so match on content, not order)
  select count(*) into n from public.notifications where user_id = ath27_user and type = 'message'
    and body like 'Msg Coach One: Second note with preview%';
  assert n = 1, 'C5 preview ON after opt-in';
  select count(*) into n from public.notifications where user_id = guardian_user and type = 'message' and body like '%Second note%';
  assert n = 0, 'C5 guardian still has previews off';
  select count(*) into n from public.notifications where user_id = guardian_user and type = 'message';
  assert n = 2, 'C5 guardian got both notifications, redacted';

  -- ===========================================================================
  -- D. Inbox, athlete-initiated thread, read marking
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', ath29_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', ath29_user::text, true);
  execute 'set local role authenticated';
  insert into public.messages (athlete_id, coach_user_id, sender_user_id, body) values (ath29, coach1, ath29_user, 'Hi coach, I would like to introduce myself');
  execute 'reset role';
  select program_id is null into k from public.messages where athlete_id = ath29 and sender_user_id = ath29_user;

  perform set_config('request.jwt.claims', json_build_object('sub', coach1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach1::text, true);
  execute 'set local role authenticated';
  j := public.coach_inbox(prog_a);
  assert jsonb_array_length(j) = 2, 'D1 two threads, got ' || jsonb_array_length(j);
  assert (j -> 0 -> 'athlete' ->> 'full_name') = 'Soph Athlete', 'D1 newest thread first';
  assert (j -> 0 ->> 'unread_count')::int = 1, 'D1 unread from athlete';
  assert not (j -> 0 -> 'athlete' ? 'date_of_birth'), 'D1 inbox cards allowlisted';
  -- Reply to the athlete-initiated thread is still a recruiting send → denied today
  j := public.send_coach_message(prog_a, ath29, 'Thanks for reaching out');
  assert (j ->> 'status') = 'denied', 'D2 reply before the window is denied (no template exception)';
  -- Coach reads thread via RLS and marks read
  select count(*) into n from public.messages where athlete_id = ath29 and coach_user_id = coach1;
  assert n = 1, 'D3 coach reads the athlete-initiated message';
  update public.messages set read_at = now() where athlete_id = ath29 and coach_user_id = coach1 and sender_user_id <> coach1;
  j := public.coach_inbox(prog_a);
  assert (j -> 0 ->> 'unread_count')::int = 0, 'D4 marked read';
  execute 'reset role';

  -- ===========================================================================
  -- E. Blocked coach loses the thread; colleague unaffected
  -- ===========================================================================
  insert into public.user_blocks (blocker_user_id, blocked_user_id) values (guardian_user, coach1);
  execute 'set local role authenticated';
  select count(*) into n from public.messages where athlete_id = ath27;
  assert n = 0, 'E1 blocked coach cannot read the thread';
  j := public.coach_inbox(prog_a);
  select count(*) into n from jsonb_array_elements(j) t where (t -> 'athlete' ->> 'full_name') = 'Senior Athlete';
  assert n = 0, 'E2 blocked thread gone from inbox';
  err := null;
  begin j := public.send_coach_message(prog_a, ath27, 'still there?');
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not found', 'E3 blocked coach cannot send: ' || coalesce(err, '<none>');
  err := null;
  begin j := public.evaluate_my_coach_action(ath27, 'coach_send_recruiting_electronic_correspondence', prog_a);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not authorized', 'E4 blocked coach preflight denied';
  execute 'reset role';
  delete from public.user_blocks where blocker_user_id = guardian_user and blocked_user_id = coach1;

  -- Coach blocks an athlete through the helper (no user id exposed)
  execute 'set local role authenticated';
  perform public.coach_block_athlete(ath27, true);
  execute 'reset role';
  select count(*) into n from public.user_blocks where blocker_user_id = coach1 and blocked_user_id = ath27_user;
  assert n = 1, 'E5 coach_block_athlete resolved the owner';
  execute 'set local role authenticated';
  perform public.coach_block_athlete(ath27, false);
  execute 'reset role';

  -- ===========================================================================
  -- F. Suspended coach loses reads
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';
  j := public.set_coach_membership_status(mem1, 'suspended');
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', coach1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach1::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.messages;
  assert n = 0, 'F1 suspended coach reads no messages';
  err := null; begin j := public.coach_inbox(prog_a); exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not authorized', 'F2 suspended coach inbox denied';
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';
  j := public.set_coach_membership_status(mem1, 'verified');
  select count(*) into n from public.recruiting_denied_attempts where actor_user_id = coach1;
  assert n >= 1, 'F3 admin can read denied attempts';
  execute 'reset role';

  -- ===========================================================================
  -- G. Shadow mode: prohibited send goes through, stamped, no denied row
  -- ===========================================================================
  update public.app_settings set bool_value = false where key = 'recruiting_rules_enforcement_enabled';
  select count(*) into n from public.recruiting_denied_attempts where actor_user_id = coach1;   -- as migration role (RLS off)
  perform set_config('request.jwt.claims', json_build_object('sub', coach1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach1::text, true);
  execute 'set local role authenticated';
  j := public.send_coach_message(prog_a, ath29, 'Shadow-mode message');
  assert (j ->> 'status') = 'sent' and (j -> 'message' ->> 'compliance_status') = 'prohibited', 'G1 shadow mode delivers and stamps prohibited';
  execute 'reset role';
  select count(*) into k from public.recruiting_denied_attempts where actor_user_id = coach1;
  assert k::int = n, 'G2 no denied row in shadow mode';

  -- Cleanup --------------------------------------------------------------------
  update public.app_settings set bool_value = flag_before where key = 'recruiting_rules_enforcement_enabled';
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  delete from public.recruiting_denied_attempts where actor_user_id in (coach1, coach2);
  delete from public.recruiting_compliance_decisions where actor_user_id in (coach1, coach2);
  delete from public.notifications where user_id in (coach1, coach2, admin_id, ath29_user, ath27_user, guardian_user);
  delete from public.notifications where type like 'coach_%' and body like '%CM Test University%';
  delete from public.program_board_entries where program_id in (prog_a, prog_b);
  delete from auth.users where id in (admin_id, coach1, coach2, ath29_user, ath27_user, guardian_user);
  delete from public.recruiting_programs where id in (prog_a, prog_b);
end $$;

select 'ALL COACH MESSAGING TESTS PASSED' as result;
