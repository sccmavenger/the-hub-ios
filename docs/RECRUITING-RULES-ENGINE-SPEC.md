# The Hub — Recruiting Rules Engine
## Claude Code Implementation Specification

**Repository:** `sccmavenger/the-hub-ios`  
**Primary client:** iOS / SwiftUI  
**Backend:** Supabase / PostgreSQL  
**Prepared:** September 30, 2026  
**Product focus for this release:** Basketball  
**AI policy for this release:** **No AI in the product. No AI is required to evaluate, interpret, or enforce recruiting rules.**

---

# 0. Instructions to Claude Code

Read this entire specification before making changes.

Inspect the current repository and database migrations before implementation. The file paths below are based on the current repository and are intended to anchor the work to the existing product rather than create a parallel architecture.

Implement this work incrementally. Preserve existing authentication, guardian consent, coach approval, message immutability, block/report behavior, NCAA Journey progress, and college-list behavior.

**Critical requirement:** do **not** solve the current problem by replacing the June 15 constant with a larger Swift `switch` statement or another collection of hard-coded dates in the iOS client.

The authoritative recruiting rules must be versioned backend data, and the compliance decision must be deterministic.

Before completing each phase:

1. Build/compile the affected target.
2. Run relevant tests.
3. Add tests for new logic.
4. Verify existing messaging and NCAA Journey flows still work.
5. Do not weaken any current RLS or safety controls.
6. Document any rule or association for which an authoritative source was not found.
7. Do not infer a rule for one division from a rule for another division.
8. Do not use AI, an LLM, or generated interpretation at runtime.

At the end, provide:
- files changed,
- migrations added,
- tests added,
- official sources used,
- rules intentionally left as `needs_review`,
- any data backfill still required,
- build/test results,
- and rollout instructions.

---

# 1. Product Decision Summary

The Hub is replacing its current hard-coded recruiting contact-date logic with a **Recruiting Rules Engine**.

The engine answers a narrower and more accurate question than “is contact open?”:

> **Is this specific recruiting action permitted for this actor, this athlete, this program, and this date under the applicable verified rule?**

The following product decisions are locked for this release.

## 1.1 Basketball first

Near- and medium-term product focus is basketball.

The architecture must be extensible to other sports later, but this implementation must not spend time building complete rule sets for sports other than basketball.

Schema fields must support future sports without another redesign.

## 1.2 Hard-block only actions The Hub controls

When The Hub itself is about to facilitate an action and a verified rule deterministically says the action is prohibited, The Hub must hard-block the action.

Example:
- a college coach attempts to send an in-app recruiting message before the applicable verified correspondence window.

Activities outside The Hub should be informational or warning-only because the application cannot know every external fact.

## 1.3 Athlete outreach and coach restrictions are separate concepts

Do not equate:
- “the athlete may send a message”
with
- “the coach may send recruiting correspondence.”

An athlete may initiate outreach through The Hub.

The coach’s permissible response may differ depending on the applicable rule and the content/type of response.

The engine must model actor and action separately.

## 1.4 Unknown means unknown

The engine must never invent or infer a rule.

If required facts or a verified rule are missing, return:

`needs_review`

The user experience should:
- explain that the rule could not be determined,
- show the closest authoritative source when available,
- and avoid a hard block unless a verified rule says the action is prohibited.

## 1.5 Source information should be visible wherever practical

A compliance decision should expose:
- plain-English explanation,
- governing body,
- division,
- sport/gender,
- action,
- source title,
- source URL,
- bylaw/reference when available,
- effective date,
- last verified date,
- and rule version.

Users should be able to understand **why** the application reached the result.

## 1.6 First UI integrations

Phase 1 product surfaces are:

1. **NCAA Journey**
2. **Messaging**
3. **College/program recruiting-status indicator**

In the current iOS repository, the “college/program” experience is primarily the athlete’s **My Colleges / CollegeListView** surface. Integrate there rather than inventing a completely separate college-profile subsystem unless the current repo has evolved by implementation time.

## 1.7 No AI in this release

No AI in the shipped product.

Specifically:
- no AI chatbot,
- no AI compliance interpretation,
- no LLM calls,
- no AI-generated rule decisions,
- no AI dependency for updating or reading rules,
- no AI fallback when a deterministic rule is unavailable.

A future external rule-curation agent may be considered separately. It is **out of scope for this release**.

## 1.8 The Hub is compliance-aware, not the NCAA

The product may:
- provide rules-based guidance,
- show authoritative sources,
- and enforce verified in-platform restrictions.

The product must **not** claim:
- that it is the NCAA,
- that it makes official NCAA eligibility determinations,
- that it guarantees an institution or coach is compliant,
- or that its rule set replaces an institution’s compliance office.

---

# 2. Current Repository State — Important Findings

Claude must verify these again against the branch being modified.

## 2.1 Hard-coded date logic exists today

Current file:

`TheHub/Utilities/Compliance.swift`

