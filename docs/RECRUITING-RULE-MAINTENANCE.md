# Recruiting Rule Maintenance

How recruiting rules get into The Hub, get changed, and get verified. This is
an engineering/operations workflow — **no AI, no scraping, no automation
publishes a rule**. A human reads the official source and writes a migration.

Background and rationale: `docs/RECRUITING-RULES-ENGINE-SPEC.md`.

## Where things live

| What | Where |
|---|---|
| Rule storage | `public.recruiting_rules`, `public.recruiting_rule_sources` (supabase/010) |
| Evaluator (the only interpreter) | `public.recruiting_evaluate_core`, RPC `evaluate_recruiting_action` (011) |
| Seeded rules | `supabase/012-recruiting-rules-seed-ncaa-d1-basketball.sql` |
| Messaging enforcement | trigger `trg_enforce_recruiting_rules` on `messages` (013) |
| Flags | `app_settings`: `recruiting_rules_engine_enabled`, `recruiting_rules_enforcement_enabled` |
| Validator | `select * from public.recruiting_rules_validate();` |
| Tests | `supabase/tests/recruiting-rules-evaluator.test.sql`, `supabase/tests/recruiting-messaging-enforcement.test.sql`, `TheHubTests/RecruitingRulesTests.swift` |
| DB access | `scripts/db-query.sh "<sql>"` or `scripts/db-query.sh < file.sql` |

## Currently published rules (as of 2026-09-30)

All from the NCAA Division I Manual 2026-27, LSDBi report 90008
(`https://web3.ncaa.org/lsdbi/reports/getReport/90008`, sha256
`a7804698d870…8045b712`), read 2026-09-30.

| rule_key | Bylaw | Decision |
|---|---|---|
| `ncaa.d1.basketball.mens.coach.electronic_correspondence` | 13.4.1.5 | prohibited until June 15 after sophomore year → permitted (hard_block) |
| `ncaa.d1.basketball.womens.coach.electronic_correspondence` | 13.4.1.6 | prohibited until June 1 after sophomore year → permitted_with_restrictions (July evaluation periods, 13.1.3.1.5.1) (hard_block) |
| `ncaa.d1.basketball.womens.coach.electronic_correspondence.nontraditional` | 13.4.1.6 | nontraditional calendar: prohibited until the day after `sophomore_completed_on` (hard_block) |
| `ncaa.d1.basketball.mens.coach.phone_call` | 13.1.3.1.6 | informational, June 15 |
| `ncaa.d1.basketball.womens.coach.phone_call` | 13.1.3.1.5 | informational, June 1 |
| `ncaa.d1.basketball.athlete.send_intro_message` | 13.4.1.12 | permitted |
| `ncaa.d1.basketball.coach.nonrecruiting_response` | 13.4.1.12 | permitted_with_restrictions |

### Known gaps (return `needs_review` by design)

- **D2, D3, NAIA, NJCAA — every action.** No official source has been read
  for these scopes. Do not copy the D1 rule. Sources to read when picking
  this up: NCAA Division II Manual (LSDBi), NCAA Division III Manual (LSDBi),
  NAIA Official & Policy Handbook, NJCAA Handbook & Casebook.
- **D1 men's basketball, nontraditional academic calendar, electronic
  correspondence.** Bylaw 13.4.1.5's nontraditional sentence names recruiting
  materials only. Ask the NCAA / a compliance office before encoding.
- **Women's basketball July evaluation periods** (13.1.3.1.5.1) are described
  in text but not encoded as dated windows. Encoding them each year from the
  official recruiting calendar (as `academic_milestone_type = 'absolute'`
  rules for the relevant actions) would let the engine say "paused" instead of
  "allowed, with limits" in July.
- **Recruiting-period rules generally** (contact/evaluation/dead periods for
  in-person actions) — not encoded. The action taxonomy supports them.

## Changing a rule (new version)

A published rule is never edited. History must remain readable.

1. **Check the official source.** Open the governing body's current
   document (for NCAA D1: LSDBi report 90008 or its successor). Find the
   bylaw. Read the whole provision including exceptions.
2. **Record the source.** Insert a `recruiting_rule_sources` row: title,
   `source_url`, exact `source_reference` (bylaw number and heading),
   `published_at`, `retrieved_at`, `checksum` (`shasum -a 256` of the PDF),
   `notes` with the page number and anything non-obvious.
3. **Compare against the live version.**
   `select * from recruiting_rules where rule_key = '…' and status = 'published';`
   If nothing changed, skip to step 9.
4. **Write a migration** `supabase/0NN-recruiting-rules-<change>.sql`:
   - insert the new row as `status = 'draft'`, `rule_version = <old> + 1`,
     same `rule_key`, `effective_from` = the date the change takes effect;
   - keep a fixed UUID and `on conflict (rule_key, rule_version) do nothing`
     so the file is re-runnable.
5. **Validate.** `scripts/db-query.sh "select * from recruiting_rules_validate();"`
   — must show no `error` rows. The validator checks source URLs, missing
   references on hard-block rules, impossible dates, future verification
   timestamps, duplicate live versions, and same-scope conflicts.
