-- =============================================================================
-- Coach Workspace 2F — notifications + saved-search alerts (020).
--
-- Run:   scripts/db-query.sh < supabase/tests/notifications-alerts.test.sql
-- Pass:  final row reads "ALL NOTIFICATIONS/ALERTS TESTS PASSED".
-- =============================================================================

do $$
declare
  admin_id uuid := gen_random_uuid();
  coach1 uuid := gen_random_uuid();
  ath1_user uuid := gen_random_uuid();
  ath2_user uuid := gen_random_uuid();
  ath1 uuid; ath2 uuid;
  prog_a uuid; mem1 uuid; ss uuid;
  j jsonb;
  n integer;
  k text;
  err text;
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  insert into auth.users (id, email, raw_user_meta_data, aud, role) values
    (admin_id, 'admin-' || admin_id || '@na-test.invalid', '{}'::jsonb, 'authenticated', 'authenticated');
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');
  insert into auth.users (id, email, raw_user_meta_data, aud, role) values
    (coach1, 'c1-' || coach1 || '@na-test.invalid', '{"signup_role":"coach","full_name":"Alert Coach","institution":"NA Test University","governing_body":"NCAA","division":"D1","sport_gender":"mens"}'::jsonb, 'authenticated', 'authenticated'),
    (ath1_user, 'a1-' || ath1_user || '@na-test.invalid', '{"signup_role":"athlete","full_name":"Alert Guard One","date_of_birth":"2005-01-01"}'::jsonb, 'authenticated', 'authenticated'),
    (ath2_user, 'a2-' || ath2_user || '@na-test.invalid', '{"signup_role":"athlete","full_name":"Alert Guard Two","date_of_birth":"2005-01-01"}'::jsonb, 'authenticated', 'authenticated');
  select id into ath1 from public.athletes where user_id = ath1_user;
  select id into ath2 from public.athletes where user_id = ath2_user;
  update public.athletes set sport_gender = 'mens', grad_year = 2027, position = 'Point Guard', is_published = true where id = ath1;
  update public.athletes set sport_gender = 'mens', grad_year = 2027, position = 'Shooting Guard' where id = ath2;   -- unpublished for now

  insert into public.recruiting_programs (institution_name, normalized_institution_name, governing_body, division, sport, sport_gender, verified_at, active)
  values ('NA Test University', 'na test university ' || coach1, 'NCAA', 'D1', 'basketball', 'mens', now(), true) returning id into prog_a;
  insert into public.coach_program_memberships (coach_user_id, program_id, status, verified_at)
    values (coach1, prog_a, 'verified', now()) returning id into mem1;
  delete from public.notifications where user_id in (coach1, ath1_user, ath2_user);

  -- ===========================================================================
  -- A. Typed destinations from legacy links; read helpers
  -- ===========================================================================
  insert into public.notifications (user_id, type, title, body, link)
  values (coach1, 'test', 'Legacy link', 'x', '/a/' || ath1);
  select destination ->> 'type' into k from public.notifications where user_id = coach1 and title = 'Legacy link';
  assert k = 'athlete', 'A1 legacy /a/{id} → athlete destination: ' || coalesce(k, '<null>');
  select (destination ->> 'athlete_id')::uuid = ath1 into k from public.notifications where user_id = coach1 and title = 'Legacy link';
  assert k::boolean, 'A1 athlete id carried';
  insert into public.notifications (user_id, type, title, body, link) values (coach1, 'test', 'Legacy msgs', 'x', '/coaches/messages');
  select destination ->> 'type' into k from public.notifications where user_id = coach1 and title = 'Legacy msgs';
  assert k = 'messages', 'A2 legacy messages link mapped';

  perform set_config('request.jwt.claims', json_build_object('sub', coach1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach1::text, true);
  execute 'set local role authenticated';
  assert public.unread_notification_count() = 2, 'A3 unread count = 2, got ' || public.unread_notification_count();
  n := public.mark_notifications_read(array[(select id from public.notifications where user_id = coach1 and title = 'Legacy link')]);
  assert n = 1 and public.unread_notification_count() = 1, 'A4 mark one read';
  n := public.mark_notifications_read();
  assert n = 1 and public.unread_notification_count() = 0, 'A5 mark all read';
  execute 'reset role';
  -- another user's rows are untouched by mark-all
  perform set_config('request.jwt.claims', json_build_object('sub', ath1_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', ath1_user::text, true);
  execute 'set local role authenticated';
  select count(*) into n from public.notifications;
  assert n = 0, 'A6 athlete sees none of the coach rows';
  execute 'reset role';

  -- ===========================================================================
  -- B. Saved-search alerts: baseline, then only new matches, no duplicates
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', coach1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach1::text, true);
  execute 'set local role authenticated';
  insert into public.coach_saved_searches (coach_user_id, program_id, name, filters, alerts_enabled)
    values (coach1, prog_a, 'guards 27', '{"positions":["guard"],"grad_years":[2027]}'::jsonb, true) returning id into ss;
  execute 'reset role';

  j := public.run_saved_search_alerts();
  assert (j ->> 'seeded')::int >= 1, 'B1 first run seeds: ' || j::text;
  select cardinality(notified_athlete_ids) into n from public.coach_saved_searches where id = ss;
  assert n = 1, 'B1 baseline holds the published guard, got ' || n;
  select count(*) into n from public.notifications where user_id = coach1 and type = 'saved_search';
  assert n = 0, 'B1 no alert on the seeding run';

  j := public.run_saved_search_alerts();
  select count(*) into n from public.notifications where user_id = coach1 and type = 'saved_search';
  assert n = 0, 'B2 nothing new, nothing sent';

  update public.athletes set is_published = true where id = ath2;   -- a new match appears
  j := public.run_saved_search_alerts();
  select count(*) into n from public.notifications where user_id = coach1 and type = 'saved_search';
  assert n = 1, 'B3 one alert for the new match, got ' || n;
  select title, destination ->> 'type' into k, err from public.notifications where user_id = coach1 and type = 'saved_search';
  assert k = '1 new athlete matches “guards 27”', 'B3 title: ' || k;
  assert err = 'saved_search', 'B3 typed destination';
  select body into k from public.notifications where user_id = coach1 and type = 'saved_search';
  assert k = 'Alert Guard Two', 'B3 body names the athlete: ' || k;

  j := public.run_saved_search_alerts();
  select count(*) into n from public.notifications where user_id = coach1 and type = 'saved_search';
  assert n = 1, 'B4 rerun does not duplicate';

  -- Editing filters resets the baseline (next run seeds, no replay)
  execute 'set local role authenticated';
  update public.coach_saved_searches set filters = '{"positions":["guard"]}'::jsonb where id = ss;
  execute 'reset role';
  select notified_athlete_ids is null into k from public.coach_saved_searches where id = ss;
  assert k::boolean, 'B5 filter edit resets baseline';
  j := public.run_saved_search_alerts();
  select count(*) into n from public.notifications where user_id = coach1 and type = 'saved_search';
  assert n = 1, 'B5 reseed run sends nothing';

  -- Blocked athlete never alerts
  insert into public.user_blocks (blocker_user_id, blocked_user_id) values (ath1_user, coach1);
  update public.coach_saved_searches set notified_athlete_ids = '{}'::uuid[] where id = ss;   -- pretend empty baseline
  j := public.run_saved_search_alerts();
  select body into k from public.notifications where user_id = coach1 and type = 'saved_search' order by created_at desc, id desc limit 1;
  select count(*) into n from public.notifications where user_id = coach1 and type = 'saved_search' and body like '%Guard One%';
  assert n = 0, 'B6 blocked athlete excluded from alerts';
  delete from public.user_blocks where blocker_user_id = ath1_user;

  -- Suspended coach: skipped entirely
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';
  j := public.set_coach_membership_status(mem1, 'suspended');
  execute 'reset role';
  select count(*) into n from public.notifications where user_id = coach1 and type = 'saved_search';
  update public.coach_saved_searches set notified_athlete_ids = '{}'::uuid[] where id = ss;
  j := public.run_saved_search_alerts();
  assert (j ->> 'skipped')::int >= 1, 'B7 suspended coach skipped: ' || j::text;
  select count(*) into k from public.notifications where user_id = coach1 and type = 'saved_search';
  assert k::int = n, 'B7 no alert for suspended coach';

  -- Scheduler registered
  select count(*) into n from cron.job where jobname = 'saved-search-alerts';
  assert n = 1, 'B8 cron job scheduled';

  -- Cleanup --------------------------------------------------------------------
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  delete from public.notifications where user_id in (coach1, admin_id, ath1_user, ath2_user);
  delete from public.notifications where type like 'coach_%' and body like '%NA Test University%';
  delete from auth.users where id in (admin_id, coach1, ath1_user, ath2_user);
  delete from public.recruiting_programs where id = prog_a;
end $$;

select 'ALL NOTIFICATIONS/ALERTS TESTS PASSED' as result;