The current implementation has:

- a `ContactWindow` model,
- `contactOpensOn(gradYear:division:)`,
- a rule treating D1 and D2 as opening on June 15 of `gradYear - 2`,
- `contactWindows(...)`,
- static NCAA calendar links,
- and a disclaimer acknowledging the summary does not account for many recruiting conditions.

This is the architecture being replaced.

Do not merely change June 15.

## 2.2 NCAA Journey directly consumes the hard-coded logic

Current file:

`TheHub/Views/NCAA/NCAAJourneyView.swift`

The Journey currently calls `Compliance.contactOpensOn(...)` and renders a milestone describing D1/D2 coaches as being able to contact the athlete.

This needs to consume the new decision service.

The rest of NCAA Journey — eligibility readiness, account status, core courses, transcript status, amateurism progress, etc. — should remain intact.

## 2.3 CollegeListView shows the current “contact windows”

Current file:

`TheHub/Views/Colleges/CollegeListView.swift`

The current college experience renders `Compliance.contactWindows(...)`.

Replace this with a rules-engine-backed recruiting status.

## 2.4 Messaging currently inserts directly into `messages`

Current file:

`TheHub/Services/AthleteService.swift`

`sendMessage(...)` currently inserts directly into the Supabase `messages` table.

Current iOS use is athlete/guardian messaging. Coach/admin tools are primarily web-side, but the **shared database** is the correct enforcement boundary.

Do not rely on a SwiftUI button state to enforce coach-message restrictions.

## 2.5 Current message safety controls must remain

Existing migrations include important controls such as:
- blocked-pair enforcement,
- coach messaging only to published athletes,
- immutable message bodies after sending,
- role/RLS checks.

Relevant current migrations include:
- `supabase/002-parity.sql`
- `supabase/007-launch-hardening.sql`

The recruiting engine must be additive to these protections.

## 2.6 Coach program context is currently insufficient

The existing `coach_requests` schema stores a `college` value, but not enough normalized program context to safely evaluate recruiting rules.

A compliance decision needs at minimum:
- governing body,
- division,
- sport,
- gender/category,
- program/institution identity,
- verified coach association.

Do **not** derive these from arbitrary free text every time a message is sent.

This gap must be addressed before reliable coach hard-blocking is enabled.

## 2.7 Terms of Use currently conflict with the planned behavior

Current canonical repo file:

`docs/legal/terms-of-service.md`

Current compiled app copy:

`TheHub/Views/Legal/LegalView.swift`

The current terms state, in substance, that The Hub does not monitor recruiting contact.

That will no longer accurately describe the feature after rules-based in-platform restrictions are enabled.

The legal/product text update is part of this project, not a later cleanup.

---

# 3. Goals

The implementation must:

1. Remove recruiting-rule authority from the iOS binary.
2. Store versioned, sourced rules in Supabase.
3. Evaluate rules deterministically.
4. Support rules that vary by:
   - governing body,
   - division,
   - sport,
   - gender/category,
   - actor,
   - action,
   - academic milestone,
   - date,
   - athlete cohort/enrollment cohort when needed,
   - and exception conditions.
5. Expose reason/source metadata with every decision.
6. Hard-block only verified prohibited actions performed through The Hub.
7. Return `needs_review` rather than guess.
8. Make the same engine usable by iOS and web clients.
9. Keep rules auditable and historically versioned.
10. Allow rule updates without an App Store release.
11. Support future sports and governing bodies without schema replacement.
12. Keep the early product completely non-AI.

---

# 4. Non-Goals for This Release

Do not turn this project into a complete compliance management platform.

The following are explicitly out of scope unless already trivial in the codebase:

- AI rule interpretation.
- AI rule curation.
- Complete rule coverage for every NCAA sport.
- State high-school association recruiting rules.
- Transfer portal compliance.
- NIL contract compliance.
- Financial-aid compliance.
- Complete event-certification workflow.
- Institution compliance-office case management.
- Full legal-rule editor UI.
- Automated scraping that immediately publishes rule changes.
- Replacing the NCAA Eligibility Center.
- Official eligibility certification.
- Predicting whether a coach or school is compliant outside The Hub.

The data model should make later expansion possible.

---

# 5. Core Domain Model

The engine must model **actions**, not one universal contact date.

Initial action taxonomy should support at least:

```text
athlete_send_intro_message
coach_send_recruiting_electronic_correspondence
coach_send_nonrecruiting_response
coach_place_phone_or_video_call
coach_off_campus_contact
coach_in_person_evaluation
athlete_official_visit
athlete_unofficial_visit
institution_send_recruiting_material
institution_send_camp_logistics
```

Only actions actually used by the current product need full Phase 1 UI.

The most important Phase 1 enforcement action is:

```text
coach_send_recruiting_electronic_correspondence
```

Do not collapse all of the above into `contact`.

---

# 6. Decision Model

Create a shared conceptual decision model equivalent to:

