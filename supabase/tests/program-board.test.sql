-- =============================================================================
-- Coach Workspace 2B — program-owned Recruiting Board (017).
--
-- Run:   scripts/db-query.sh < supabase/tests/program-board.test.sql
-- Pass:  final row reads "ALL PROGRAM BOARD TESTS PASSED".
--
-- Fixtures: program A (men's) with coach1 + coach2 (colleagues) and coach3 on
-- program B (women's); two published men's athletes; guardian of athlete1
-- blocks coach2 midway. Runs as `authenticated` with JWT claims.
-- =============================================================================

do $$
declare
  coach1 uuid := gen_random_uuid();
  coach2 uuid := gen_random_uuid();
  coach3 uuid := gen_random_uuid();
  admin_id uuid := gen_random_uuid();
  ath1_user uuid := gen_random_uuid();
  ath2_user uuid := gen_random_uuid();
  guardian_user uuid := gen_random_uuid();
  ath1 uuid; ath2 uuid;
  prog_a uuid; prog_b uuid;
  entry1 uuid; entry2 uuid;
  j jsonb;
  err text;
  n integer;
  k text;
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  -- Fixtures -------------------------------------------------------------------
  insert into auth.users (id, email, raw_user_meta_data, aud, role) values
    (admin_id, 'admin-' || admin_id || '@pb-test.invalid', '{}'::jsonb, 'authenticated', 'authenticated');
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');
  insert into auth.users (id, email, raw_user_meta_data, aud, role) values
    (coach1, 'c1-' || coach1 || '@pb-test.invalid', '{"signup_role":"coach","full_name":"Board Coach One","institution":"PB Test University","governing_body":"NCAA","division":"D1","sport_gender":"mens"}'::jsonb, 'authenticated', 'authenticated'),
    (coach2, 'c2-' || coach2 || '@pb-test.invalid', '{"signup_role":"coach","full_name":"Board Coach Two","institution":"PB Test University","governing_body":"NCAA","division":"D1","sport_gender":"mens"}'::jsonb, 'authenticated', 'authenticated'),
    (coach3, 'c3-' || coach3 || '@pb-test.invalid', '{"signup_role":"coach","full_name":"Board Coach Three","institution":"PB Test University","governing_body":"NCAA","division":"D1","sport_gender":"womens"}'::jsonb, 'authenticated', 'authenticated'),
    (ath1_user, 'a1-' || ath1_user || '@pb-test.invalid', '{"signup_role":"athlete","full_name":"Board Athlete One","date_of_birth":"2009-05-01"}'::jsonb, 'authenticated', 'authenticated'),
    (ath2_user, 'a2-' || ath2_user || '@pb-test.invalid', '{"signup_role":"athlete","full_name":"Board Athlete Two","date_of_birth":"2005-05-01"}'::jsonb, 'authenticated', 'authenticated'),
    (guardian_user, 'g-' || guardian_user || '@pb-test.invalid', '{"signup_role":"parent","full_name":"Board Guardian"}'::jsonb, 'authenticated', 'authenticated');

  select id into ath1 from public.athletes where user_id = ath1_user;
  select id into ath2 from public.athletes where user_id = ath2_user;
  update public.athletes set sport_gender = 'mens', grad_year = 2027, position = 'Guard',
    guardian_consent_at = now(), guardian_consent_name = 'Board Guardian', guardian_consent_email = 'g@pb-test.invalid'
    where id = ath1;
  insert into public.athlete_guardians (athlete_id, user_id, relationship) values (ath1, guardian_user, 'parent');
  update public.athletes set sport_gender = 'mens', grad_year = 2026, position = 'Forward' where id = ath2;
  update public.athletes set is_published = true where id in (ath1, ath2);
  insert into public.athlete_contacts (athlete_id, athlete_email, guardian_phone) values (ath1, 'a1@pb-test.invalid', '555-0199');

  insert into public.recruiting_programs (institution_name, normalized_institution_name, governing_body, division, sport, sport_gender, verified_at, active)
  values ('PB Test University', 'pb test university ' || coach1, 'NCAA', 'D1', 'basketball', 'mens', now(), true) returning id into prog_a;
  insert into public.recruiting_programs (institution_name, normalized_institution_name, governing_body, division, sport, sport_gender, verified_at, active)
  values ('PB Test University', 'pb test university w ' || coach1, 'NCAA', 'D1', 'basketball', 'womens', now(), true) returning id into prog_b;
  insert into public.coach_program_memberships (coach_user_id, program_id, status, verified_at, title, membership_role) values
    (coach1, prog_a, 'verified', now(), 'Head Coach', 'head_coach'),
    (coach2, prog_a, 'verified', now(), 'Assistant Coach', 'assistant_coach'),
    (coach3, prog_b, 'verified', now(), 'Head Coach', 'head_coach');
  delete from public.notifications where user_id in (ath1_user, ath2_user, guardian_user);

  -- ===========================================================================
  -- A. Save, contact unlock, notification (D25, W6)
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', coach1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach1::text, true);
  execute 'set local role authenticated';

  j := public.coach_athlete_detail(prog_a, ath1);
  assert (j ->> 'contact_unlocked')::boolean = false and j -> 'board' = 'null'::jsonb, 'A1 locked before save';
  select count(*) into n from public.athlete_contacts where athlete_id = ath1;
  assert n = 0, 'A1 contacts RLS locked before save';

  j := public.board_save_athlete(prog_a, ath1);
  entry1 := (j ->> 'id')::uuid;
  assert (j ->> 'stage') = 'watching' and (j ->> 'saved_by_name') = 'Board Coach One', 'A2 saved: ' || j::text;
  j := public.board_save_athlete(prog_a, ath1);    -- idempotent
  assert (j ->> 'id')::uuid = entry1, 'A3 second save is a no-op';

  j := public.coach_athlete_detail(prog_a, ath1);
  assert (j ->> 'contact_unlocked')::boolean and (j -> 'contact' ->> 'athlete_email') = 'a1@pb-test.invalid', 'A4 contact via RPC after save';
  assert (j -> 'board' ->> 'id')::uuid = entry1, 'A4 board state in detail';
  select count(*) into n from public.athlete_contacts where athlete_id = ath1;
  assert n = 1, 'A5 contacts RLS unlocked after save';
  execute 'reset role';

  select count(*) into n from public.notifications where user_id = ath1_user and type = 'bookmark'
    and title = 'PB Test University Men''s Basketball saved your profile' and body like 'Coach Board Coach One%';
  assert n = 1, 'A6 athlete notified with program label + coach';
  select count(*) into n from public.notifications where user_id = guardian_user and type = 'bookmark';
  assert n = 1, 'A7 guardian notified';
  select count(*) into n from public.program_board_activity where entry_id = entry1 and action = 'saved' and actor_user_id = coach1;
  assert n = 1, 'A8 activity logged';

  -- Athlete side: bookmarks_for_athlete names the program
  perform set_config('request.jwt.claims', json_build_object('sub', ath1_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', ath1_user::text, true);
  execute 'set local role authenticated';
  select college into k from public.bookmarks_for_athlete(ath1);
  assert k = 'PB Test University Men''s Basketball', 'A9 saved-by label: ' || coalesce(k, '<null>');
  select count(*) into n from public.coach_directory_names(array[coach1]);
  assert n = 1, 'A10 directory resolves the saving coach via board relation';
  execute 'reset role';

  -- ===========================================================================
  -- B. Colleague collaboration (W5): stage, tags, assign; private notes isolated
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', coach2, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach2::text, true);
  execute 'set local role authenticated';

  j := public.board_list(prog_a);
  assert jsonb_array_length(j -> 'items') = 1, 'B1 colleague sees the shared entry';
  assert (j -> 'stage_counts' ->> 'watching')::int = 1, 'B1 stage counts';
  assert not (j -> 'items' -> 0 -> 'athlete' ? 'date_of_birth'), 'B1 allowlist on board cards';

  j := public.board_set_stage(entry1, 'evaluating');
  assert (j ->> 'stage') = 'evaluating', 'B2 colleague moved stage';
  j := public.board_set_tags(entry1, array[' Shooter ', 'shooter', 'Length', '']);
  assert j -> 'tags' = '["Shooter","Length"]'::jsonb, 'B3 tags cleaned/deduped: ' || (j -> 'tags')::text;
  err := null;
  begin j := public.board_set_tags(entry1, array['a','b','c','d','e','f','g','h','i','j','k']);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'a prospect can have at most 10 tags', 'B4 11 tags rejected: ' || coalesce(err, '<none>');
  err := null;
  begin j := public.board_set_tags(entry1, array[repeat('x', 31)]);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'tags must be 30 characters or fewer', 'B5 31-char tag rejected';

  j := public.board_assign(entry1, coach1);
  assert (j ->> 'assigned_to')::uuid = coach1 and (j ->> 'assigned_to_name') = 'Board Coach One', 'B6 assigned to colleague';
  err := null;
  begin j := public.board_assign(entry1, coach3);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'assignee is not active staff of this program', 'B7 cannot assign outside staff';

  -- Private note: coach2 writes; limits; coach1 cannot read it
  insert into public.coach_private_notes (coach_user_id, athlete_id, body) values (coach2, ath1, 'Quiet leader, needs strength work.');
  err := null;
  begin insert into public.coach_private_notes (coach_user_id, athlete_id, body) values (coach2, ath2, repeat('y', 2001));
  exception when others then get stacked diagnostics err = message_text; end;
  assert err is not null, 'B8 2,001-char note rejected';
  j := public.coach_athlete_detail(prog_a, ath1);
  assert (j ->> 'private_note') like 'Quiet leader%', 'B9 own note in detail';
  j := public.board_list(prog_a);
  assert (j -> 'items' -> 0 ->> 'has_private_note')::boolean, 'B9 has_private_note flag';
  select count(*) into n from public.program_board_activity where entry_id = entry1;
  assert n = 4, 'B10 activity rows: saved, stage, tags, assigned → ' || n;
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', coach1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach1::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.coach_private_notes;
  assert n = 0, 'B11 colleague cannot read another coach''s private notes';
  j := public.coach_athlete_detail(prog_a, ath1);
  assert j -> 'private_note' = 'null'::jsonb, 'B11 detail hides colleague note';
  j := public.board_list(prog_a, p_assigned_to => coach1);
  assert jsonb_array_length(j -> 'items') = 1 and (j ->> 'assigned_to_me')::int = 1, 'B12 assigned-to-me filter';
  j := public.coach_home_summary(prog_a);
  assert (j -> 'board_counts' ->> 'evaluating')::int = 1 and (j ->> 'assigned_to_me')::int = 1
     and jsonb_array_length(j -> 'recent_activity') = 4, 'B13 home summary: ' || j::text;
  execute 'reset role';

  -- Admin cannot read private notes either
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.coach_private_notes;
  assert n = 0, 'B14 admin cannot read private notes';
  select count(*) into n from public.program_board_entries;
  assert n = 1, 'B14 admin can read board entries';
  execute 'reset role';

  -- ===========================================================================
  -- C. Cross-program isolation
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', coach3, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach3::text, true);
  execute 'set local role authenticated';
  err := null; begin j := public.board_list(prog_a); exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not authorized', 'C1 other program cannot list';
  err := null; begin j := public.board_set_stage(entry1, 'offered'); exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not found', 'C2 other program cannot mutate';
  select count(*) into n from public.program_board_entries;
  assert n = 0, 'C3 RLS hides other program''s entries';
  err := null; begin j := public.board_save_athlete(prog_b, ath1); exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not found', 'C4 womens program cannot save a mens athlete';
  execute 'reset role';

  -- ===========================================================================
  -- D. Block hides the entry from the blocked coach only (W3, D26)
  -- ===========================================================================
  insert into public.user_blocks (blocker_user_id, blocked_user_id) values (guardian_user, coach2);
  perform set_config('request.jwt.claims', json_build_object('sub', coach2, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach2::text, true);
  execute 'set local role authenticated';
  j := public.board_list(prog_a);
  assert jsonb_array_length(j -> 'items') = 0 and (j -> 'stage_counts') = '{}'::jsonb, 'D1 blocked coach sees no entry/counts';
  select count(*) into n from public.program_board_entries;
  assert n = 0, 'D2 RLS hides entry from blocked coach';
  err := null; begin j := public.board_set_stage(entry1, 'offered'); exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not found', 'D3 blocked coach cannot mutate';
  select count(*) into n from public.athlete_contacts where athlete_id = ath1;
  assert n = 0, 'D4 blocked coach loses contact despite board entry';
  j := public.board_activity(prog_a);
  assert jsonb_array_length(j) = 0, 'D5 activity for the blocked athlete hidden';
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', coach1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach1::text, true);
  execute 'set local role authenticated';
  j := public.board_list(prog_a);
  assert jsonb_array_length(j -> 'items') = 1, 'D6 colleague still sees the entry';
  execute 'reset role';

  -- ===========================================================================
  -- E. Remove / restore keep history; unpublish blocks restore
  -- ===========================================================================
  execute 'set local role authenticated';
  j := public.board_remove(entry1);
  assert j ->> 'removed_at' is not null, 'E1 removed';
  j := public.board_list(prog_a);
  assert jsonb_array_length(j -> 'items') = 0, 'E2 removed hidden by default';
  j := public.board_list(prog_a, p_include_removed => true);
  assert jsonb_array_length(j -> 'items') = 1, 'E3 removed visible on request';
  select count(*) into n from public.athlete_contacts where athlete_id = ath1;
  assert n = 0, 'E4 contact locks when removed';
  j := public.board_restore(entry1);
  assert j ->> 'removed_at' is null and (j ->> 'stage') = 'evaluating', 'E5 restored with stage kept';
  select count(*) into n from public.program_board_activity where entry_id = entry1 and action in ('removed', 'restored');
  assert n = 2, 'E6 remove/restore audited';
  execute 'reset role';
  update public.athletes set is_published = false where id = ath1;
  execute 'set local role authenticated';
  j := public.board_remove(entry1);
  err := null; begin j := public.board_restore(entry1); exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not found' or err = 'athlete is no longer published', 'E7 unpublished cannot be restored: ' || coalesce(err, '<none>');
  execute 'reset role';
  update public.athletes set is_published = true where id = ath1;

  -- ===========================================================================
  -- F. Pagination and second athlete
  -- ===========================================================================
  execute 'set local role authenticated';
  j := public.board_restore(entry1);
  j := public.board_save_athlete(prog_a, ath2, 'contacted');
  entry2 := (j ->> 'id')::uuid;
  j := public.board_list(prog_a, p_limit => 1);
  assert jsonb_array_length(j -> 'items') = 1 and j -> 'next_cursor' <> 'null'::jsonb, 'F1 page 1';
  k := j -> 'items' -> 0 -> 'entry' ->> 'id';
  j := public.board_list(prog_a, p_cursor => j -> 'next_cursor', p_limit => 1);
  assert jsonb_array_length(j -> 'items') = 1 and (j -> 'items' -> 0 -> 'entry' ->> 'id') <> k, 'F2 page 2 differs';
  j := public.board_list(prog_a, p_stage => 'contacted');
  assert jsonb_array_length(j -> 'items') = 1 and (j -> 'items' -> 0 -> 'athlete' ->> 'full_name') = 'Board Athlete Two', 'F3 stage filter';
  execute 'reset role';

  -- ===========================================================================
  -- G. Direct writes are not allowed; legacy insert closed
  -- ===========================================================================
  execute 'set local role authenticated';
  err := null;
  begin insert into public.program_board_entries (program_id, athlete_id) values (prog_a, ath2);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err is not null, 'G1 direct insert refused (RPC only)';
  err := null;
  begin update public.program_board_entries set stage = 'offered' where id = entry2;
  exception when others then get stacked diagnostics err = message_text; end;
  select stage into k from public.program_board_entries where id = entry2;
  assert k = 'contacted', 'G2 direct update has no effect';
  err := null;
  begin insert into public.coach_saved_athletes (coach_user_id, athlete_id) values (coach1, ath2);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err is not null, 'G3 legacy coach_saved_athletes insert closed';
  execute 'reset role';

  -- Cleanup --------------------------------------------------------------------
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  delete from public.notifications where user_id in (coach1, coach2, coach3, admin_id, ath1_user, ath2_user, guardian_user);
  delete from public.notifications where type like 'coach_%' and body like '%PB Test University%';
  -- Board rows first: the users' cascade would SET NULL saved_by/assigned_to on
  -- rows created in this transaction while their athlete is being deleted.
  delete from public.program_board_entries where program_id in (prog_a, prog_b);
  delete from auth.users where id in (admin_id, coach1, coach2, coach3, ath1_user, ath2_user, guardian_user);
  delete from public.recruiting_programs where id in (prog_a, prog_b);
end $$;

select 'ALL PROGRAM BOARD TESTS PASSED' as result;
