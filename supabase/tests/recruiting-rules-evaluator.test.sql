-- =============================================================================
-- Recruiting Rules Engine — evaluator tests (spec §29.1, §30).
--
-- Run:   scripts/db-query.sh < supabase/tests/recruiting-rules-evaluator.test.sql
-- Pass:  the final row reads "ALL RECRUITING EVALUATOR TESTS PASSED".
-- Fail:  the API returns the failing ASSERT message; the DO block is one
--        statement, so its TEST fixtures roll back automatically.
--
-- The core evaluator is pure over (ctx, at) + recruiting_rules, so no auth
-- users or athlete rows are needed. Fixed dates and the rule time zone
-- (America/Indiana/Indianapolis) are used throughout; nothing reads now().
-- Fixtures live under governing_body = 'TEST', which no real scope uses.
-- =============================================================================

do $$
declare
  d jsonb;
  mens jsonb := jsonb_build_object(
    'governing_body', 'NCAA', 'division', 'D1', 'sport', 'basketball', 'sport_gender', 'mens',
    'actor_type', 'coach', 'action_type', 'coach_send_recruiting_electronic_correspondence',
    'athlete_grad_year', 2029, 'athlete_academic_calendar_type', 'traditional_us',
    'context_source', 'test'
  );
  womens jsonb;
  test_scope jsonb := jsonb_build_object(
    'governing_body', 'TEST', 'division', 'T1', 'sport', 'basketball', 'sport_gender', 'mens',
    'actor_type', 'coach', 'athlete_grad_year', 2029, 'athlete_academic_calendar_type', 'traditional_us',
    'context_source', 'test'
  );
  test_source uuid := 'c1c2c3d4-0009-4000-8000-000000000001';
  retired_count integer;