```swift
enum RecruitingDecisionStatus: String, Codable {
    case permitted
    case prohibited
    case permittedWithRestrictions
    case needsReview
}

struct RecruitingDecision: Codable {
    let status: RecruitingDecisionStatus
    let action: String
    let reason: String
    let userMessage: String
    let nextPermittedAt: Date?
    let ruleId: UUID?
    let ruleVersion: Int?
    let sourceTitle: String?
    let sourceURL: URL?
    let sourceReference: String?
    let effectiveFrom: Date?
    let effectiveUntil: Date?
    let lastVerifiedAt: Date?
    let enforcement: EnforcementLevel
}
```

Suggested enforcement enum:

```swift
enum EnforcementLevel: String, Codable {
    case hardBlock
    case warning
    case informational
    case none
}
```

### Status behavior

**permitted**
- action may proceed.

**prohibited**
- action must be blocked when it is performed inside The Hub and the rule is verified.

**permittedWithRestrictions**
- action may be possible only under a narrow exception/condition.
- UI must explain the restriction.
- do not silently treat as fully permitted.

**needsReview**
- required rule or facts are missing/ambiguous.
- do not guess.
- for Phase 1, do not hard-block solely because status is `needsReview`.

---

# 7. Evaluation Context

A rules evaluation should accept context equivalent to:

```text
governing_body
division
sport
sport_gender
actor_type
action_type
athlete_id
athlete_grad_year
athlete_academic_calendar_type
athlete_sophomore_completed_on
athlete_commitment_status
program_id
coach_user_id
evaluation_timestamp
```

Not every rule will require every field.

The evaluator should identify which missing field prevented a determination.

Example:

```json
{
  "status": "needs_review",
  "reason": "Program division is not verified for this coach.",
  "missing_context": ["program.division"]
}
```

---

# 8. Program and Coach Context

The existing free-text `coach_requests.college` value is not sufficient for authoritative enforcement.

Create normalized program context.

Recommended tables:

```sql
create table public.recruiting_programs (
    id uuid primary key default gen_random_uuid(),
    institution_name text not null,
    normalized_institution_name text not null,
    governing_body text not null,
    division text,
    sport text not null,
    sport_gender text not null,
    external_id text,
    official_url text,
    active boolean not null default true,
    source_url text,
    verified_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
```

```sql
create table public.coach_program_memberships (
    id uuid primary key default gen_random_uuid(),
    coach_user_id uuid not null references auth.users(id) on delete cascade,
    program_id uuid not null references public.recruiting_programs(id) on delete cascade,
    title text,
    status text not null check (status in ('pending','verified','rejected','inactive')),
    verified_at timestamptz,
    verified_by uuid references auth.users(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (coach_user_id, program_id)
);
```

Do not delete `coach_requests.college` immediately if existing code depends on it.

Instead:
1. add the normalized model,
2. migrate/backfill known approved coaches,
3. keep the legacy field during transition,
4. make enforcement depend on a **verified** program membership,
5. return `needs_review` when the coach’s governing body/division/program is not verified.

Do not hard-block based on guessed school/division matching from a free-text college name.

---

# 9. Athlete Academic Context

The current `Athlete` model contains:
- `gradYear`
- `sportGender`
- DOB and other profile data.

That is useful but not sufficient for every exception.

Add backend support for:

```text
academic_calendar_type:
    traditional_us
    nontraditional
    unknown

sophomore_completed_on:
    date nullable
```

Do not require every existing user to fill this immediately.

For rules whose standard formulation can be deterministically evaluated from graduation year under a traditional U.S. calendar, the engine may use the documented standard calculation.

If a rule has a special nontraditional-calendar exception:
- evaluate using `sophomore_completed_on` when supplied;
- otherwise return `needs_review` for that exception path rather than guessing.

If these fields are added to `athletes`, update:
- Supabase schema,
- Swift `Athlete` model,
- coding keys,
- profile editing only if necessary for this phase.

A polished academic-calendar settings UX is not required if it expands scope. A safe default/unknown path is acceptable.

---

# 10. Rule Storage

Use backend tables, not Swift constants.

Recommended source table:

```sql
create table public.recruiting_rule_sources (
    id uuid primary key default gen_random_uuid(),
    governing_body text not null,
    title text not null,
    source_url text not null,
    source_reference text,
    published_at date,
    retrieved_at timestamptz not null,
    checksum text,
    notes text,
    created_at timestamptz not null default now()
);
```

Recommended rule table:

