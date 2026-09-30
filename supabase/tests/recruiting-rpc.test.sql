-- =============================================================================
-- Recruiting Rules Engine — RPC tests (the path the iOS app calls).
--
-- Run:   scripts/db-query.sh < supabase/tests/recruiting-rpc.test.sql
-- Pass:  final row reads "ALL RECRUITING RPC TESTS PASSED".
--
-- Exercises evaluate_recruiting_action as a signed-in athlete by setting the
-- JWT claims PostgREST would set, so authorization, athlete-fact resolution
-- and the client_supplied context label are all covered. Fixtures roll back
-- on any failed assert (single DO block).
-- =============================================================================

do $$
declare
  athlete_user uuid := gen_random_uuid();
  other_user uuid := gen_random_uuid();
  athlete_id uuid;
  d jsonb;
  err text;
begin
  insert into auth.users (id, email, raw_user_meta_data, aud, role)
  values
    (athlete_user, 'rpc-' || athlete_user || '@recruiting-test.invalid',
     '{"signup_role": "athlete", "full_name": "RPC Test Athlete", "date_of_birth": "2009-01-01"}'::jsonb,
     'authenticated', 'authenticated'),
    (other_user, 'rpc2-' || other_user || '@recruiting-test.invalid',
     '{"signup_role": "athlete", "full_name": "Other Athlete", "date_of_birth": "2009-01-01"}'::jsonb,
     'authenticated', 'authenticated');

  update public.athletes set grad_year = 2029, sport_gender = 'womens'
  where user_id = athlete_user returning id into athlete_id;
  assert athlete_id is not null, 'fixture athlete missing';

  -- Act as the athlete (what PostgREST does for a bearer token).
  perform set_config('request.jwt.claims',
    json_build_object('sub', athlete_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', athlete_user::text, true);

  -- 1. Informational D1 evaluation for own athlete, fixed date before June 1 2027
  d := public.evaluate_recruiting_action(
    athlete_id, 'coach_send_recruiting_electronic_correspondence', null, 'NCAA', 'D1',
    '2027-05-31 12:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'prohibited', '1 status: ' || d::text;
  assert d ->> 'context_source' = 'client_supplied', '1 context_source: ' || (d ->> 'context_source');
  assert d ->> 'sport_gender' = 'womens', '1 gender should come from the athletes row';
  assert d ->> 'next_permitted_on' = '2027-06-01', '1 next: ' || (d ->> 'next_permitted_on');
  assert d ->> 'source_reference' like 'Bylaw 13.4.1.6%', '1 source';

  -- 2. Same athlete after the date → permitted_with_restrictions (women's July caveat)
  d := public.evaluate_recruiting_action(
    athlete_id, 'coach_send_recruiting_electronic_correspondence', null, 'NCAA', 'D1',
    '2027-06-01 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'permitted_with_restrictions', '2 status: ' || d::text;

  -- 3. D2 → needs_review, no rule attached
  d := public.evaluate_recruiting_action(
    athlete_id, 'coach_send_recruiting_electronic_correspondence', null, 'NCAA', 'D2', now());
  assert d ->> 'status' = 'needs_review', '3 status: ' || d::text;
  assert (d ->> 'rule_id') is null, '3 no rule';

  -- 4. Athlete outreach → permitted
  d := public.evaluate_recruiting_action(athlete_id, 'athlete_send_intro_message', null, 'NCAA', 'D1', now());
  assert d ->> 'status' = 'permitted', '4 status: ' || d::text;

  -- 5. No governing body supplied → needs_review with missing program context
  d := public.evaluate_recruiting_action(athlete_id, 'coach_send_recruiting_electronic_correspondence', null, null, null, now());
  assert d ->> 'status' = 'needs_review', '5 status: ' || d::text;
  assert d -> 'missing_context' ? 'program.governing_body', '5 missing';

  -- 6. Someone else's athlete → not authorized
  perform set_config('request.jwt.claims',
    json_build_object('sub', other_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', other_user::text, true);
  err := null;
  begin
    d := public.evaluate_recruiting_action(athlete_id, 'athlete_send_intro_message', null, 'NCAA', 'D1', now());
  exception when others then
    get stacked diagnostics err = message_text;
  end;
  assert err = 'not authorized', '6 expected not authorized, got: ' || coalesce(err, '<none>');

  -- 7. Signed out → not authenticated
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
  err := null;
  begin
    d := public.evaluate_recruiting_action(athlete_id, 'athlete_send_intro_message', null, 'NCAA', 'D1', now());
  exception when others then
    get stacked diagnostics err = message_text;
  end;
  assert err = 'not authenticated', '7 expected not authenticated, got: ' || coalesce(err, '<none>');

  delete from auth.users where id in (athlete_user, other_user);
end $$;

select 'ALL RECRUITING RPC TESTS PASSED' as result;