begin
  womens := mens || '{"sport_gender": "womens"}'::jsonb;

  -- Fixtures ------------------------------------------------------------------
  delete from public.recruiting_rules where governing_body = 'TEST';
  delete from public.recruiting_rule_sources where governing_body = 'TEST';
  insert into public.recruiting_rule_sources (id, governing_body, title, source_url, source_reference, retrieved_at)
  values (test_source, 'TEST', 'Test fixture source', 'https://example.test/rules', '§test', '2026-09-30T00:00:00Z');

  -- I: two equally specific, contradictory published rules for the same scope.
  insert into public.recruiting_rules
    (rule_key, governing_body, division, sport, sport_gender, actor_type, action_type, decision, enforcement_level,
     plain_english_summary, source_id, effective_from, rule_version, status, last_verified_at)
  values
    ('test.conflict.a', 'TEST', 'T1', 'basketball', 'mens', 'coach', 'test_conflict_action', 'permitted', 'none',
     'A says yes', test_source, '2026-01-01', 1, 'published', '2026-09-30T00:00:00Z'),
    ('test.conflict.b', 'TEST', 'T1', 'basketball', 'mens', 'coach', 'test_conflict_action', 'prohibited', 'hard_block',
     'B says no', test_source, '2026-01-01', 1, 'published', '2026-09-30T00:00:00Z');

  -- J: not yet effective.
  insert into public.recruiting_rules
    (rule_key, governing_body, division, sport, sport_gender, actor_type, action_type, decision, enforcement_level,
     plain_english_summary, source_id, effective_from, rule_version, status, last_verified_at)
  values
    ('test.future', 'TEST', 'T1', 'basketball', 'mens', 'coach', 'test_future_action', 'prohibited', 'hard_block',
     'Future rule', test_source, '2030-01-01', 1, 'published', '2026-09-30T00:00:00Z');

  -- K: retired version preserved; no live version.
  insert into public.recruiting_rules
    (rule_key, governing_body, division, sport, sport_gender, actor_type, action_type, decision, enforcement_level,
     plain_english_summary, source_id, effective_from, effective_until, rule_version, status, last_verified_at)
  values
    ('test.retired', 'TEST', 'T1', 'basketball', 'mens', 'coach', 'test_retired_action', 'prohibited', 'hard_block',
     'Old rule', test_source, '2020-01-01', '2025-12-31', 1, 'retired', '2026-09-30T00:00:00Z');

  -- §30: a dated in-person restriction must not touch an unrelated electronic action.
  insert into public.recruiting_rules
    (rule_key, governing_body, division, sport, sport_gender, actor_type, action_type, decision, decision_after_start,
     enforcement_level, academic_milestone_type, absolute_start_at, absolute_end_at,
     plain_english_summary, source_id, effective_from, rule_version, status, last_verified_at)
  values
    ('test.offcampus.july', 'TEST', 'T1', 'basketball', 'mens', 'coach', 'coach_off_campus_contact', 'prohibited', 'permitted',
     'warning', 'absolute', '2027-07-01 00:00 America/Indiana/Indianapolis', '2027-08-01 00:00 America/Indiana/Indianapolis',
     'No off-campus contact in July (test)', test_source, '2026-01-01', 1, 'published', '2026-09-30T00:00:00Z');
  insert into public.recruiting_rules
    (rule_key, governing_body, division, sport, sport_gender, actor_type, action_type, decision, enforcement_level,
     plain_english_summary, source_id, effective_from, rule_version, status, last_verified_at)
  values
    ('test.electronic.ok', 'TEST', 'T1', 'basketball', 'mens', 'coach', 'coach_send_recruiting_electronic_correspondence',
     'permitted', 'none', 'Electronic OK (test)', test_source, '2026-01-01', 1, 'published', '2026-09-30T00:00:00Z');

  -- Case A: D1 men's, traditional calendar, before June 15 → prohibited / hard block ----
  d := public.recruiting_evaluate_core(mens, '2027-06-14 23:59:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'prohibited', 'A status: ' || d::text;
  assert d ->> 'enforcement' = 'hard_block', 'A enforcement: ' || (d ->> 'enforcement');
  assert d ->> 'rule_key' = 'ncaa.d1.basketball.mens.coach.electronic_correspondence', 'A rule: ' || (d ->> 'rule_key');
  assert d ->> 'source_url' like 'https://web3.ncaa.org/lsdbi/%', 'A source url: ' || (d ->> 'source_url');
  assert d ->> 'source_reference' like 'Bylaw 13.4.1.5%', 'A source ref: ' || (d ->> 'source_reference');
  -- June 15 2027 00:00 Indianapolis (EDT, UTC-4) = 04:00Z
  assert d ->> 'next_permitted_at' = '2027-06-15T04:00:00Z', 'A next: ' || (d ->> 'next_permitted_at');
  assert (d ->> 'last_verified_at') is not null, 'A last_verified_at missing';
  assert d ->> 'action' = 'coach_send_recruiting_electronic_correspondence', 'A action';

  -- Case B: same context at/after opening → permitted ------------------------------
  d := public.recruiting_evaluate_core(mens, '2027-06-15 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'permitted', 'B status: ' || d::text;
  assert d ->> 'enforcement' = 'none', 'B enforcement';
  assert (d ->> 'next_permitted_at') is null, 'B next should be null';
  -- One second earlier is still prohibited (boundary is exact).
  d := public.recruiting_evaluate_core(mens, '2027-06-14 23:59:59 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'prohibited', 'B boundary: ' || (d ->> 'status');

  -- Case C: D1 women's before June 1 → prohibited ----------------------------------
  d := public.recruiting_evaluate_core(womens, '2027-05-31 23:59:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'prohibited', 'C status: ' || d::text;
  assert d ->> 'enforcement' = 'hard_block', 'C enforcement';
  assert d ->> 'next_permitted_at' = '2027-06-01T04:00:00Z', 'C next: ' || (d ->> 'next_permitted_at');
  assert d ->> 'source_reference' like 'Bylaw 13.4.1.6%', 'C source ref: ' || (d ->> 'source_reference');

  -- Case D: D1 women's after June 1 → open, but with the July evaluation-period
  -- caveat (Bylaw 13.1.3.1.5.1), so permitted_with_restrictions rather than the
  -- spec's plain "permitted". Deliberate, documented deviation.
  d := public.recruiting_evaluate_core(womens, '2027-06-01 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'permitted_with_restrictions', 'D status: ' || d::text;
  assert d ->> 'enforcement' = 'informational', 'D enforcement';
  assert d ->> 'user_message' like '%July evaluation periods%', 'D message should mention July';

  -- Case E: nontraditional calendar WITH sophomore completion date uses the exception --
  d := public.recruiting_evaluate_core(
    womens || '{"athlete_academic_calendar_type": "nontraditional", "athlete_sophomore_completed_on": "2027-11-20"}'::jsonb,
    '2027-11-20 12:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'prohibited', 'E1 status: ' || d::text;
  assert d ->> 'rule_key' = 'ncaa.d1.basketball.womens.coach.electronic_correspondence.nontraditional', 'E1 rule: ' || (d ->> 'rule_key');
  -- day after = Nov 21 00:00 Indianapolis (EST, UTC-5) = 05:00Z; no June-1 guess
  assert d ->> 'next_permitted_at' = '2027-11-21T05:00:00Z', 'E1 next: ' || (d ->> 'next_permitted_at');
  d := public.recruiting_evaluate_core(
    womens || '{"athlete_academic_calendar_type": "nontraditional", "athlete_sophomore_completed_on": "2027-11-20"}'::jsonb,
    '2027-11-21 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'permitted_with_restrictions', 'E2 status: ' || d::text;

  -- Case F: nontraditional/unknown calendar without the required fact → needs_review --
  d := public.recruiting_evaluate_core(
    womens || '{"athlete_academic_calendar_type": "nontraditional"}'::jsonb,
    '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'F1 status: ' || d::text;
  assert d -> 'missing_context' ? 'athlete.sophomore_completed_on', 'F1 missing: ' || (d ->> 'missing_context');
  assert d ->> 'enforcement' = 'none', 'F1 enforcement';
  assert (d ->> 'source_url') is not null, 'F1 should still show closest source';
  d := public.recruiting_evaluate_core(
    mens || '{"athlete_academic_calendar_type": "unknown"}'::jsonb,
    '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'F2 status: ' || d::text;
  assert d -> 'missing_context' ? 'athlete_academic_calendar_type', 'F2 missing: ' || (d ->> 'missing_context');
  -- Men's nontraditional electronic correspondence is intentionally unseeded.
  d := public.recruiting_evaluate_core(
    mens || '{"athlete_academic_calendar_type": "nontraditional"}'::jsonb,
    '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'F3 status: ' || d::text;
  -- Calendar type entirely absent from context → unknown, never guessed.
  d := public.recruiting_evaluate_core(mens - 'athlete_academic_calendar_type', '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'F4 status: ' || d::text;
  assert d -> 'missing_context' ? 'athlete_academic_calendar_type', 'F4 missing';

  -- Case G: coach division/governing body missing or unverified → needs_review -------
  d := public.recruiting_evaluate_core(mens - 'division', '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'G1 status: ' || d::text;
  assert d -> 'missing_context' ? 'program.division', 'G1 missing: ' || (d ->> 'missing_context');
  d := public.recruiting_evaluate_core(mens - 'governing_body', '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'G2 status: ' || d::text;
  assert d -> 'missing_context' ? 'program.governing_body', 'G2 missing';
  d := public.recruiting_evaluate_core(mens - 'sport_gender', '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'G3 status: ' || d::text;
  assert d -> 'missing_context' ? 'athlete.sport_gender', 'G3 missing';
  -- Missing grad year on a grad-year rule → needs_review with the closest source.
  d := public.recruiting_evaluate_core(mens - 'athlete_grad_year', '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'G4 status: ' || d::text;
  assert d -> 'missing_context' ? 'athlete.grad_year', 'G4 missing';
  assert (d ->> 'rule_key') is not null, 'G4 should attach closest rule';

  -- Case H: D2 (and D3/NAIA/NJCAA) have no sourced rule → needs_review, never D1 ---
  d := public.recruiting_evaluate_core(mens || '{"division": "D2"}'::jsonb, '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'H D2 status: ' || d::text;
  assert (d ->> 'rule_id') is null, 'H D2 must not attach the D1 rule';
  d := public.recruiting_evaluate_core(mens || '{"division": "D3"}'::jsonb, '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'H D3 status';
  d := public.recruiting_evaluate_core(mens || '{"governing_body": "NAIA", "division": null}'::jsonb, '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'H NAIA status: ' || d::text;
  assert (d ->> 'rule_id') is null, 'H NAIA must not attach an NCAA rule';
  d := public.recruiting_evaluate_core(mens || '{"governing_body": "NJCAA", "division": null}'::jsonb, '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'H NJCAA status';

  -- Case I: equally specific contradictory published rules → needs_review + conflict --
  d := public.recruiting_evaluate_core(test_scope || '{"action_type": "test_conflict_action"}'::jsonb, '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'I status: ' || d::text;
  assert (d ->> 'conflict')::boolean, 'I conflict flag';
  assert d -> 'missing_context' ? 'rule.conflict', 'I missing';
  -- The validator reports the same defect.
  assert exists (select 1 from public.recruiting_rules_validate() v where v.rule_key = 'test.conflict.a' and v.severity = 'error'),
    'I validator should flag conflict';

  -- Case J: rule not yet effective is not selected -----------------------------------
  d := public.recruiting_evaluate_core(test_scope || '{"action_type": "test_future_action"}'::jsonb, '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'J status: ' || d::text;
  assert (d ->> 'rule_id') is null, 'J must not select future rule';
  d := public.recruiting_evaluate_core(test_scope || '{"action_type": "test_future_action"}'::jsonb, '2030-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'prohibited', 'J after effective: ' || d::text;

  -- Case K: retired rule is never selected but is preserved --------------------------
  d := public.recruiting_evaluate_core(test_scope || '{"action_type": "test_retired_action"}'::jsonb, '2027-06-10 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'needs_review', 'K status: ' || d::text;
  assert (d ->> 'rule_id') is null, 'K must not select retired rule';
  select count(*) into retired_count from public.recruiting_rules where rule_key = 'test.retired' and status = 'retired';
  assert retired_count = 1, 'K retired row must persist';

  -- §30: in-person restriction does not disable electronic correspondence ------------
  d := public.recruiting_evaluate_core(test_scope || '{"action_type": "coach_off_campus_contact"}'::jsonb, '2027-07-15 12:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'prohibited', 'S30 off-campus in July: ' || d::text;
  assert d ->> 'next_permitted_at' = '2027-08-01T04:00:00Z', 'S30 window end: ' || (d ->> 'next_permitted_at');
  d := public.recruiting_evaluate_core(test_scope || '{"action_type": "coach_send_recruiting_electronic_correspondence"}'::jsonb, '2027-07-15 12:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'permitted', 'S30 electronic in July must stay permitted: ' || d::text;
  d := public.recruiting_evaluate_core(test_scope || '{"action_type": "coach_off_campus_contact"}'::jsonb, '2027-08-01 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'permitted', 'S30 off-campus after window: ' || d::text;

  -- Athlete outreach vs coach restriction are separate (spec §1.3) -------------------
  d := public.recruiting_evaluate_core(
    mens || '{"actor_type": "athlete", "action_type": "athlete_send_intro_message"}'::jsonb,
    '2026-10-01 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'permitted', 'athlete outreach: ' || d::text;
  assert d ->> 'enforcement' = 'none', 'athlete outreach enforcement';
  d := public.recruiting_evaluate_core(
    womens || '{"actor_type": "athlete", "action_type": "athlete_send_intro_message"}'::jsonb,
    '2026-10-01 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'permitted', 'athlete outreach (womens): ' || d::text;
  d := public.recruiting_evaluate_core(
    mens || '{"action_type": "coach_send_nonrecruiting_response"}'::jsonb,
    '2026-10-01 00:00:00 America/Indiana/Indianapolis');
  assert d ->> 'status' = 'permitted_with_restrictions', 'nonrecruiting response: ' || d::text;
  assert d ->> 'source_reference' like 'Bylaw 13.4.1.12%', 'nonrecruiting response source';

  -- Actor derivation never trusts the client ------------------------------------------
  assert public.recruiting_actor_for_action('coach_send_recruiting_electronic_correspondence') = 'coach', 'actor coach';
  assert public.recruiting_actor_for_action('athlete_official_visit') = 'athlete', 'actor athlete';
  assert public.recruiting_actor_for_action('institution_send_camp_logistics') = 'institution', 'actor institution';
  assert public.recruiting_actor_for_action('bogus') is null, 'actor bogus';

  -- Production rule set passes validation (TEST fixtures excluded) --------------------
  assert not exists (
    select 1 from public.recruiting_rules_validate() v
    where v.severity = 'error' and coalesce(v.rule_key, '') not like 'test.%'
  ), 'production rules have validation errors';

  -- Cleanup (also happens automatically on any failed assert) --------------------------
  delete from public.recruiting_rules where governing_body = 'TEST';
  delete from public.recruiting_rule_sources where governing_body = 'TEST';
end $$;

select 'ALL RECRUITING EVALUATOR TESTS PASSED' as result;