```sql
create table public.recruiting_rules (
    id uuid primary key default gen_random_uuid(),

    governing_body text not null,
    division text,
    sport text,
    sport_gender text,

    actor_type text not null,
    action_type text not null,

    decision text not null
      check (decision in (
        'permitted',
        'prohibited',
        'permitted_with_restrictions'
      )),

    enforcement_level text not null
      check (enforcement_level in (
        'hard_block',
        'warning',
        'informational',
        'none'
      )),

    academic_milestone_type text,
    start_month integer,
    start_day integer,
    start_year_offset_from_grad integer,
    absolute_start_at timestamptz,
    absolute_end_at timestamptz,

    conditions jsonb not null default '{}'::jsonb,
    exception_priority integer not null default 0,

    plain_english_summary text not null,

    source_id uuid not null
      references public.recruiting_rule_sources(id),

    effective_from date not null,
    effective_until date,

    rule_version integer not null,
    status text not null
      check (status in ('draft','published','retired')),

    last_verified_at timestamptz not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
```

The schema may be adjusted if a cleaner representation is found after inspecting current migrations, but preserve these capabilities:
- versioning,
- effective dating,
- source linkage,
- conditions,
- exceptions,
- actor/action separation,
- deterministic evaluation,
- and auditability.

---

# 11. Rule Versioning and Publication

A rule change must not overwrite history.

When a rule changes:
1. retire/end-date the old rule;
2. insert a new version;
3. retain old source/version metadata.

Never mutate a previously applied published rule in a way that destroys historical meaning.

Rules should have:
- `draft`
- `published`
- `retired`

Only `published` rules participate in production evaluation.

A database constraint or validation routine should prevent overlapping contradictory published rules for the same scope unless one is an explicit higher-priority exception.

---

# 12. Rule Precedence

The evaluator must be deterministic.

Recommended precedence, most specific first:

1. exact governing body
2. exact division
3. exact sport
4. exact sport gender/category
5. exact actor
6. exact action
7. explicit exception conditions
8. enrollment/cohort conditions when present
9. general/default rule

An exception should override a general rule only when its conditions match.

If two equally specific published rules conflict:
- return `needs_review`,
- log the configuration defect,
- do not choose one arbitrarily.

---

# 13. Authoritative Decision Service

Use a single authoritative backend function.

Recommended PostgreSQL function/RPC:

```text
evaluate_recruiting_action(...)
```

The same evaluator must be used by:
- iOS for informational displays,
- web clients,
- and database enforcement.

Do not implement one copy of the logic in Swift and another copy in SQL.

Swift should deserialize the decision; it should not reimplement the rule.

Conceptual RPC call:

```swift
let decision: RecruitingDecision = try await supabase
    .rpc(
        "evaluate_recruiting_action",
        params: [
            "athlete_id": athleteId,
            "program_id": programId,
            "actor_user_id": actorUserId,
            "action_type": action.rawValue,
            "evaluation_at": Date.now.toISO8601String()
        ]
    )
    .execute()
    .value
```

The database should resolve trusted context itself where possible instead of accepting security-sensitive claims from the client.

For example:
- actor identity should come from `auth.uid()` in enforcement paths,
- verified coach/program membership should come from database rows,
- athlete data should come from `athletes`.

Do not trust a client-provided `"division":"D1"` for hard-blocking.

---

# 14. Messaging Enforcement

This is a core requirement.

Current message writes go to `public.messages`.

Add a `BEFORE INSERT` enforcement trigger, or route writes through a server function that cannot be bypassed by ordinary authenticated clients.

Preferred approach: preserve the current table flow and add a trigger that calls the same deterministic evaluator.

Conceptual behavior:

```text
IF sender is athlete/guardian:
    do not apply coach-initiated recruiting-message block
    preserve existing RLS and block checks

IF sender is verified coach:
    evaluate coach_send_recruiting_electronic_correspondence

    IF decision == prohibited AND enforcement == hard_block:
        reject insert with stable compliance error code

    IF decision == permitted:
        allow

    IF decision == permitted_with_restrictions:
        enforce only if the exception can be determined safely
        otherwise needs_review behavior

    IF decision == needs_review:
        allow under current product decision,
        but record the evaluation and surface a warning in supported clients
```

The database hard-block is important because:
- old app builds,
- future web clients,
- or an implementation error in the UI
must not bypass a known prohibition.

### Stable error

Do not expose an opaque SQL error to users.

Return or throw a stable code such as:

```text
RECRUITING_ACTION_PROHIBITED
```

with decision metadata available to the client.

The UI can then display:

> This recruiting message can’t be sent yet under the rule currently applicable to this program and athlete.

Then show:
- next permissible date when known,
- reason,
- source link.

---

# 15. Compliance Metadata on Messages

Consider adding immutable evaluation metadata to coach-sent messages:

```text
compliance_status
compliance_rule_id
compliance_rule_version
compliance_evaluated_at
```

Do not store unnecessary sensitive interpretation or duplicate the entire source document.

The purpose is auditability:
- which rule allowed a message at send time?

If added, protect these fields from client modification just like the message body and identity fields.

---

# 16. Decision Audit Log

Create a minimal audit table for enforcement-sensitive evaluations:

