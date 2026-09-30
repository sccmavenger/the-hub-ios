-- =============================================================================
-- 012 — Recruiting Rules Engine: seed verified NCAA Division I basketball rules.
--
-- Every row below was read directly from the official source on 2026-09-30:
--   NCAA Division I Manual 2026-27, LSDBi report 90008 (PDF, 414 pages,
--   footer dated 9/30/26), https://web3.ncaa.org/lsdbi/reports/getReport/90008
--   sha256 a7804698d8708a6bf7258cbe5f8f877aa78212496ab86fa75116558b8045b712
--
-- NOTE — the spec (docs/RECRUITING-RULES-ENGINE-SPEC.md §21) cites Bylaws
-- 13.4.1.3 / 13.4.1.4 for basketball. In the current manual those numbers are
-- the men's lacrosse and softball exceptions. Basketball is 13.4.1.5 (men's,
-- June 15) and 13.4.1.6 (women's, June 1). Dates in the spec were right; the
-- citations were not. The rows below cite the numbers as printed in the PDF.
--
-- Scope of this seed: NCAA Division I basketball only. Nothing here is copied
-- to D2/D3/NAIA/NJCAA — those scopes return needs_review until a rule is
-- read from their own official source (see docs/RECRUITING-RULE-MAINTENANCE.md).
--
-- Deliberately NOT seeded (documented gaps):
--   * Men's basketball, nontraditional academic calendar, ELECTRONIC
--     correspondence. Bylaw 13.4.1.5's nontraditional sentence names only
--     "recruiting materials, including general correspondence" — it omits
--     "electronic correspondence", unlike 13.4.1.6 (women's). We do not infer
--     the omission either way; that context returns needs_review.
--   * Women's basketball July evaluation periods (13.1.3.1.5.1): "all
--     communication ... is prohibited" during those periods. The exact dates
--     live in the annual recruiting calendar, not the manual, so instead of
--     an absolute-window rule the women's "open" state is
--     permitted_with_restrictions and the summary says to check the calendar.
--
-- Time zone for all dated rules: America/Indiana/Indianapolis (NCAA HQ),
-- product decision 2026-09-30. The bylaws themselves give no time zone for
-- the basketball dates.
--
-- Re-runnable: fixed UUIDs + on conflict do nothing. To change a rule, do NOT
-- edit these rows — add a new version per the maintenance doc.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Sources (one row per cited bylaw so source_reference is exact)
-- ---------------------------------------------------------------------------
insert into public.recruiting_rule_sources
  (id, governing_body, title, source_url, source_reference, published_at, retrieved_at, checksum, notes)
values
  (
    'a1b2c3d4-0001-4000-8000-000000000001', 'NCAA',
    'NCAA Division I Manual 2026-27 (LSDBi report 90008)',
    'https://web3.ncaa.org/lsdbi/reports/getReport/90008',
    'Bylaw 13.4.1.5 Exception — Men''s Basketball (recruiting materials and electronic correspondence)',
    '2026-09-30', '2026-09-30T00:00:00Z',
    'sha256:a7804698d8708a6bf7258cbe5f8f877aa78212496ab86fa75116558b8045b712',
    'PDF page 90. June 15 at the conclusion of sophomore year. Nontraditional-calendar sentence covers recruiting materials only (no explicit electronic-correspondence clause).'
  ),
  (
    'a1b2c3d4-0001-4000-8000-000000000002', 'NCAA',
    'NCAA Division I Manual 2026-27 (LSDBi report 90008)',
    'https://web3.ncaa.org/lsdbi/reports/getReport/90008',
    'Bylaw 13.4.1.6 Exception — Women''s Basketball (recruiting materials and electronic correspondence)',
    '2026-09-30', '2026-09-30T00:00:00Z',
    'sha256:a7804698d8708a6bf7258cbe5f8f877aa78212496ab86fa75116558b8045b712',
    'PDF page 90. June 1 at the conclusion of sophomore year; nontraditional calendar: the day after the conclusion of sophomore year. See also 13.1.3.1.5.1 (July evaluation periods: all communication prohibited).'
  ),
  (
    'a1b2c3d4-0001-4000-8000-000000000003', 'NCAA',
    'NCAA Division I Manual 2026-27 (LSDBi report 90008)',
    'https://web3.ncaa.org/lsdbi/reports/getReport/90008',
    'Bylaw 13.1.3.1.6 Exception — Men''s Basketball (telephone calls)',
    '2026-09-30', '2026-09-30T00:00:00Z',
    'sha256:a7804698d8708a6bf7258cbe5f8f877aa78212496ab86fa75116558b8045b712',
    'PDF page 75. Calls may not be made before June 15 at the conclusion of sophomore year.'
  ),
  (
    'a1b2c3d4-0001-4000-8000-000000000004', 'NCAA',
    'NCAA Division I Manual 2026-27 (LSDBi report 90008)',
    'https://web3.ncaa.org/lsdbi/reports/getReport/90008',
    'Bylaw 13.1.3.1.5 Exception — Women''s Basketball (telephone calls); 13.1.3.1.5.1 July evaluation periods',
    '2026-09-30', '2026-09-30T00:00:00Z',
    'sha256:a7804698d8708a6bf7258cbe5f8f877aa78212496ab86fa75116558b8045b712',
    'PDF pages 74-75. Calls may not be made before June 1 at the conclusion of sophomore year. During July evaluation periods all communication is prohibited.'
  ),
  (
    'a1b2c3d4-0001-4000-8000-000000000005', 'NCAA',
    'NCAA Division I Manual 2026-27 (LSDBi report 90008)',
    'https://web3.ncaa.org/lsdbi/reports/getReport/90008',
    'Bylaw 13.4.1.12 Responding to Prospective Student-Athlete''s Request',
    '2026-09-30', '2026-09-30T00:00:00Z',
    'sha256:a7804698d8708a6bf7258cbe5f8f877aa78212496ab86fa75116558b8045b712',
    'PDF page 91. Staff may respond to a prospect''s own request before the permissible date only with a non-recruiting reply (e.g. explanation of NCAA rules, referral to admissions).'
  )
on conflict (id) do nothing;

-- ---------------------------------------------------------------------------
-- Rules
-- ---------------------------------------------------------------------------
insert into public.recruiting_rules (
  id, rule_key, governing_body, division, sport, sport_gender, actor_type, action_type,
  decision, decision_after_start, enforcement_level,
  academic_milestone_type, start_month, start_day, start_year_offset_from_grad, start_day_offset,
  conditions, exception_priority,
  plain_english_summary, plain_english_summary_after,
  source_id, effective_from, effective_until, rule_version, status, last_verified_at
)
values
  -- 1. D1 men's basketball — coach electronic correspondence (HARD BLOCK)
  (
    'b1b2c3d4-0002-4000-8000-000000000001',
    'ncaa.d1.basketball.mens.coach.electronic_correspondence',
    'NCAA', 'D1', 'basketball', 'mens', 'coach', 'coach_send_recruiting_electronic_correspondence',
    'prohibited', 'permitted', 'hard_block',
    'grad_year_offset', 6, 15, -2, null,
    '{"athlete_academic_calendar_type": "traditional_us"}'::jsonb, 0,
    'Under NCAA Division I rules for men''s basketball, a college program may not send you recruiting materials or electronic messages (email, texts, DMs) until June 15 after your sophomore year of high school.',
    'NCAA Division I men''s basketball programs may send recruiting materials and electronic messages starting June 15 after your sophomore year of high school.',
    'a1b2c3d4-0001-4000-8000-000000000001', '2026-08-01', null, 1, 'published', '2026-09-30T00:00:00Z'
  ),

  -- 2. D1 women's basketball — coach electronic correspondence (HARD BLOCK)
  (
    'b1b2c3d4-0002-4000-8000-000000000002',
    'ncaa.d1.basketball.womens.coach.electronic_correspondence',
    'NCAA', 'D1', 'basketball', 'womens', 'coach', 'coach_send_recruiting_electronic_correspondence',
    'prohibited', 'permitted_with_restrictions', 'hard_block',
    'grad_year_offset', 6, 1, -2, null,
    '{"athlete_academic_calendar_type": "traditional_us"}'::jsonb, 0,
    'Under NCAA Division I rules for women''s basketball, a college program may not send you recruiting materials or electronic messages (email, texts, DMs) until June 1 after your sophomore year of high school.',
    'NCAA Division I women''s basketball programs may send recruiting materials and electronic messages starting June 1 after your sophomore year of high school. Exception: during the July evaluation periods, all communication with recruits is paused — check the current women''s basketball recruiting calendar for the exact dates.',
    'a1b2c3d4-0001-4000-8000-000000000002', '2026-08-01', null, 1, 'published', '2026-09-30T00:00:00Z'
  ),

  -- 3. D1 women's basketball — nontraditional academic calendar exception
  (
    'b1b2c3d4-0002-4000-8000-000000000003',
    'ncaa.d1.basketball.womens.coach.electronic_correspondence.nontraditional',
    'NCAA', 'D1', 'basketball', 'womens', 'coach', 'coach_send_recruiting_electronic_correspondence',
    'prohibited', 'permitted_with_restrictions', 'hard_block',
    'sophomore_completed_offset', null, null, null, 1,
    '{"athlete_academic_calendar_type": "nontraditional"}'::jsonb, 10,
    'Because your school uses a nontraditional academic calendar, NCAA Division I women''s basketball programs may not send you recruiting materials or electronic messages until the day after your sophomore year ends.',
    'Because your school uses a nontraditional academic calendar, NCAA Division I women''s basketball programs may send recruiting materials and electronic messages starting the day after your sophomore year ended. Exception: during the July evaluation periods, all communication with recruits is paused — check the current women''s basketball recruiting calendar.',
    'a1b2c3d4-0001-4000-8000-000000000002', '2026-08-01', null, 1, 'published', '2026-09-30T00:00:00Z'
  ),

  -- 4. D1 men's basketball — telephone calls (informational; not a Hub action)
  (
    'b1b2c3d4-0002-4000-8000-000000000004',
    'ncaa.d1.basketball.mens.coach.phone_call',
    'NCAA', 'D1', 'basketball', 'mens', 'coach', 'coach_place_phone_or_video_call',
    'prohibited', 'permitted', 'informational',
    'grad_year_offset', 6, 15, -2, null,
    '{"athlete_academic_calendar_type": "traditional_us"}'::jsonb, 0,
    'Under NCAA Division I rules for men''s basketball, college coaches may not call you or your family until June 15 after your sophomore year of high school.',
    'NCAA Division I men''s basketball coaches may call you starting June 15 after your sophomore year of high school.',
    'a1b2c3d4-0001-4000-8000-000000000003', '2026-08-01', null, 1, 'published', '2026-09-30T00:00:00Z'
  ),

  -- 5. D1 women's basketball — telephone calls (informational)
  (
    'b1b2c3d4-0002-4000-8000-000000000005',
    'ncaa.d1.basketball.womens.coach.phone_call',
    'NCAA', 'D1', 'basketball', 'womens', 'coach', 'coach_place_phone_or_video_call',
    'prohibited', 'permitted_with_restrictions', 'informational',
    'grad_year_offset', 6, 1, -2, null,
    '{"athlete_academic_calendar_type": "traditional_us"}'::jsonb, 0,
    'Under NCAA Division I rules for women''s basketball, college coaches may not call you or your family until June 1 after your sophomore year of high school.',
    'NCAA Division I women''s basketball coaches may call you starting June 1 after your sophomore year of high school, except during the July evaluation periods, when all communication with recruits is paused.',
    'a1b2c3d4-0001-4000-8000-000000000004', '2026-08-01', null, 1, 'published', '2026-09-30T00:00:00Z'
  ),

  -- 6. Athlete outreach — always permitted (bylaws restrict institutions, not you)
  (
    'b1b2c3d4-0002-4000-8000-000000000006',
    'ncaa.d1.basketball.athlete.send_intro_message',
    'NCAA', 'D1', 'basketball', null, 'athlete', 'athlete_send_intro_message',
    'permitted', null, 'none',
    null, null, null, null, null,
    '{}'::jsonb, 0,
    'NCAA recruiting rules limit what college programs may send you — they do not stop you from introducing yourself to a coach at any age. Before their permissible date, a coach can only reply with general information (for example, an explanation of NCAA rules or a referral to admissions), not a recruiting pitch.',
    null,
    'a1b2c3d4-0001-4000-8000-000000000005', '2026-08-01', null, 1, 'published', '2026-09-30T00:00:00Z'
  ),

  -- 7. Coach non-recruiting reply to an athlete's own request (restricted)
  (
    'b1b2c3d4-0002-4000-8000-000000000007',
    'ncaa.d1.basketball.coach.nonrecruiting_response',
    'NCAA', 'D1', 'basketball', null, 'coach', 'coach_send_nonrecruiting_response',
    'permitted_with_restrictions', null, 'informational',
    null, null, null, null, null,
    '{}'::jsonb, 0,
    'Before the date a program may start recruiting correspondence, staff may reply to a recruit''s own request for information only with a non-recruiting response — for example, an explanation of current NCAA rules or a referral to the admissions office. The reply must not start recruiting the athlete or describe the athletics program.',
    null,
    'a1b2c3d4-0001-4000-8000-000000000005', '2026-08-01', null, 1, 'published', '2026-09-30T00:00:00Z'
  )
on conflict (rule_key, rule_version) do nothing;
