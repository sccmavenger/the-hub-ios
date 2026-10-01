-- =============================================================================
-- Coach Workspace 2A — media paths (015) + security foundation (016).
--
-- Run:   scripts/db-query.sh < supabase/tests/coach-workspace-security.test.sql
-- Pass:  final row reads "ALL COACH WORKSPACE SECURITY TESTS PASSED".
--
-- Fixtures (all @cw-test.invalid, removed at the end): two verified programs
-- (men's A, women's B), coach1 on A, coach2 on A (colleague), coach3 on B,
-- coach4 approved then suspended, an admin, two published men's athletes
-- (one near, one far), one unpublished, one women's, a guardian who blocks
-- coach1. Runs each scenario as the `authenticated` role with JWT claims so
-- RLS, not just function checks, is exercised.
-- =============================================================================

do $$
declare
  admin_id uuid := gen_random_uuid();
  coach1 uuid := gen_random_uuid();   -- program A, blocked by athlete_near's guardian
  coach2 uuid := gen_random_uuid();   -- program A colleague
  coach3 uuid := gen_random_uuid();   -- program B (women's)
  coach4 uuid := gen_random_uuid();   -- program A, suspended later
  ath_near_user uuid := gen_random_uuid();
  ath_far_user uuid := gen_random_uuid();
  ath_unpub_user uuid := gen_random_uuid();
  ath_w_user uuid := gen_random_uuid();
  guardian_user uuid := gen_random_uuid();
  ath_near uuid; ath_far uuid; ath_unpub uuid; ath_w uuid;
  prog_a uuid; prog_b uuid;
  mem4 uuid;
  j jsonb;
  err text;
  n integer;
  k text;
  photo_obj text;
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);

  -- Fixtures -------------------------------------------------------------------
  insert into auth.users (id, email, raw_user_meta_data, aud, role) values
    (admin_id, 'admin-' || admin_id || '@cw-test.invalid', '{}'::jsonb, 'authenticated', 'authenticated');
  insert into public.user_roles (user_id, role) values (admin_id, 'admin');

  insert into auth.users (id, email, raw_user_meta_data, aud, role) values
    (coach1, 'c1-' || coach1 || '@cw-test.invalid', '{"signup_role":"coach","full_name":"Coach One","institution":"CW Test University","governing_body":"NCAA","division":"D1","sport_gender":"mens"}'::jsonb, 'authenticated', 'authenticated'),
    (coach2, 'c2-' || coach2 || '@cw-test.invalid', '{"signup_role":"coach","full_name":"Coach Two","institution":"CW Test University","governing_body":"NCAA","division":"D1","sport_gender":"mens"}'::jsonb, 'authenticated', 'authenticated'),
    (coach3, 'c3-' || coach3 || '@cw-test.invalid', '{"signup_role":"coach","full_name":"Coach Three","institution":"CW Test University","governing_body":"NCAA","division":"D1","sport_gender":"womens"}'::jsonb, 'authenticated', 'authenticated'),
    (coach4, 'c4-' || coach4 || '@cw-test.invalid', '{"signup_role":"coach","full_name":"Coach Four","institution":"CW Test University","governing_body":"NCAA","division":"D1","sport_gender":"mens"}'::jsonb, 'authenticated', 'authenticated'),
    (ath_near_user, 'an-' || ath_near_user || '@cw-test.invalid', '{"signup_role":"athlete","full_name":"Near Athlete","date_of_birth":"2009-03-01"}'::jsonb, 'authenticated', 'authenticated'),
    (ath_far_user, 'af-' || ath_far_user || '@cw-test.invalid', '{"signup_role":"athlete","full_name":"Far Athlete","date_of_birth":"2005-03-01"}'::jsonb, 'authenticated', 'authenticated'),
    (ath_unpub_user, 'au-' || ath_unpub_user || '@cw-test.invalid', '{"signup_role":"athlete","full_name":"Hidden Athlete","date_of_birth":"2005-03-01"}'::jsonb, 'authenticated', 'authenticated'),
    (ath_w_user, 'aw-' || ath_w_user || '@cw-test.invalid', '{"signup_role":"athlete","full_name":"Womens Athlete","date_of_birth":"2005-03-01"}'::jsonb, 'authenticated', 'authenticated'),
    (guardian_user, 'g-' || guardian_user || '@cw-test.invalid', '{"signup_role":"parent","full_name":"Near Guardian"}'::jsonb, 'authenticated', 'authenticated');

  select id into ath_near from public.athletes where user_id = ath_near_user;
  select id into ath_far from public.athletes where user_id = ath_far_user;
  select id into ath_unpub from public.athletes where user_id = ath_unpub_user;
  select id into ath_w from public.athletes where user_id = ath_w_user;

  -- Near athlete: St. Louis, minor with guardian consent; far: Seattle; women's: St. Louis
  update public.athletes set sport_gender = 'mens', grad_year = 2027, position = 'Point Guard', height_inches = 74, gpa = 3.6,
    high_school = 'CW High', hometown = 'St. Louis', state = 'MO', zip_code = '63101', latitude = 38.63, longitude = -90.20,
    sat_score = 1200, ncaa_id = '1234567890', guardian_consent_at = now(), guardian_consent_name = 'Near Guardian',
    guardian_consent_email = 'g@cw-test.invalid', profile_photo_path = ath_near_user::text || '/profile.jpg'
    where id = ath_near;
  insert into public.athlete_guardians (athlete_id, user_id, relationship) values (ath_near, guardian_user, 'parent');
  update public.athletes set sport_gender = 'mens', grad_year = 2026, position = 'Center', height_inches = 82, gpa = 3.0,
    state = 'WA', latitude = 47.61, longitude = -122.33 where id = ath_far;
  update public.athletes set sport_gender = 'mens', grad_year = 2026, state = 'MO', latitude = 38.63, longitude = -90.20 where id = ath_unpub;
  update public.athletes set sport_gender = 'womens', grad_year = 2027, state = 'MO', latitude = 38.63, longitude = -90.20 where id = ath_w;
  update public.athletes set is_published = true where id in (ath_near, ath_far, ath_w);

  insert into public.athlete_contacts (athlete_id, athlete_email, guardian_name, guardian_phone)
  values (ath_near, 'near@cw-test.invalid', 'Near Guardian', '555-0100');
  insert into public.athlete_events (athlete_id, event_date, opponent) values (ath_near, current_date + 3, 'Rival HS');
  photo_obj := ath_near_user::text || '/gallery/cwtest.jpg';
  insert into public.athlete_photos (athlete_id, url, storage_path) values (ath_near, 'legacy', photo_obj);
  -- A storage object for the photo and an unrelated sibling object in the same folder
  insert into storage.objects (bucket_id, name, owner, metadata) values
    ('athlete-media', photo_obj, ath_near_user, '{}'::jsonb),
    ('athlete-media', ath_near_user::text || '/gallery/unreferenced.jpg', ath_near_user, '{}'::jsonb);

  insert into public.recruiting_programs (institution_name, normalized_institution_name, governing_body, division, sport, sport_gender, verified_at, active)
  values ('CW Test University', 'cw test university ' || coach1, 'NCAA', 'D1', 'basketball', 'mens', now(), true) returning id into prog_a;
  insert into public.recruiting_programs (institution_name, normalized_institution_name, governing_body, division, sport, sport_gender, verified_at, active)
  values ('CW Test University', 'cw test university w ' || coach1, 'NCAA', 'D1', 'basketball', 'womens', now(), true) returning id into prog_b;

  insert into public.coach_program_memberships (coach_user_id, program_id, status, verified_at, title, membership_role) values
    (coach1, prog_a, 'verified', now(), 'Assistant Coach', 'assistant_coach'),
    (coach2, prog_a, 'verified', now(), 'Head Coach', 'head_coach'),
    (coach3, prog_b, 'verified', now(), 'Head Coach', 'head_coach');
  insert into public.coach_program_memberships (coach_user_id, program_id, status, verified_at)
    values (coach4, prog_a, 'verified', now()) returning id into mem4;
  -- membership triggers derived the coach role
  select count(*) into n from public.user_roles where role = 'coach' and user_id in (coach1, coach2, coach3, coach4);
  assert n = 4, 'fixture: coach roles derived, got ' || n;

  -- Guardian of near athlete blocks coach1
  insert into public.user_blocks (blocker_user_id, blocked_user_id) values (guardian_user, coach1);

  -- ===========================================================================
  -- A. Admin exclusivity (D24)
  -- ===========================================================================
  err := null;
  begin insert into public.user_roles (user_id, role) values (admin_id, 'athlete');
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'admin accounts cannot hold other roles', 'A1 admin→athlete refused: ' || coalesce(err, '<none>');
  err := null;
  begin insert into public.user_roles (user_id, role) values (coach2, 'admin');
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'admin accounts cannot hold other roles', 'A2 coach→admin refused: ' || coalesce(err, '<none>');
  err := null;
  begin
    insert into public.coach_program_memberships (coach_user_id, program_id, status, verified_at) values (admin_id, prog_a, 'verified', now());
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'admin accounts cannot hold other roles', 'A3 verified membership for an admin cannot grant coach: ' || coalesce(err, '<none>');

  -- ===========================================================================
  -- B. Coach2 (unblocked, program A): search, detail, allowlist, pagination
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', coach2, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach2::text, true);
  execute 'set local role authenticated';

  select count(*) into n from public.athletes;
  assert n = 0, 'B0 coaches do not read the athletes table, saw ' || n;

  -- Fixture names all contain "Athlete"; the name query keeps real published accounts out of the totals.
  j := public.search_published_athletes(prog_a, p_query => 'athlete');
  assert (j ->> 'total')::int = 2, 'B1 two published mens athletes, got ' || (j ->> 'total');
  assert j -> 'next_cursor' is null or (j -> 'next_cursor') = 'null'::jsonb, 'B1 single page';
  -- Allowlist: forbidden keys absent from every card
  select count(*) into n from jsonb_array_elements(j -> 'items') it
    where it ? 'date_of_birth' or it ? 'sat_score' or it ? 'act_score' or it ? 'ncaa_id' or it ? 'zip_code'
       or it ? 'latitude' or it ? 'longitude' or it ? 'user_id' or it ? 'guardian_consent_email' or it ? 'guardian_consent_name' or it ? 'email';
  assert n = 0, 'B2 forbidden columns leaked in search payload';
  select count(*) into n from jsonb_array_elements(j -> 'items') it where it ->> 'full_name' = 'Hidden Athlete';
  assert n = 0, 'B3 unpublished athlete absent';
  select count(*) into n from jsonb_array_elements(j -> 'items') it where it ->> 'full_name' = 'Womens Athlete';
  assert n = 0, 'B4 other gender absent (program is mens)';

  -- Radius from St. Louis: 100 mi keeps Near, drops Far
  j := public.search_published_athletes(prog_a, p_query => 'athlete', p_center_lat => 38.63, p_center_lng => -90.20, p_radius_miles => 100);
  assert (j ->> 'total')::int = 1 and (j -> 'items' -> 0 ->> 'full_name') = 'Near Athlete', 'B5 radius filter';
  assert (j -> 'items' -> 0 ->> 'distance_miles')::int = 0, 'B5 distance rounded to 5: ' || (j -> 'items' -> 0 ->> 'distance_miles');
  j := public.search_published_athletes(prog_a, p_query => 'athlete', p_center_lat => 38.63, p_center_lng => -90.20, p_radius_miles => 250);
  assert (j ->> 'total')::int = 1, 'B5b Seattle is > 250 mi';
  -- Filters
  j := public.search_published_athletes(prog_a, p_query => 'athlete', p_positions => array['guard']);
  assert (j ->> 'total')::int = 1 and (j -> 'items' -> 0 ->> 'position') = 'Point Guard', 'B6 position ilike';
  j := public.search_published_athletes(prog_a, p_query => 'athlete', p_grad_years => array[2026]);
  assert (j ->> 'total')::int = 1 and (j -> 'items' -> 0 ->> 'full_name') = 'Far Athlete', 'B7 grad year';
  j := public.search_published_athletes(prog_a, p_query => 'athlete', p_min_height_in => 80);
  assert (j ->> 'total')::int = 1, 'B8 min height';
  j := public.search_published_athletes(prog_a, p_query => 'athlete', p_min_gpa => 3.5);
  assert (j ->> 'total')::int = 1 and (j -> 'items' -> 0 ->> 'full_name') = 'Near Athlete', 'B9 min gpa';
  j := public.search_published_athletes(prog_a, p_query => 'athlete', p_playing_within => '7d');
  assert (j ->> 'total')::int = 1 and (j -> 'items' -> 0 ->> 'full_name') = 'Near Athlete', 'B10 playing within 7d';
  j := public.search_published_athletes(prog_a, p_query => 'athlete', p_states => array['wa']);
  assert (j ->> 'total')::int = 1 and (j -> 'items' -> 0 ->> 'state') = 'WA', 'B11 state filter';
  j := public.search_published_athletes(prog_a, p_query => 'far');
  assert (j ->> 'total')::int = 1, 'B12 name query';
  -- Pagination: page size 1 → two pages, cursor stable, no duplicates
  j := public.search_published_athletes(prog_a, p_query => 'athlete', p_limit => 1);
  assert jsonb_array_length(j -> 'items') = 1 and j -> 'next_cursor' is not null and (j -> 'next_cursor') <> 'null'::jsonb, 'B13 page 1 has cursor';
  k := j -> 'items' -> 0 ->> 'full_name';
  j := public.search_published_athletes(prog_a, p_query => 'athlete', p_cursor => j -> 'next_cursor', p_limit => 1);
  assert jsonb_array_length(j -> 'items') = 1 and (j -> 'items' -> 0 ->> 'full_name') <> k, 'B13 page 2 differs';
  assert (j -> 'next_cursor') = 'null'::jsonb or j -> 'next_cursor' is null, 'B13 page 2 is last';
  err := null;
  begin j := public.search_published_athletes(prog_a, p_radius_miles => 77);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'invalid p_radius_miles', 'B14 radius validated';

  -- Detail: contact locked (no save), events, photos with paths only
  j := public.coach_athlete_detail(prog_a, ath_near);
  assert (j -> 'athlete' ->> 'full_name') = 'Near Athlete', 'B15 detail';
  assert not (j -> 'athlete' ? 'date_of_birth'), 'B15 no DOB in detail';
  assert (j ->> 'contact_unlocked')::boolean = false and j -> 'contact' = 'null'::jsonb, 'B16 contact locked before save';
  assert jsonb_array_length(j -> 'upcoming_events') = 1, 'B17 upcoming events';
  assert (j -> 'photos' -> 0 ->> 'storage_path') = photo_obj, 'B18 photo path';
  assert not (j -> 'photos' -> 0 ? 'url'), 'B18 no legacy url in coach payload';
  -- Saving to the program board (017) unlocks contact
  j := public.board_save_athlete(prog_a, ath_near);
  j := public.coach_athlete_detail(prog_a, ath_near);
  assert (j ->> 'contact_unlocked')::boolean and (j -> 'contact' ->> 'athlete_email') = 'near@cw-test.invalid', 'B19 contact after save';
  -- 018: search items carry board_stage + next_event_date
  j := public.search_published_athletes(prog_a, p_query => 'near');
  assert (j -> 'items' -> 0 ->> 'board_stage') = 'watching', 'B19b board_stage in search: ' || coalesce(j -> 'items' -> 0 ->> 'board_stage', '<null>');
  assert (j -> 'items' -> 0 ->> 'next_event_date')::date = current_date + 3, 'B19b next_event_date in search';
  j := public.search_published_athletes(prog_a, p_query => 'far');
  assert j -> 'items' -> 0 -> 'board_stage' = 'null'::jsonb, 'B19c unsaved athlete has null board_stage';
  -- Unpublished / wrong gender / unknown → uniform 'not found'
  err := null; begin j := public.coach_athlete_detail(prog_a, ath_unpub); exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not found', 'B20 unpublished → not found';
  err := null; begin j := public.coach_athlete_detail(prog_a, ath_w); exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not found', 'B21 other gender → not found';
  -- Forged program (coach2 is not on B)
  err := null; begin j := public.search_published_athletes(prog_b); exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not authorized', 'B22 forged program id';
  -- Staff roster
  j := public.program_staff(prog_a);
  assert jsonb_array_length(j) = 3, 'B23 three active staff on A, got ' || jsonb_array_length(j);
  select count(*) into n from jsonb_array_elements(j) s where s ? 'email' or s ? 'phone';
  assert n = 0, 'B23 roster carries no contact info';
  assert (j -> 0 ->> 'membership_role') = 'head_coach', 'B23 head coach first';
  -- Storage: coach reads the referenced object, not the unreferenced sibling
  select count(*) into n from storage.objects where bucket_id = 'athlete-media' and name = photo_obj;
  assert n = 1, 'B24 coach can read the referenced photo object';
  select count(*) into n from storage.objects where bucket_id = 'athlete-media' and name = ath_near_user::text || '/gallery/unreferenced.jpg';
  assert n = 0, 'B25 unreferenced sibling object hidden (folder leak closed)';
  -- Photos table (RLS) readable for published athlete
  select count(*) into n from public.athlete_photos where athlete_id = ath_near;
  assert n = 1, 'B26 photos select for coach';
  -- Home summary works
  j := public.coach_home_summary(prog_a);
  assert (j ->> 'unread_threads')::int = 0, 'B27 home summary';
  execute 'reset role';

  -- ===========================================================================
  -- C. Coach1 (blocked by the guardian) sees nothing of Near Athlete
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', coach1, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach1::text, true);
  execute 'set local role authenticated';
  j := public.search_published_athletes(prog_a, p_query => 'athlete');
  select count(*) into n from jsonb_array_elements(j -> 'items') it where it ->> 'full_name' = 'Near Athlete';
  assert n = 0 and (j ->> 'total')::int = 1, 'C1 blocked coach does not see the athlete in search';
  err := null; begin j := public.coach_athlete_detail(prog_a, ath_near); exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not found', 'C2 blocked coach detail → not found';
  select count(*) into n from public.athlete_photos where athlete_id = ath_near;
  assert n = 0, 'C3 blocked coach photos hidden';
  select count(*) into n from public.athlete_events where athlete_id = ath_near;
  assert n = 0, 'C4 blocked coach events hidden';
  select count(*) into n from storage.objects where bucket_id = 'athlete-media' and name = photo_obj;
  assert n = 0, 'C5 blocked coach storage hidden';
  j := public.board_save_athlete(prog_a, ath_far);  -- unrelated save still fine
  -- The program's board already holds Near Athlete (coach2 saved them above);
  -- the blocked colleague still gets no contact details.
  select count(*) into n from public.athlete_contacts where athlete_id = ath_near;
  assert n = 0, 'C6 blocked coach contacts hidden despite the program''s board entry';
  -- Blocked coach cannot message (guardian block now counts in the trigger)
  err := null;
  begin insert into public.messages (athlete_id, coach_user_id, sender_user_id, body) values (ath_near, coach1, coach1, 'hi');
  exception when others then get stacked diagnostics err = message_text; end;
  assert err is not null, 'C7 blocked coach cannot message';
  execute 'reset role';

  -- ===========================================================================
  -- D. Coach3 (women's program) cannot reach men's athletes; sees the women's one
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', coach3, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach3::text, true);
  execute 'set local role authenticated';
  j := public.search_published_athletes(prog_b);
  assert (j ->> 'total')::int = 1 and (j -> 'items' -> 0 ->> 'full_name') = 'Womens Athlete', 'D1 womens program sees womens athlete only';
  err := null; begin j := public.coach_athlete_detail(prog_b, ath_near); exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not found', 'D2 cross-gender detail denied';
  err := null; begin j := public.program_staff(prog_a); exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not authorized', 'D3 cross-program roster denied';
  -- Saved search must be program-scoped to a program the coach holds
  err := null;
  begin insert into public.coach_saved_searches (coach_user_id, name, filters, program_id) values (coach3, 'x', '{}'::jsonb, prog_a);
  exception when others then get stacked diagnostics err = message_text; end;
  assert err is not null, 'D4 saved search for a program the coach lacks is refused';
  insert into public.coach_saved_searches (coach_user_id, name, filters, program_id) values (coach3, 'guards', '{"positions":["guard"]}'::jsonb, prog_b);
  execute 'reset role';

  -- ===========================================================================
  -- E. Suspension (D5) revokes everything in-session
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', admin_id, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  execute 'set local role authenticated';
  j := public.set_coach_membership_status(mem4, 'suspended');
  execute 'reset role';
  perform set_config('request.jwt.claims', json_build_object('sub', coach4, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach4::text, true);
  execute 'set local role authenticated';
  err := null; begin j := public.search_published_athletes(prog_a); exception when others then get stacked diagnostics err = message_text; end;
  assert err = 'not authorized', 'E1 suspended coach search denied';
  select count(*) into n from public.athlete_photos where athlete_id = ath_far;
  assert n = 0, 'E2 suspended coach photos denied';
  select count(*) into n from storage.objects where bucket_id = 'athlete-media';
  assert n = 0, 'E3 suspended coach storage denied';
  execute 'reset role';
  -- and the roster no longer lists them
  perform set_config('request.jwt.claims', json_build_object('sub', coach2, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', coach2::text, true);
  execute 'set local role authenticated';
  j := public.program_staff(prog_a);
  assert jsonb_array_length(j) = 2, 'E4 suspended staff drop off the roster, got ' || jsonb_array_length(j);
  execute 'reset role';

  -- ===========================================================================
  -- F. Athlete side: oracle closed, recipient check, guardian media read, labels
  -- ===========================================================================
  perform set_config('request.jwt.claims', json_build_object('sub', ath_far_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', ath_far_user::text, true);
  execute 'set local role authenticated';
  assert public.athlete_is_published(ath_near) = false, 'F1 publication oracle closed for unrelated athlete';
  assert public.athlete_is_published(ath_far) = true, 'F1 own athlete still true';
  err := null;
  begin insert into public.messages (athlete_id, coach_user_id, sender_user_id, body) values (ath_far, guardian_user, ath_far_user, 'hi');
  exception when others then get stacked diagnostics err = message_text; end;
  assert err is not null, 'F2 athlete cannot open a thread with a non-coach';
  insert into public.messages (athlete_id, coach_user_id, sender_user_id, body) values (ath_far, coach2, ath_far_user, 'hello coach');
  -- directory names: coach2 (shared thread) resolves with the verified program; coach3 (no relation) does not
  select count(*) into n from public.coach_directory_names(array[coach2, coach3]);
  assert n = 1, 'F3 directory names only for related coaches, got ' || n;
  select college into k from public.coach_directory_names(array[coach2]);
  assert k = 'CW Test University', 'F3 label from verified program: ' || coalesce(k, '<null>');
  execute 'reset role';

  perform set_config('request.jwt.claims', json_build_object('sub', guardian_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', guardian_user::text, true);
  execute 'set local role authenticated';
  select count(*) into n from storage.objects where bucket_id = 'athlete-media' and name = photo_obj;
  assert n = 1, 'F4 guardian reads the managed athlete''s object via row-based policy';
  select count(*) into n from storage.objects where bucket_id = 'athlete-media' and name = ath_near_user::text || '/gallery/unreferenced.jpg';
  assert n = 0, 'F5 guardian does not read unreferenced objects in a folder they do not own';
  execute 'reset role';

  -- ===========================================================================
  -- G. Interest notification routes by verified membership, not claim (D6)
  -- ===========================================================================
  delete from public.notifications where type = 'interest' and user_id in (coach1, coach2, coach3, coach4);
  perform public.notify_coaches_of_interest(ath_far, 'CW Test University');
  select count(*) into n from public.notifications where type = 'interest' and user_id = coach2;
  assert n = 1, 'G1 verified mens staff notified';
  select count(*) into n from public.notifications where type = 'interest' and user_id = coach3;
  assert n = 0, 'G2 womens program not notified for a mens athlete';
  select count(*) into n from public.notifications where type = 'interest' and user_id = coach4;
  assert n = 0, 'G3 suspended coach not notified';
  perform public.notify_coaches_of_interest(ath_near, 'CW Test University');
  select count(*) into n from public.notifications where type = 'interest' and user_id = coach1 and body like 'Near Athlete%';
  assert n = 0, 'G4 blocked coach not notified for the athlete whose guardian blocked them';
  select count(*) into n from public.notifications where type = 'interest' and user_id = coach2 and body like 'Near Athlete%';
  assert n = 1, 'G5 unblocked colleague still notified';

  -- Cleanup --------------------------------------------------------------------
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  delete from public.notifications where user_id in (coach1, coach2, coach3, coach4, admin_id, ath_near_user, ath_far_user, guardian_user);
  delete from public.notifications where type like 'coach_%' and body like '%CW Test University%';
  -- storage.protect_delete() blocks direct deletes unless this GUC is set; the
  -- fixture rows are metadata-only (no bytes were ever uploaded).
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects where bucket_id = 'athlete-media' and name like ath_near_user::text || '/%';
  perform set_config('storage.allow_delete_query', 'false', true);
  delete from public.program_board_entries where program_id in (prog_a, prog_b);
  delete from auth.users where id in (admin_id, coach1, coach2, coach3, coach4, ath_near_user, ath_far_user, ath_unpub_user, ath_w_user, guardian_user);
  delete from public.recruiting_programs where id in (prog_a, prog_b);
end $$;

select 'ALL COACH WORKSPACE SECURITY TESTS PASSED' as result;