```sql
create table public.recruiting_compliance_decisions (
    id uuid primary key default gen_random_uuid(),
    actor_user_id uuid,
    athlete_id uuid,
    program_id uuid,
    action_type text not null,
    decision text not null,
    enforcement_level text not null,
    rule_id uuid,
    rule_version integer,
    evaluated_at timestamptz not null default now(),
    context_snapshot jsonb
);
```

Do **not** store message bodies in this log.

Use a sanitized context snapshot only if necessary.

RLS:
- ordinary users should not be able to browse global compliance logs;
- admin/service access only, with narrow user-visible decision data returned through the evaluator.

---

# 17. NCAA Journey Integration

Replace the current single hard-coded “contact opens” timeline behavior.

The Journey should become action-aware.

Suggested UI block:

```text
Recruiting communication

Coach recruiting messages
[Allowed / Not yet / Needs review]

Your outreach
[You can introduce yourself]

Why?
[Plain-English explanation]

Source
[Official NCAA source]

Last verified
[date]
```

Do not imply that:
- all contact types become legal on the same date,
- messaging and in-person contact are equivalent,
- or a dead/quiet/evaluation period universally disables electronic messaging.

The existing NCAA eligibility-readiness journey should remain.

This feature augments the Journey; it does not replace eligibility tracking.

---

# 18. Messaging UI Integration

For athlete/guardian messaging:
- allow athlete outreach as currently decided,
- show explanatory recruiting status where useful,
- explain that the coach may be subject to response restrictions.

For coach-facing clients:
- fetch a decision before send to provide good UX,
- but rely on the database as the authoritative enforcement layer.

If preflight says `prohibited`:
- disable send,
- show reason/source/next date.

If preflight says `needs_review`:
- warning, not a hard block under Phase 1 policy.

If the server rejects despite a stale preflight result:
- treat the server result as authoritative,
- refresh the decision,
- display the server reason.

---

# 19. College / Program Status Integration

Current iOS surface: `CollegeListView`.

Replace the generic D1/D2 contact-window card with program-specific status when enough program data exists.

Example:

```text
Missouri State
NCAA D1 · Men's Basketball

Recruiting status
Electronic recruiting messages: Allowed
Your outreach: Allowed

Why?
NCAA rule explanation

Source
Official NCAA rule
```

If the college interest is only free text and cannot be mapped to a verified recruiting program:

```text
Recruiting status: Needs review
We don't have a verified program/division match for this school yet.
```

Do not guess a program from a school name for enforcement.

It is acceptable to use fuzzy/normalized matching to **suggest** a mapping, but a hard-blocking program association must be verified data.

---

# 20. Source UX

Create a reusable SwiftUI component for rule attribution, for example:

`RecruitingRuleSourceView`

It should be able to show:
- source title,
- reference/bylaw,
- effective date,
- last verified date,
- link to the official source.

Use system browser behavior consistent with the current app.

Avoid copying long copyrighted rule text into the app.

Store a concise plain-English summary and link to the official source.

---

# 21. Phase 1 Seed Rules

Do not populate a rule from memory.

Seed only rules supported by official sources.

At minimum, current official NCAA Division I legislation should be represented for the basketball electronic-correspondence scenarios needed to replace the existing hard-coded value.

Verified examples as of September 30, 2026 include:

## NCAA Division I — Men's Basketball

For recruiting materials/electronic correspondence, the current NCAA Division I rule identifies June 15 at the conclusion of the athlete’s sophomore year, with a nontraditional-academic-calendar provision.

Reference:
- NCAA Division I Bylaw 13.4.1.3 in the current LSDBi report.

Official source:
`https://web3.ncaa.org/lsdbi/reports/getReport/90008`

## NCAA Division I — Women's Basketball

For recruiting materials/electronic correspondence, the current NCAA Division I rule identifies June 1 at the conclusion of the athlete’s sophomore year, with a nontraditional-academic-calendar provision.

Reference:
- NCAA Division I Bylaw 13.4.1.4 in the current LSDBi report.

Official source:
`https://web3.ncaa.org/lsdbi/reports/getReport/90008`

## NCAA recruiting calendar source

NCAA currently publishes 2026-27 Division I men's and women's basketball recruiting calendars through its basketball certification resources.

Official source:
`https://www.ncaa.org/eligibility-center/recruiting/basketball-certification/`

### Important seed-rule requirement

The current app treats D1 and D2 as equivalent for the June 15 rule.

**Do not carry that assumption forward.**

If Claude cannot locate and verify the applicable D2/D3/NAIA/NJCAA basketball rule from an official source during implementation:
- do not copy the D1 rule,
- do not infer equivalence,
- create no hard-blocking rule for that unsourced scope,
- return `needs_review`,
- and document the missing source in the completion report.

The engine is more valuable being explicitly incomplete than confidently wrong.

---

# 22. Rule Maintenance Without AI

The user does not want to personally babysit rule rows, but this release also must not ship AI.

Therefore Phase 1 rule maintenance should be an engineering/operations workflow.

Add:

