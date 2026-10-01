-- =============================================================================
-- Coach onboarding & verification tests (014; spec §35–§41).
--
-- Run:   scripts/db-query.sh < supabase/tests/coach-onboarding.test.sql
-- Pass:  final row reads "ALL COACH ONBOARDING TESTS PASSED".
--
-- Creates throwaway auth users (@coach-test.invalid) and removes them at the
-- end. One DO block = one statement, so a failed assert rolls back every
-- fixture. Unlike the recruiting tests this suite also switches to the
-- `authenticated` role (what PostgREST does) so RLS policies — not just
-- auth.uid() checks inside functions — are exercised. The "pending coach
-- cannot…" section is the spec's release blocker (§37).
-- =============================================================================

do $$
declare
  admin_id uuid := gen_random_uuid();
  coach1 uuid := gen_random_uuid();     -- approved, then suspended/reinstated/inactivated
  coach2 uuid := gen_random_uuid();     -- rejected → resubmit → needs info → resubmit → withdraw
  athlete_user uuid := gen_random_uuid();
  parent_user uuid := gen_random_uuid();
  athlete_id uuid;
  req1 uuid;
  req2 uuid;
  prog_id uuid;
  mem_id uuid;
  tmp_prog uuid;
  n integer;
  err text;
  j jsonb;
  r record;

  procedure_marker text := 'coach-onboarding';