6. **Test.** Add/adjust cases in
   `supabase/tests/recruiting-rules-evaluator.test.sql` (fixed dates, the
   rule's time zone). Run both SQL test files. Run the Swift tests.
7. **Publish.** In the same migration (or a follow-up), in one transaction:
   ```sql
   update recruiting_rules set status = 'retired',
          effective_until = '<new effective_from - 1 day>'
    where rule_key = '…' and status = 'published';
   update recruiting_rules set status = 'published'
    where rule_key = '…' and rule_version = <new>;
   ```
   The partial unique index guarantees one live version per key.
8. **Retire/end-date the previous version** — done above; never delete it.
9. **Verify key scenarios** through the RPC as a real user (Journey and
   Colleges in the app, or `evaluate_recruiting_action` from the SQL editor
   with `set role authenticated` + a JWT claim), before and after the date.
10. **Record `last_verified_at`.** For an unchanged rule that you re-read,
    `update recruiting_rules set last_verified_at = now() where id = …` is
    the one permitted in-place edit; it does not alter meaning.

Commit the migration and note the source in the commit message.

## Annual cycle

- Each August (new NCAA manual) re-read every published bylaw and update
  `last_verified_at` or publish new versions.
- Rules older than 180 days without verification appear as `warning` rows in
  the validator. They keep working; treat the warning as a to-do.
- The women's basketball recruiting calendar (July evaluation periods)
  changes every year.

## Programs and coach verification

Enforcement requires a `coach_program_memberships` row with
`status = 'verified'` joined to an active `recruiting_programs` row with
`verified_at` set. Since 2026-09-30 (`supabase/014-coach-onboarding.sql`)
these rows are created by **approving a coach application** — in the iOS
app (admin → Coaches tab → application → Approve…) or by calling the RPC
as an admin:

```sql
-- existing program (verifies it if it isn't yet)
select approve_coach_request('<request id>', '<program id>', null, 'assistant_coach', 'Assistant Coach', 'verified on staff page');
-- or a new program from admin-confirmed attributes
select approve_coach_request('<request id>', null,
  '{"institution_name":"Missouri State University","governing_body":"NCAA","division":"D1","sport_gender":"mens","athletics_url":"https://missouristatebears.com/"}',
  'assistant_coach', 'Assistant Coach', 'verified on staff page');
-- suspend / inactivate / reinstate (coach role follows in the same statement)
select set_coach_membership_status('<membership id>', 'suspended', 'left program');
```

The coach role is *derived*: `sync_coach_role(user_id)` keeps
`user_roles.coach` equal to "has ≥1 verified membership in an active,
verified program", and membership/program triggers re-run it on every
change. BEFORE triggers refuse, for any authenticated client (PostgREST,
including the web admin portal), direct `coach_requests.status` flips,
direct `user_roles (role = 'coach')` inserts, and direct verified
membership inserts. Server-side contexts (`scripts/db-query.sh`, service
role — `auth.uid()` is null) are exempt, so the raw inserts below still work
for maintenance and tests, but the RPCs are the supported path:

```sql
insert into recruiting_programs (institution_name, normalized_institution_name,
  governing_body, division, sport, sport_gender, verified_at, source_url)
values ('Missouri State University', 'missouri state university', 'NCAA', 'D1',
  'basketball', 'mens', now(), 'https://missouristatebears.com/');

insert into coach_program_memberships (coach_user_id, program_id, status, verified_at, verified_by)
values ('<coach auth uid>', '<program id>', 'verified', now(), '<admin uid>');
```

Never derive a program from `coach_requests.college` free text for
enforcement. The bundled `Colleges.json` division may be used to *suggest*
a mapping, not to verify one. Tests: `supabase/tests/coach-onboarding.test.sql`.

## Rollout flags

| Flag | Stage | Effect |
|---|---|---|
| `recruiting_rules_engine_enabled = true` | A (current) | Clients show decisions; enforcement off; trigger logs shadow rows |
| `recruiting_rules_enforcement_enabled = true` | B | Verified-coach prohibited sends rejected with `RECRUITING_ACTION_PROHIBITED` |
| both `false` | rollback | App shows "Recruiting status unavailable"; no blocking; no rule shown |

Flip from the app's Admin Settings screen or:
`scripts/db-query.sh "update app_settings set bool_value = true where key = 'recruiting_rules_enforcement_enabled';"`

## Observability

- `recruiting_compliance_decisions` — every coach-send evaluation (no bodies).
  `evaluation_source` is `message_trigger`, `message_trigger_shadow`, or
  `rpc_conflict`. A rejected insert rolls its audit row back; look for
  `RECRUITING_ACTION_PROHIBITED` lines in the Postgres log instead.
- Useful queries:
  ```sql
  select decision, count(*) from recruiting_compliance_decisions group by 1;
  select unnest(missing_context) m, count(*) from recruiting_compliance_decisions group by 1 order by 2 desc;
  select rule_key, last_verified_at from recruiting_rules where status = 'published' order by 2;
  ```

## Website terms

`docs/legal/terms-of-service.md` §6 and `LegalView.swift` were rewritten
2026-09-30. The Lovable-hosted `/terms` page is outside this repo and must be
updated to the identical text (see TECH-DEBT #13). Until it is, the website
still says The Hub "does not monitor recruiting contact".