`docs/RECRUITING-RULE-MAINTENANCE.md`

It should explain:

1. Check official governing-body sources.
2. Record the source URL and reference.
3. Compare against the currently published rule version.
4. Add a new source record.
5. Add a new draft rule version.
6. Run validation/tests.
7. Publish the new version.
8. Retire/end-date the previous version.
9. Verify key scenarios.
10. Record `last_verified_at`.

Also add a lightweight validation script or database test that detects:
- missing source records,
- unpublished source references,
- impossible dates,
- overlapping conflicting rules,
- missing verification timestamps,
- hard-block rules with no source,
- duplicate active versions.

A future automated curator can use this workflow later without changing runtime architecture.

Do not implement that future agent now.

---

# 23. Legal / Terms Update

This is part of acceptance criteria.

Current Section 6 conflicts with the new feature because it says The Hub does not monitor recruiting contact.

Update the canonical Terms of Use and all in-repo copies.

Current known locations:
- `docs/legal/terms-of-service.md`
- `TheHub/Views/Legal/LegalView.swift`

The canonical file currently notes that identical text is also published on the website.

If the website terms live outside this repository:
- do not falsely claim they were updated,
- add the required website update to the completion checklist,
- identify the exact replacement text.

## Proposed Section 6 direction

Use language substantially equivalent to:

> **6. COACH ACCESS AND RECRUITING RULES**  
> Approved coaches remain responsible for complying with NCAA, NAIA, NJCAA, conference, institution, and other applicable recruiting rules. The HUB may provide rules-based recruiting guidance and may restrict certain actions performed through the Service when the Service has a verified rule indicating that the action is not permitted. These features are informational and operational safeguards and are not an official eligibility or compliance determination by the NCAA or any other governing body. Recruiting rules can change and may depend on facts the Service does not know. Users should confirm questions with the applicable governing body or institution compliance office.

Claude may adapt wording to match the existing legal style but must preserve the meaning.

Do not claim that The Hub guarantees compliance.

Update the “last updated” date.

Search the entire repository for old statements such as:
- “does not monitor recruiting contact,”
- generic “contact opens June 15,”
- “D1 & D2 coaches may now contact you,”
- or copy that treats all contact types as one event.

Update inconsistent product copy.

This technical specification is not a substitute for legal review; preserve a concise product disclaimer where appropriate.

---

# 24. Feature Flags and Rollout

Use a staged rollout.

Recommended flags:

```text
recruiting_rules_engine_enabled
recruiting_rules_enforcement_enabled
```

If an existing remote/admin feature-flag system is already present, extend it rather than building a second one.

Rollout order:

### Stage A — Shadow/evaluation
- engine enabled,
- UI can display decisions,
- enforcement disabled,
- compare outputs against test cases.

### Stage B — Verified scopes
- enable hard-blocking only for published, verified rules and complete coach/program context.

### Stage C — Expand coverage
- publish additional sourced basketball rules,
- no client update required.

Do not make incomplete D2/D3/NAIA/NJCAA coverage a blocker for shipping the engine if unsupported contexts correctly return `needs_review`.

---

# 25. Offline and Failure Behavior

The backend is authoritative.

Client caching may improve display performance but may not become a second rule engine.

Rules/decisions may be cached with:
- rule version,
- evaluated timestamp,
- expiry.

If cached data is stale:
- label it as stale or refresh it,
- never hard-block a user solely from stale local data.

Messaging already requires the server to insert a message, so the server enforcement path remains authoritative.

If the decision service is unavailable:
- athlete informational surfaces should show “Recruiting status unavailable.”
- do not fabricate an allowed/prohibited state.
- coach message writes should follow the database’s actual enforcement availability and fail safely if the authoritative transaction cannot be completed.

---

# 26. Security Requirements

1. Rule publication must not be writable by ordinary authenticated users.
2. Source/rule tables should be read-only or RPC-only to ordinary clients as appropriate.
3. Only service/admin roles may create/publish/retire rules.
4. Coach/program membership verification must be admin-controlled.
5. Client-provided division/sport values are not authoritative for hard-blocking.
6. Preserve current message RLS.
7. Preserve blocked-user enforcement.
8. Preserve message immutability.
9. Preserve published-athlete requirement for coach-initiated threads.
10. Do not expose global coach/program verification data unnecessarily.
11. Do not store message body text in compliance audit logs.
12. Add indexes for decision-path lookups.

---

# 27. Suggested Swift Architecture

Recommended new files, adjusted to match current project organization:

```text
TheHub/Core/Models/RecruitingDecision.swift
TheHub/Core/Models/RecruitingProgram.swift
TheHub/Services/RecruitingRulesService.swift
TheHub/Views/Recruiting/RecruitingStatusView.swift
TheHub/Views/Recruiting/RecruitingRuleSourceView.swift
```

Responsibilities:

## `RecruitingRulesService`
- call backend evaluator,
- decode decision,
- optional short-lived cache,
- no rule interpretation.