begin
  -- ===========================================================================
  -- Fixtures (migration role, no JWT)
  -- ===========================================================================
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  -- Admin first, so the coach signups below notify it.
  insert into auth.users (id, email, raw_user_meta_data, aud, role) values
    (admin_id, 'admin-' || admin_id || '@coach-test.invalid', '{}'::jsonb, 'authenticated', 'authenticated');
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');

  insert into auth.users (id, email, raw_user_meta_data, aud, role) values
    -- Tampered metadata: status/roles/division claims must never become truth.
    (coach1, 'coach1-' || coach1 || '@coach-test.invalid',
     jsonb_build_object(
       'signup_role', 'coach', 'full_name', '  Test   Coach One ', 'coach_title', 'Assistant Coach',
       'institution', 'Coach Test University', 'governing_body', 'ncaa', 'division', 'Division I',
       'sport_gender', 'Men''s', 'athletics_url', 'javascript:alert(1)', 'program_url', 'https://athletics.example.test/mbb',
       'phone', '555-0100', 'verification_note', 'Listed on staff directory.',
       'status', 'approved', 'user_roles', 'coach', 'role', 'admin'),
     'authenticated', 'authenticated'),
    (coach2, 'coach2-' || coach2 || '@coach-test.invalid',
     jsonb_build_object(
       'signup_role', 'coach', 'full_name', 'Test Coach Two', 'coach_title', 'Head Coach',
       'institution', 'Coach Test College', 'governing_body', 'NJCAA', 'division', 'D2', 'sport_gender', 'womens'),
     'authenticated', 'authenticated'),
    (athlete_user, 'ath-' || athlete_user || '@coach-test.invalid',
     '{"signup_role": "athlete", "full_name": "Test Adult Athlete", "date_of_birth": "2005-01-01"}'::jsonb,
     'authenticated', 'authenticated'),
    (parent_user, 'par-' || parent_user || '@coach-test.invalid',
     '{"signup_role": "parent", "full_name": "Test Parent"}'::jsonb, 'authenticated', 'authenticated');

  -- Regression: athlete/parent signup unchanged --------------------------------
  select id into athlete_id from public.athletes where user_id = athlete_user;
  assert athlete_id is not null, 'R1 athlete row should be created by signup trigger';
  select count(*) into n from public.user_roles where user_id = athlete_user and role = 'athlete';
  assert n = 1, 'R1 athlete role';
  select count(*) into n from public.user_roles where user_id = parent_user and role = 'parent';
  assert n = 1, 'R1 parent role';
  select count(*) into n from public.coach_requests where user_id in (athlete_user, parent_user);
  assert n = 0, 'R1 athlete/parent signups must not create coach requests';
  update public.athletes set is_published = true, grad_year = 2023, sport_gender = 'mens' where id = athlete_id;

  -- ===========================================================================
  -- §35 Coach signup: account + profile + PENDING request, no role, sanitized
  -- ===========================================================================
  select count(*) into n from public.user_profiles where id = coach1;
  assert n = 1, 'S1 coach profile created';
  select * into r from public.coach_requests where user_id = coach1;
  assert found, 'S1 coach request created';
  req1 := r.id;
  assert r.status = 'pending', 'S1 status must be pending despite metadata, got ' || r.status;
  assert r.full_name = 'Test Coach One', 'S1 name whitespace collapsed: [' || r.full_name || ']';
  assert r.college = 'Coach Test University', 'S1 institution';
  assert r.governing_body = 'NCAA', 'S1 governing body normalized: ' || coalesce(r.governing_body, '<null>');
  assert r.division = 'D1', 'S1 division normalized: ' || coalesce(r.division, '<null>');
  assert r.sport_gender = 'mens', 'S1 sport_gender normalized: ' || coalesce(r.sport_gender, '<null>');
  assert r.athletics_url is null, 'S1 non-http URL dropped';
  assert r.program_url = 'https://athletics.example.test/mbb', 'S1 http URL kept';
  assert r.approved_program_id is null and r.reviewed_by is null, 'S1 verified linkage unset';
  select count(*) into n from public.user_roles where user_id = coach1;
  assert n = 0, 'S1 coach signup must grant NO role, found ' || n;
  select count(*) into n from public.coach_program_memberships where coach_user_id = coach1;
  assert n = 0, 'S1 no membership at signup';
  select count(*) into n from public.coach_request_reviews where request_id = req1 and action = 'submitted';
  assert n = 1, 'S1 submitted review event';
  select count(*) into n from public.notifications where user_id = admin_id and type = 'coach_application_submitted';
  assert n = 2, 'S1 admins notified once per application, got ' || n;

  select id into req2 from public.coach_requests where user_id = coach2;
  assert req2 is not null, 'S1 second request';

  -- ===========================================================================
  -- §37 Pending coach cannot reach athlete data (RLS, as `authenticated`)
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', coach1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach1::text, true);
  execute 'set local role authenticated';

  assert public.has_role('coach') = false, 'P0 pending coach has no coach role';
  select count(*) into n from public.athletes;
  assert n = 0, 'P1 pending coach must not see published athletes, saw ' || n;
  select count(*) into n from public.athlete_contacts;
  assert n = 0, 'P2 pending coach sees no contacts';

  err := null;
  begin
    insert into public.coach_saved_athletes (coach_user_id, athlete_id) values (coach1, athlete_id);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err is not null, 'P3 pending coach must not save athletes';

  err := null;
  begin
    insert into public.messages (athlete_id, coach_user_id, sender_user_id, body)
    values (athlete_id, coach1, coach1, 'pending coach message');
  exception when others then get stacked diagnostics err = message_text; end;
  assert err is not null, 'P4 pending coach must not message';

  err := null;
  begin
    insert into public.user_roles (user_id, role) values (coach1, 'coach');
  exception when others then get stacked diagnostics err = message_text; end;
  assert err is not null, 'P5 pending coach must not self-grant coach';

  err := null;
  begin
    insert into public.coach_program_memberships (coach_user_id, program_id, status)
    select coach1, id, 'verified' from public.recruiting_programs limit 1;
  exception when others then get stacked diagnostics err = message_text; end;
  -- Either RLS (no policy) or "0 rows" if no program exists — both mean no access.
  select count(*) into n from public.coach_program_memberships where coach_user_id = coach1;
  assert n = 0, 'P6 pending coach must not self-verify membership';

  select count(*) into n from public.coach_requests;
  assert n = 1, 'P7 coach sees exactly own request, saw ' || n;
  select count(*) into n from public.coach_request_reviews;
  assert n = 0, 'P8 review log is admin-only';

  update public.coach_requests set status = 'approved' where id = req1;   -- no owner update policy → 0 rows
  execute 'reset role';
  select status into err from public.coach_requests where id = req1;
  assert err = 'pending', 'P9 owner cannot flip status, got ' || err;

  execute 'set local role authenticated';
  err := null;
  begin
    j := public.approve_coach_request(req1, null, '{"institution_name":"X","governing_body":"NCAA","division":"D1","sport_gender":"mens"}'::jsonb);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not authorized', 'P10 non-admin approval denied, got: ' || coalesce(err, '<none>');

  err := null;
  begin
    j := public.reject_coach_request(req2, 'nope');
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not authorized', 'P11 non-admin rejection denied';
  execute 'reset role';

  -- ===========================================================================
  -- §27 Guards: even an ADMIN client cannot take the non-atomic shortcuts
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';

  err := null;
  begin
    update public.coach_requests set status = 'approved', reviewed_by = admin_id where id = req1;
  exception when others then get stacked diagnostics err = message_text; end;
  assert err like 'coach request review fields change only via%', 'G1 direct status flip blocked: ' || coalesce(err, '<none>');

  err := null;
  begin
    insert into public.user_roles (user_id, role) values (coach1, 'coach');
  exception when others then get stacked diagnostics err = message_text; end;
  assert err like 'coach role is granted only by approving%', 'G2 direct coach grant blocked: ' || coalesce(err, '<none>');

  insert into public.recruiting_programs (institution_name, normalized_institution_name, governing_body, division, sport, sport_gender)
  values ('Coach Test Guard U', 'coach test guard u', 'NCAA', 'D2', 'basketball', 'mens')
  returning id into tmp_prog;
  err := null;
  begin
    insert into public.coach_program_memberships (coach_user_id, program_id, status, verified_at)
    values (coach1, tmp_prog, 'verified', now());
  exception when others then get stacked diagnostics err = message_text; end;
  assert err like 'memberships are verified only via%', 'G3 direct verified membership blocked: ' || coalesce(err, '<none>');
  -- admin may still edit claim fields directly
  update public.coach_requests set phone = '555-0199' where id = req1;

  -- ===========================================================================
  -- §36 Approval: validation failures leave no partial state
  -- ===========================================================================
  err := null;
  begin
    j := public.approve_coach_request(req1, null,
      '{"institution_name":"Coach Test University","governing_body":"NCAA","division":"D1","sport_gender":"boys"}'::jsonb);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err like 'program sport_gender%', 'A1 invalid program rejected: ' || coalesce(err, '<none>');
  err := null;
  begin
    j := public.approve_coach_request(req1, null,
      '{"institution_name":"Coach Test University","governing_body":"NCAA","sport_gender":"mens"}'::jsonb);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err like 'NCAA programs need a division%', 'A2 NCAA without division rejected: ' || coalesce(err, '<none>');
  err := null;
  begin
    j := public.approve_coach_request(req1, gen_random_uuid());
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'program not found', 'A3 unknown program id rejected: ' || coalesce(err, '<none>');
  err := null;
  begin
    j := public.approve_coach_request(req1);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err like 'approval requires%', 'A4 program required';

  execute 'reset role';
  select status into err from public.coach_requests where id = req1;
  assert err = 'pending', 'A5 request still pending after failed approvals';
  select count(*) into n from public.user_roles where user_id = coach1 and role = 'coach';
  assert n = 0, 'A5 no role after failed approvals';
  select count(*) into n from public.coach_program_memberships where coach_user_id = coach1;
  assert n = 0, 'A5 no membership after failed approvals';
  select count(*) into n from public.recruiting_programs where normalized_institution_name = 'coach test university';
  assert n = 0, 'A5 no program created by failed approvals';

  -- ===========================================================================
  -- §36 Valid approval: program + membership + role + request + notification
  -- ===========================================================================
  execute 'set local role authenticated';
  j := public.approve_coach_request(
    req1, null,
    '{"institution_name":" Coach Test  University ","governing_body":"NCAA","division":"D1","sport_gender":"mens","athletics_url":"https://athletics.example.test"}'::jsonb,
    'assistant_coach', 'Assistant Coach, Men''s Basketball', 'Verified via staff directory 2026-09-30');
  execute 'reset role';

  prog_id := (j ->> 'program_id')::uuid;
  mem_id := (j ->> 'membership_id')::uuid;
  assert prog_id is not null and mem_id is not null, 'V1 approval returns ids';

  select * into r from public.coach_requests where id = req1;
  assert r.status = 'approved', 'V2 request approved';
  assert r.reviewed_by = admin_id and r.reviewed_at is not null, 'V2 reviewer recorded';
  assert r.approved_program_id = prog_id and r.approved_membership_id = mem_id, 'V2 linkage stored';

  select * into r from public.recruiting_programs where id = prog_id;
  assert r.institution_name = 'Coach Test University', 'V3 program name cleaned: [' || r.institution_name || ']';
  assert r.verified_at is not null and r.verified_by = admin_id, 'V3 program verified by admin';
  assert r.governing_body = 'NCAA' and r.division = 'D1' and r.sport_gender = 'mens' and r.sport = 'basketball', 'V3 program attrs';

  select * into r from public.coach_program_memberships where id = mem_id;
  assert r.status = 'verified' and r.verified_by = admin_id and r.coach_user_id = coach1, 'V4 membership verified';
  assert r.membership_role = 'assistant_coach' and r.title = 'Assistant Coach, Men''s Basketball', 'V4 membership attrs';
  assert r.started_at = current_date and r.ended_at is null, 'V4 dates';

  select count(*) into n from public.user_roles where user_id = coach1 and role = 'coach';
  assert n = 1, 'V5 coach role granted';
  select count(*) into n from public.user_roles where user_id = coach1;
  assert n = 1, 'V5 only the coach role';

  select count(*) into n from public.notifications where user_id = coach1 and type = 'coach_application_approved'
    and body like '%Coach Test University Men''s Basketball%';
  assert n = 1, 'V6 coach notified with program label';
  select count(*) into n from public.coach_request_reviews where request_id = req1 and action = 'approved'
    and actor_user_id = admin_id and internal_note like 'Verified via%';
  assert n = 1, 'V7 approval audited with internal note';

  -- Re-approval / rejection of an approved request is refused
  execute 'set local role authenticated';
  err := null;
  begin
    j := public.approve_coach_request(req1, prog_id);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err like 'coach request is approved%', 'V8 double approval refused: ' || coalesce(err, '<none>');
  err := null;
  begin
    j := public.reject_coach_request(req1, 'too late');
  exception when others then get stacked diagnostics err = message_text; end;
  assert err like 'coach request is approved%', 'V9 reject after approve refused';
  execute 'reset role';

  -- Approved coach now passes coach RLS
  perform set_config('request.jwt.claims', json_build_object('sub', coach1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach1::text, true);
  execute 'set local role authenticated';
  assert public.has_role('coach'), 'V10 approved coach has role';
  -- Since 016 coaches never read the athletes table; the detail RPC is the path.
  select count(*) into n from public.athletes where id = athlete_id;
  assert n = 0, 'V10 coaches do not read the athletes table directly (016), saw ' || n;
  j := public.coach_athlete_detail(prog_id, athlete_id);
  assert (j -> 'athlete' ->> 'full_name') = 'Test Adult Athlete', 'V10 approved coach reads the published athlete via RPC';
  select count(*) into n from public.coach_program_memberships m join public.recruiting_programs p on p.id = m.program_id
    where m.coach_user_id = coach1 and m.status = 'verified' and p.verified_at is not null;
  assert n = 1, 'V11 coach can read own verified membership + program (CoachProgramService path)';
  -- Coach cannot alter own membership (no policy → 0 rows)
  update public.coach_program_memberships set status = 'inactive' where id = mem_id;
  execute 'reset role';
  select status into err from public.coach_program_memberships where id = mem_id;
  assert err = 'verified', 'V12 coach cannot change own membership';

  -- ===========================================================================
  -- §39 Revocation: suspend → role gone, access stops, history intact
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';
  j := public.set_coach_membership_status(mem_id, 'suspended', 'Left program per AD email');
  execute 'reset role';
  assert (j ->> 'has_coach_role')::boolean = false, 'X1 suspension drops role';
  select count(*) into n from public.user_roles where user_id = coach1 and role = 'coach';
  assert n = 0, 'X1 role row removed';
  select count(*) into n from public.coach_program_memberships where id = mem_id and status = 'suspended';
  assert n = 1, 'X2 membership row retained as suspended';
  select count(*) into n from public.recruiting_programs where id = prog_id;
  assert n = 1, 'X2 program retained';
  select count(*) into n from public.notifications where user_id = coach1 and type = 'coach_membership_suspended';
  assert n = 1, 'X3 coach notified of suspension';
  select count(*) into n from public.coach_request_reviews where request_id = req1 and action = 'membership_suspended';
  assert n = 1, 'X3 suspension audited';

  perform set_config('request.jwt.claims', json_build_object('sub', coach1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach1::text, true);
  execute 'set local role authenticated';
  err := null;
  begin
    j := public.coach_athlete_detail(prog_id, athlete_id);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not authorized', 'X4 suspended coach loses athlete access immediately: ' || coalesce(err, '<none>');
  execute 'reset role';

  -- Reinstate → role back; inactivate → role gone + ended_at
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';
  j := public.set_coach_membership_status(mem_id, 'verified');
  assert (j ->> 'has_coach_role')::boolean, 'X5 reinstate restores role';
  j := public.set_coach_membership_status(mem_id, 'inactive');
  assert (j ->> 'has_coach_role')::boolean = false, 'X6 inactivate drops role';
  execute 'reset role';
  select * into r from public.coach_program_memberships where id = mem_id;
  assert r.status = 'inactive' and r.ended_at = current_date, 'X6 ended_at stamped';

  -- Program deactivation also drops the role (trigger path), even from SQL
  execute 'set local role authenticated';
  j := public.set_coach_membership_status(mem_id, 'verified');
  execute 'reset role';
  update public.recruiting_programs set active = false where id = prog_id;
  select count(*) into n from public.user_roles where user_id = coach1 and role = 'coach';
  assert n = 0, 'X7 inactive program removes dependent coach role';
  update public.recruiting_programs set active = true where id = prog_id;
  select count(*) into n from public.user_roles where user_id = coach1 and role = 'coach';
  assert n = 1, 'X7 reactivating program restores role';

  -- ===========================================================================
  -- §38 Rejection → resubmit → needs info → resubmit → withdraw
  -- ===========================================================================
  execute 'set local role authenticated';
  j := public.reject_coach_request(req2, 'We could not verify your affiliation with the program information provided.', 'No listing on NJCAA site');
  execute 'reset role';
  select * into r from public.coach_requests where id = req2;
  assert r.status = 'rejected' and r.rejection_reason like 'We could not verify%', 'J1 rejected with reason';
  assert r.reviewed_by = admin_id, 'J1 reviewer';
  select count(*) into n from public.user_roles where user_id = coach2;
  assert n = 0, 'J1 rejected coach has no role';
  select count(*) into n from public.notifications where user_id = coach2 and type = 'coach_application_rejected';
  assert n = 1, 'J1 coach notified';

  -- Rejected coach: can sign in, sees reason, no athlete access, resubmits
  perform set_config('request.jwt.claims', json_build_object('sub', coach2, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach2::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.athletes;
  assert n = 0, 'J2 rejected coach has no athlete access';
  select rejection_reason into err from public.coach_requests where id = req2;
  assert err like 'We could not verify%', 'J2 rejected coach can read reason';

  err := null;
  begin
    j := public.update_coach_application('{"governing_body":"NBA"}'::jsonb);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'invalid governing_body', 'J3 invalid claim rejected: ' || coalesce(err, '<none>');

  j := public.update_coach_application(
    '{"college":"Coach Test College","governing_body":"NAIA","division":null,"sport_gender":"womens","athletics_url":"https://athletics.example.test/staff","status":"approved"}'::jsonb);
  execute 'reset role';
  select * into r from public.coach_requests where id = req2;
  assert r.status = 'pending', 'J4 resubmit → pending (status claim ignored), got ' || r.status;
  assert r.resubmitted_at is not null, 'J4 resubmitted_at stamped';
  assert r.rejection_reason is null and r.reviewed_by is null, 'J4 review cleared';
  assert r.governing_body = 'NAIA' and r.division is null and r.sport_gender = 'womens', 'J4 claims updated';
  assert r.athletics_url = 'https://athletics.example.test/staff', 'J4 url stored';
  select count(*) into n from public.coach_request_reviews where request_id = req2 and action = 'resubmitted';
  assert n = 1, 'J4 resubmission audited';
  select count(*) into n from public.notifications where user_id = admin_id and type = 'coach_application_submitted'
    and title = 'Coach application resubmitted';
  assert n = 1, 'J4 admin notified of resubmission';

  -- Request more info
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';
  j := public.request_coach_info(req2, 'Please send a link to your listing in the staff directory.');
  execute 'reset role';
  select * into r from public.coach_requests where id = req2;
  assert r.status = 'needs_more_information' and r.info_request_message like 'Please send%', 'J5 needs info';
  select count(*) into n from public.notifications where user_id = coach2 and type = 'coach_application_needs_information';
  assert n = 1, 'J5 coach notified';

  perform set_config('request.jwt.claims', json_build_object('sub', coach2, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach2::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.athletes;
  assert n = 0, 'J6 needs-info coach has no athlete access';
  j := public.update_coach_application('{"program_url":"https://athletics.example.test/wbb/roster"}'::jsonb);
  assert (j ->> 'status') = 'pending' and (j ->> 'info_request_message') is null, 'J6 back to pending';

  -- Withdraw, then apply again
  j := public.withdraw_coach_application();
  assert (j ->> 'status') = 'withdrawn', 'J7 withdrawn';
  err := null;
  begin
    j := public.withdraw_coach_application();
  exception when others then get stacked diagnostics err = message_text; end;
  assert err like 'application cannot be withdrawn%', 'J7 double withdraw refused';
  j := public.update_coach_application('{}'::jsonb);
  assert (j ->> 'status') = 'pending', 'J8 re-apply after withdraw → pending';
  execute 'reset role';

  -- An athlete account cannot open a coach application
  perform set_config('request.jwt.claims', json_build_object('sub', athlete_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', athlete_user::text, true);
  execute 'set local role authenticated';
  err := null;
  begin
    j := public.update_coach_application('{"college":"Sneaky U"}'::jsonb);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not authorized', 'J9 role-holding account cannot create coach application: ' || coalesce(err, '<none>');
  err := null;
  begin
    insert into public.coach_requests (user_id, full_name, email) values (athlete_user, 'x', 'x@coach-test.invalid');
  exception when others then get stacked diagnostics err = message_text; end;
  assert err is not null, 'J9 direct coach_requests insert blocked (policy removed)';
  execute 'reset role';

  -- Approved coach cannot edit the application any more
  perform set_config('request.jwt.claims', json_build_object('sub', coach1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach1::text, true);
  execute 'set local role authenticated';
  err := null;
  begin
    j := public.update_coach_application('{"college":"Other U"}'::jsonb);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err like 'application is not editable in status approved%', 'J10 approved not editable: ' || coalesce(err, '<none>');
  execute 'reset role';

  -- ===========================================================================
  -- Cleanup
  -- ===========================================================================
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  delete from public.notifications where type like 'coach_%' and body like '%Coach Test%';
  delete from auth.users where id in (admin_id, coach1, coach2, athlete_user, parent_user);
  delete from public.recruiting_programs where id in (prog_id, tmp_prog);
  select count(*) into n from public.coach_requests where email like '%@coach-test.invalid';
  assert n = 0, 'cleanup: requests cascaded';
end $$;

select 'ALL COACH ONBOARDING TESTS PASSED' as result;