## `RecruitingDecision`
- Codable representation of backend result.

## `RecruitingStatusView`
- consistent badge/status UI.

## `RecruitingRuleSourceView`
- explanation/source/effective/verification UI.

Refactor `Compliance.swift`.

It may continue to contain:
- generic URLs,
- age helper functions,
- trademark notice,
- non-rule helper copy if useful.

It must no longer be the authoritative store of recruiting dates.

---

# 28. Migration Strategy

Do not make this a flag-day rewrite.

## Migration 1 — schema
Add:
- source table,
- rules table,
- program table,
- coach/program memberships,
- optional audit table,
- athlete academic-calendar fields if chosen.

## Migration 2 — seed verified rules
Insert official basketball rule sources and verified initial rules.

## Migration 3 — evaluator
Create deterministic evaluation function and SQL tests.

## Migration 4 — shadow client
Add service/models and display results while old UI still exists behind flag if needed.

## Migration 5 — program mapping
Backfill known approved coach associations where data is trustworthy.

Unknown mappings remain unknown.

## Migration 6 — messaging enforcement
Add backend enforcement trigger/function behind rollout flag.

## Migration 7 — remove old authority
Remove/deprecate:
- `contactOpensOn`
- `contactWindows`
- hard-coded universal D1/D2 contact-date copy.

## Migration 8 — legal/copy sweep
Update Terms and all references.

Each migration should be re-runnable where that matches the repository’s current migration style.

---

# 29. Automated Test Matrix

Tests are mandatory.

Use fixed dates/time zones in tests. Do not rely on `Date.now` without injection.

## 29.1 Core evaluator tests

### Case A
```text
Governing body: NCAA
Division: D1
Sport: basketball
Gender: men's
Actor: coach
Action: recruiting electronic correspondence
Athlete: traditional U.S. calendar
Date: before applicable June 15 opening
Expected: prohibited
Enforcement: hard block
Source: present
```

### Case B
Same context after opening.

Expected:
```text
permitted
```

### Case C
```text
NCAA D1
Women's basketball
Coach electronic correspondence
Before applicable June 1 opening
```

Expected:
```text
prohibited
```

### Case D
Same context after opening.

Expected:
```text
permitted
```

### Case E
Nontraditional academic calendar with explicit sophomore completion date.

Expected:
- evaluator uses the exception rule,
- no traditional-calendar guess.

### Case F
Nontraditional/unknown calendar and required completion date absent.

Expected:
```text
needs_review
```

### Case G
Coach division missing/unverified.

Expected:
```text
needs_review
```

### Case H
Rule source missing for D2 scope.

Expected:
```text
needs_review
```
Never fall through to the D1 rule.

### Case I
Two equally specific contradictory active rules.

Expected:
```text
needs_review
```
and a configuration error logged/test failure.

### Case J
Rule not yet effective.

Expected:
- it is not selected before `effective_from`.

### Case K
Retired rule.

Expected:
- not selected for current decisions,
- still preserved historically.

## 29.2 Athlete-vs-coach messaging tests

### Athlete initiates message before coach recruiting window
Expected:
- athlete send is allowed under product policy,
- UI explains potential coach response restrictions.

### Coach initiates prohibited recruiting message
Expected:
- database rejects insert,
- stable compliance error,
- no row created,
- no notification created.

### Coach permitted message
Expected:
- insert succeeds,
- existing notification behavior works.

### Blocked conversation
Expected:
- existing block restriction still wins,
- recruiting changes do not bypass it.

### Unpublished athlete
Expected:
- existing coach-to-unpublished-athlete restriction remains.

### Message immutability
Expected:
- compliance metadata and body cannot be rewritten by the parties after send.

## 29.3 UI tests

Test:
- permitted status,
- prohibited status,
- needs-review status,
- source link visible,
- last-verified visible,
- next-date display,
- unavailable/network state,
- no generic “Contact allowed” when the evaluator only knows about one action type.

## 29.4 Regression tests

Verify:
- guardian consent,
- account signup,
- athlete profile publishing,
- college-interest CRUD,
- NCAA readiness save/load,
- block/unblock,
- message read receipts,
- notifications,
- coach approval,
- profile visibility.

---

# 30. Important Semantic Test: Dead/Quiet/Evaluation Periods

The architecture must not model recruiting periods as a universal “messaging off” switch.

Different recruiting periods regulate different activities.

A future calendar rule may affect:
- in-person contact,
- evaluation,
- visits,
without necessarily making otherwise-permitted electronic correspondence illegal.

Therefore the rule model must be action-specific from day one.

Even if Phase 1 does not fully implement all recruiting-period rules, add at least one unit test proving that an in-person restriction does not automatically prohibit an unrelated electronic action.

---

# 31. User-Facing Copy Principles

Avoid legalistic copy in the main UI.

Prefer:

```text
Coach recruiting messages
Not available yet

Under the rule currently matched to this program and athlete, coach recruiting correspondence begins June 1.

Why?
View official NCAA source
```

Avoid:

```text
Illegal
Violation
The NCAA says this coach is noncompliant
```

unless the source and context truly support that characterization.

For unknown:

```text
Needs review

We don't have enough verified information to determine this recruiting action. The Hub won't guess.
```

---

# 32. Observability

Add structured logging for:
- evaluator failures,
- conflicting rules,
- missing verified coach/program context,
- hard-block events,
- needs-review frequency.

Do not log:
- message body,
- unnecessary athlete personal data.

Useful aggregate metrics:
- evaluations by status,
- blocks by rule ID,
- needs-review by missing field,
- stale-rule warnings,
- last verified age of published rules.

These can later guide which rule coverage to add next.

---

# 33. Rule Freshness

A published rule should have a `last_verified_at`.

Add a stale threshold configuration, for example 180 days, but do not automatically declare a rule invalid solely because the threshold passes.

Instead:
- flag it operationally as requiring verification,
- optionally show “last verified” in the UI,
- keep the version history.

For rules tied to annual recruiting calendars, the operations process should verify the new calendar each cycle.

---

# 34. Acceptance Criteria

This project is complete only when all of the following are true.

## Architecture
- [ ] No universal June 15 authority remains in the iOS client.
- [ ] Recruiting rules are stored in Supabase.
- [ ] Rules are versioned and effective-dated.
- [ ] Rules have official source metadata.
- [ ] Evaluation is deterministic.
- [ ] No AI is used in the product.
- [ ] Unknown inputs return `needs_review`.

## Program context
- [ ] Verified coach-to-program context exists.
- [ ] Hard-blocking does not rely on free-text college names.
- [ ] Missing program context does not get guessed.

## Messaging
- [ ] Coach message enforcement exists at the backend/database boundary.
- [ ] Known prohibited coach messages are rejected.
- [ ] Athlete outreach remains available under the agreed product model.
- [ ] Existing blocked-pair rules still work.
- [ ] Existing published-athlete restrictions still work.
- [ ] Existing message immutability still works.

## NCAA Journey
- [ ] Current contact-date call is replaced.
- [ ] Journey renders action-specific recruiting status.
- [ ] Source and explanation are accessible.
- [ ] Existing eligibility readiness behavior remains intact.

## Colleges
- [ ] Current generic contact-window UI is replaced.
- [ ] Program-specific status is shown where context exists.
- [ ] Unknown programs show `needs_review`.

## Rules
- [ ] D1 men's basketball electronic-correspondence rule is sourced and tested.
- [ ] D1 women's basketball electronic-correspondence rule is sourced and tested.
- [ ] Nontraditional-calendar handling is represented.
- [ ] No D2/D3/NAIA/NJCAA rule is copied from another governing scope without an official source.
- [ ] Unsupported scopes return `needs_review`.

## Legal/product text
- [ ] `docs/legal/terms-of-service.md` is updated.
- [ ] `TheHub/Views/Legal/LegalView.swift` matches the canonical terms.
- [ ] Terms “last updated” date is changed.
- [ ] Repository search shows no obsolete “The Hub does not monitor recruiting contact” statement.
- [ ] Repository search shows no obsolete universal D1/D2 June 15 copy.
- [ ] External website terms update is completed or explicitly listed as a required deployment step if outside this repo.

## Tests
- [ ] SQL/database evaluator tests pass.
- [ ] Messaging enforcement tests pass.
- [ ] Swift model/service tests pass.
- [ ] UI states are tested.
- [ ] Regression tests for existing safety controls pass.

## Build
- [ ] iOS target builds successfully.
- [ ] Supabase migrations apply cleanly.
- [ ] Existing production data is not destroyed.
- [ ] Rollback/disable path exists through feature flag or migration plan.

---

# 35. Required Completion Report From Claude Code

When implementation is done, Claude Code must provide a final report in this format:

```text
IMPLEMENTATION SUMMARY

1. Architecture implemented
2. Files added
3. Files changed
4. Database migrations added
5. Rule sources used
6. Rules seeded
7. Scopes intentionally left as needs_review
8. Coach/program data migrated
9. Legal text changed
10. Tests added
11. Test results
12. Xcode/build results
13. Supabase migration results
14. Feature flags / rollout steps
15. Known limitations
16. Manual deployment steps
```

Do not consider the project complete if Claude only writes code but does not report which rules are actually sourced and which remain unknown.

---

# 36. Final Product Principle

The goal is not to make The Hub pretend it understands every recruiting rule.

The goal is to make it trustworthy.

When The Hub knows a verified rule:
- explain it,
- cite it,
- apply it consistently,
- and enforce it when The Hub controls the action.

When The Hub does not know:
- say so,
- show the best official source available,
- and do not guess.

That behavior should be consistent across NCAA Journey, Messaging, and Colleges, and the backend should remain the single authoritative decision boundary.
