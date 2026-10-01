# Native Coach Mode — Phase 2 Gap Analysis

**Prepared:** 2026-09-30 (repository inspection, read-only; no code changed)
**Repository:** `sccmavenger/the-hub-ios` at `2a45d10`
**Scope:** What exists after Coach Mode Phase 1, and what is needed for the
proposed Coach Workspace: **Home | Discover | Recruiting Board | Messages | Program**
**Status:** awaiting product decisions (§E) before any implementation

Constraints this analysis honors: no weakening of RLS, guardian/minor
protections, coach verification, block/report, or recruiting-compliance
enforcement; no AI features; no NCAA rules hard-coded into the app;
Supabase remains authoritative; Phase 1 architecture is preserved.

Related: `COACH-MODE-ONBOARDING-AND-VERIFICATION-SPEC.md` (Phase 1 spec),
`docs/RECRUITING-RULES-ENGINE-SPEC.md`, `docs/RECRUITING-RULE-MAINTENANCE.md`,
`GAP-ANALYSIS.md` (2026-09-11 web-parity analysis; §D6–D10 describe the web
app's coach features), `docs/TECH-DEBT.md`.

---

## A. Current State

Coach Mode today is an **entry point, not a workspace**.

An approved coach is routed by `AccountStateResolver` to `CoachTabView`
(`TheHub/Views/Main/MainTabView.swift`) with two tabs:

- **Home** (`CoachHomeView`): verified program card (institution, men's/women's
  basketball, association + division, title/role, verified date), a
  recruiting-rules note, and an Account link.
- **More**: Account, Sign Out.

What Phase 1 built and what must be preserved:

| Area | Where | State |
|---|---|---|
| Application lifecycle (pending / needs info / rejected / withdrawn / approved-but-paused) | `supabase/014-coach-onboarding.sql`, `Views/Coach/*` | complete |
| Admin review (approve / reject / request info / suspend / reinstate) | `Views/Admin/CoachApplication*`, `Services/CoachAdminService.swift` | complete, in iOS |
| Derived coach role (`sync_coach_role`, membership/program triggers, guards) | 014 | complete, applied to prod |
| Verified program context | `Services/CoachProgramService.swift` → `CoachProgramContext` | complete; `currentContext` = most recently verified |
| Rules-engine enforcement on coach sends | `supabase/013-*`: `trg_enforce_recruiting_rules` | complete; **shadow mode** (`recruiting_rules_enforcement_enabled = false`) |

What does **not** exist in the app: athlete discovery, the recruiting board,
a coach inbox, saved searches, notifications UI, program management, a program
switcher, coach-side preflight of recruiting decisions, profile-view recording
calls. Several of these exist in the database with no client (see §C, §D).

---

## B. Existing Building Blocks

### B1. Database (effective state after 014)

| Object | What it gives Phase 2 | Notes |
|---|---|---|
| `coach_saved_athletes` (setup.sql:252) | The recruiting board: `stage` check (watching/evaluating/contacted/offered/passed), `tags text[]`, `notes`, unique (coach, athlete), updated_at | Insert requires coach role + published athlete (014:966). Select/update/delete are owner-only by design (007:143–164) so revoked coaches can clean up. Trigger notifies the athlete + guardian-by-email on save (002:211–266). |
| `coach_saved_searches` (setup.sql:265) | `name`, `filters jsonb`, `alerts_enabled`, `last_run_at` | RLS: coach role + owner, all ops (002:407). Filter shape is defined only by the iOS `SearchFilters` model: `zip_code, radius, position, grad_year, min_height_inches, min_gpa, sport_gender, playing_within_days`. Nothing runs saved searches or sends alerts. |
| `messages` (setup.sql:276, 013:32) | Thread = (athlete_id, coach_user_id); `read_at`; compliance stamps `compliance_status/_rule_id/_rule_version/_evaluated_at` | Select: coach_user_id = me OR can_manage_athlete (setup.sql:584). Insert (007:94): sender = me AND ((coach = me AND coach role AND published) OR can_manage). Triggers: blocks (002:333), recruiting rules (013:185), notify (002:268), immutable except read_at (013:38). |
| `notifications` | `type, title, body, link` written by triggers/RPCs | Links are **web paths** (`/messages`, `/coaches/messages`, `/a/{athleteId}`, `/admin/coaches`, `/coach`). No client reads them. |
| `user_blocks`, `content_reports` (002) | Block/report with working RLS | Blocks are enforced **only** by the message-insert trigger. |
| `athletes` and media/events tables | Coach select = published AND coach role (setup.sql:421, 451, 465, 479) | **Whole row** is readable: DOB, guardian consent email/name, lat/long, zip, SAT/ACT, NCAA id. |
| `athlete_contacts` | Coach select = coach role AND published AND a `coach_saved_athletes` row (002:384) | This is the "save unlocks contact" rule. |
| `athlete_profile_views` | Written only by the `record-profile-view` edge function (service role) | Coach label = `coach_requests.college` (claim), not the verified program. |
| `recruiting_programs`, `coach_program_memberships` (010/014) | Program identity and verified membership | Coach reads own memberships only. |
| `athlete_ncaa_readiness`, `athlete_college_interests` | Not readable by coaches | Correct; keep. |
| Storage `athlete-media` | Private; coach read policy per **folder** of a published athlete or their guardian (002:447–464) | See §E security. |

### B2. RPCs a coach can call

| RPC | Purpose | Authorization |
|---|---|---|
| `evaluate_my_coach_action(p_athlete_id, p_action_type default 'coach_send_recruiting_electronic_correspondence')` (013:159) | **Preflight** that uses the exact program resolver the trigger uses | coach role AND published |
| `evaluate_recruiting_action(p_athlete_id, p_action_type, p_program_id, p_governing_body, p_division, p_evaluation_at)` (011:390) | Informational evaluation; `p_program_id` gives `verified_program` context | manager OR admin OR (coach AND published) |
| `coach_directory_names(uuid[])`, `bookmarks_for_athlete(uuid)` (004) | Label coaches for athletes | first has **no caller check** |
| `update_coach_application`, `withdraw_coach_application` (014) | Applicant self-service | own row |
| Edge `record-profile-view` | Logs a view (6 h dedupe, skips self/guardian) | any JWT; **no publish check** |

### B3. iOS code

**Reuse as-is**
- `AthleteService`: `fetchPhotos`, `fetchVideos`, `fetchEvents`, `fetchContact` (RLS gates it; returns nil when locked), `sendMessage` (already side-agnostic, maps `RECRUITING_ACTION_PROHIBITED`), `markThreadRead`, `recordProfileView` (never called today), `fetchCoachNames` (coach labels only).
- `SafetyService` (block/unblock/isBlocked/listBlocks/submitReport), `GeocodingService.geocodeZip` (zippopotam, no key), `CollegeDirectory` + `CrestLoader` + `CollegeCrestView`, `AppSettingsService`, `CoachProgramService`.
- Views: `RecruitingStatusView`, `RecruitingStatusBadge`, `RecruitingRuleSourceView`, `ReportSheet`, `LoadErrorState`, `CoachStatusPill`, all `HubFormFields`, `HubFormSection`.
- Models, present and **unused anywhere**: `CoachSavedAthlete` (+`pipelineStage`), `CoachSavedSearch`/`SearchFilters`, `MessageThread`, `AppNotification`, `UserProfile`, `PipelineStage` (with colors).

**Reuse with parameterization**
- `PublicProfileView` — its header comment names it as the base for the coach detail screen. Needs: a coach mode (title, no "unpublished" banner), honest contact-locked state (today it always renders the contact card and shows "No contact details added yet" to a coach who simply hasn't saved), Save-to-Board action, `recordProfileView` call, extraction of private `PhotoViewer`, `FlowChips`, `sectionCard`, `academicStat`, `contactRow`.
- `ThreadsView` / `ThreadDetailView` (`Views/Dashboard/ActivityDetailViews.swift`) — bubbles, compose bar, scroll, block/report scaffolding are right; but inbound detection is `sender == thread.coachUserId` (reversed for a coach), block target is the coach id (should be `athlete.userId`), and copy says "This Coach" throughout. Needs an "other party" abstraction.
- `RecruitingRulesService` — never sends `p_program_id`; cache key lacks program; nothing calls `evaluate_my_coach_action`.
- `RecruitingDecision.missingContextHint` — athlete wording only; coach keys (`coach.verified_program`, `.ambiguous`, `rule`) need copy.
- `fetchAthlete(userId:)` (coaches need by `id`), `fetchMessages(athleteId:)` and `unreadMessageCount` (need coach-scoped variants), `AccountView` blocked list (labels only coaches).
- `Message` model does not decode compliance stamps.

**Athlete-only, keep separate**
- `MessagesTabView` wrapper, `BookmarksView`, `DashboardView`, `InsightsView`, `NCAAJourneyView`, `CollegeListView` + `CollegeFormView`, `AthleteOutreachStatusView`, every write on athlete data, uploads, NCAA readiness, college interests, `fetchProfileViews`, `fetchBookmarks`, `profileViewCount`, `coachSaveCount`.

---

## C. Missing Capabilities

| Tab | Missing |
|---|---|
| **Home** | Board count, unread count, recent activity, notifications list (no notifications UI exists anywhere). |
| **Discover** | Any search surface. No search RPC; web did client-side haversine over a 500-row cap. No athlete card/row component. **No coach-safe column selection** (raw select returns DOB, consent email, coordinates). Saved-search CRUD and "run". "Playing within N days" needs an events join. Radius chips, position groups, grad year, min height/GPA, state/zip, name search (web §D7). |
| **Recruiting Board** | Any saved-athletes service. Stage chips with counts, per-card stage picker, tags (web ≤10) and private notes (web ≤2000) editors; DB has **no length/cardinality constraints**. CSV export (web) — later. |
| **Messages** | Coach inbox query grouped by athlete. Role-agnostic thread model. Preflight wiring to `evaluate_my_coach_action`. Coach-worded needs-review copy. Specific handling of block-trigger text and RLS denials (today generic alert). Routing of `/coaches/messages` notification link. Decode/display of compliance stamps (optional). |
| **Program** | Beyond the card: nothing. Staff list needs a new policy (coach reads own memberships only). Program switcher (blocked by RPC design, see §D contradictions). Program data is admin-owned; nothing for a coach to edit. |

Cross-cutting: profile-view coach label uses the claimed college (TECH-DEBT #28 class); `record-profile-view` has no publish check; no deep-link/notification routing in the app beyond auth callbacks.

---

## D. Recommended Architecture

Preserve Phase 1; add one layer per concern.

1. **`CoachWorkspaceService`** (new): saved athletes CRUD, saved searches CRUD, inbox (messages where `coach_user_id = me`, grouped by athlete), unread/board counts. Adopts the existing unused models. `CoachProgramService` remains the single source of program context.
2. **Server-side search RPC** `search_published_athletes(...)` (new migration): explicit **column allowlist** (no DOB, consent fields, coordinates, SAT/ACT, NCAA id, IG/TikTok unless decided), filters + radius math in SQL, excludes blocked pairs in both directions, row cap, optional events join for "playing within". Discover reads athletes **only** through this. A companion view/RPC for the coach detail screen with the same allowlist.
3. **Thread abstraction**: `MessageThread`-style value with an "other party" (user id, display name, avatar) so one `ThreadDetailView` serves both sides. Coach inbox = new fetch; sending reuses `sendMessage` unchanged.
4. **Preflight via `evaluate_my_coach_action`**, decoded into `RecruitingDecision`, separate cache key (or none), rendered by `RecruitingStatusView`. Database stays authoritative; on a server rejection, re-run preflight and show the server reason (rules spec §18). **No rule dates, divisions, or windows in Swift.**
5. **Coach mode on `PublicProfileView`** rather than a second profile screen; extract private subviews first.
6. **Program tab** = memberships joined to programs (works today) + whatever staff visibility is approved.
7. **Notifications** (if approved): `AppNotification` model exists; needs a list view and a `link` → in-app route mapper for both roles.

### Where the current implementation contradicts the proposed workspace

1. **Board ownership.** The Phase 1 spec speaks of program-level data ownership and shared staff boards; `coach_saved_athletes` / `coach_saved_searches` are keyed to `coach_user_id` only. A shared board needs `program_id` on those tables plus new policies and a migration of existing rows.
2. **Multiple programs.** `CoachProgramService.currentContext` picks the most recently verified membership, but `recruiting_enforce_coach_action` returns `needs_review` for any coach with >1 verified program matching the athlete's gender, and `evaluate_my_coach_action` has **no program parameter**. A "Switch Program" UI cannot change enforcement without an RPC change.
3. **Replies before the window.** The trigger evaluates every coach send as `coach_send_recruiting_electronic_correspondence` (013:192) and never inspects the thread. The published `coach_send_nonrecruiting_response` rule (012, rule 7) is used by no enforcement path. Once enforcement is ON, a coach cannot reply even "contact admissions" to an athlete who wrote first.
4. **Admin precedence.** `AccountStateResolver` routes admin above coach, so an account holding both roles never sees Coach Mode (including the real admin if approved as a coach for testing).
5. **Notification links are web paths** and the app has no notification UI or router.
6. **Contact card copy** in `PublicProfileView` is misleading for a coach who hasn't saved the athlete.
7. **App Store questionnaire**: "Social media capability: **No**" is justified in `docs/APPSTORE-CONNECT-FIELDS.md` by "no discovery". A coach athlete directory is discovery of user-generated content (by vetted adults). The answer, review notes, and possibly age-rating basis need re-evaluation before Discover ships.
8. **Media URLs** are 1-year signed URLs stored in DB (TECH-DEBT #6). Discover multiplies coach media reads and makes this the primary exposure path for minors' photos after unpublish/block.

---

## E. Product Decisions Needed

### E1. Security and minors — decide before Discover ships

| # | Finding (verified in repo) | Decision needed | Recommendation |
|---|---|---|---|
| 1 | Coach select on `athletes` returns **every column**: DOB, guardian consent email/name, lat/long, zip, SAT/ACT, NCAA id (setup.sql:421; no column grants). Web hid DOB/SAT/ACT/NCAA-id from its public payload. | Which columns may coaches see at all? | Allowlist enforced by the search RPC + a coach view; never raw table selects from Discover. |
| 2 | **Blocks are enforced only on message insert** (002:333). A blocked coach still reads profile, media, events, storage, and (if previously saved) contacts. Guardian blocks are ignored by the trigger. | Should a block hide the athlete from the coach everywhere? Should guardians' blocks count? | Yes to both: filter blocked pairs in the search RPC and add block checks to coach read policies (or a helper). |
| 3 | **Storage policy is per folder**, not per photo row (002:447–464). A guardian with one published and one unpublished child exposes both children's files under the guardian's uid folder. | Fix via per-row policy or the "store path, sign on read" approach (TECH-DEBT #6)? | Treat as a live S1 regardless of Phase 2; fix in 2A. |
| 4 | **Revoked/suspended coach keeps read access** to old threads (incl. minors' message history) and board rows: policies are owner-only by design (007/014). | Keep reads for cleanup, or end reads with the role? | End select/update with the role; keep delete owner-only for cleanup. |
| 5 | `notify_coaches_of_interest` targets `coach_requests.status = 'approved'`, not the role (002:148–154). Suspending a membership does not change request status, so a suspended coach still receives athlete names/positions/grad years. | Approve the fix. | Key on `has_role`-equivalent (membership-derived). Small migration. |
| 6 | `coach_directory_names` has no caller check; `athlete_is_published()` and other helpers have default PUBLIC execute (callable via `/rpc`) → existence/publication oracles. `record-profile-view` accepts any athlete id without a publish check (404 vs ok reveals existence; TECH-DEBT #9). | Approve tightening. | Revoke helper execute from anon/authenticated where not needed; require a shared thread for name lookups; publish check in the edge function. |
| 7 | Notification bodies carry up to 120 chars of message text (002:287/292/297), while the audit log deliberately stores no bodies. | Acceptable? | Probably yes (recipient-only), but confirm. |
| 8 | An athlete/guardian can insert a message with **any** `coach_user_id` (the manager branch doesn't check the recipient is a coach) (007:102). | Approve a recipient check. | Require recipient to hold the coach role (or have a verified membership). |

### E2. Product scope

1. **Board ownership**: per-coach (ship now) or program-shared (schema change)?
2. **Discover filters for v1** and **server RPC vs client-side haversine** (web parity was client-side over ≤500 rows). Recommendation: server RPC (data minimization for minors + performance).
3. **Saved-search alerts**: build the server job, or ship saved filters only?
4. **Coach replies before the window**: allow a coach-declared non-recruiting reply (evaluated as `coach_send_nonrecruiting_response`), or block all and point to email/admissions? This is a compliance call; the engine deliberately does not read message content.
5. **Turn enforcement ON when Messages ships?** With Discover + coach messaging live, shadow mode means prohibited messages reach minors and are merely stamped `prohibited`.
6. **Multi-program coaches**: add a program parameter to the preflight/trigger path and a switcher, or defer and document single-program behavior?
7. **Native notifications list** in Phase 2 (both roles) or later?
8. **Games near me** (web D8) and **CSV export** (web D9): Phase 2 or later?
9. **Tag/notes limits** as DB constraints (web: tags ≤10, notes ≤2000)?
10. **Staff visibility on Program tab**: may a coach see other verified members of their program?
11. **App Store**: who revisits the "Social media capability" answer, review notes, and age-rating basis for the Discover build?

---

## F. Proposed Implementation Phases

Each phase: builds, its tests pass, lands in its own commit; migrations applied to prod via `scripts/db-query.sh` with DO-block tests run as the `authenticated` role (pattern: `supabase/tests/coach-onboarding.test.sql`). Nothing starts before §E decisions.

| Phase | Scope | Depends on |
|---|---|---|
| **2A — Backend hardening & coach read surface** | Migration 015: `search_published_athletes` RPC with column allowlist, block-aware filtering, row cap, optional events join; coach detail view/RPC with same allowlist; storage per-row policy or sign-on-read; interest notifications keyed on role; `record-profile-view` publish check + verified-program label; tighten `coach_directory_names` and helper grants; message recipient check; revoked-coach read decision. SQL tests for every policy. | E1 decisions |
| **2B — Coach data layer (iOS)** | `CoachWorkspaceService`; coach-scoped message fetch + unread; `RecruitingRulesService.evaluateMyCoachAction` with program-aware caching; thread abstraction; `Message` decodes compliance stamps; unit tests (grouping, mapping, decoding). | 2A |
| **2C — Discover + athlete detail** | Search screen with filters, saved searches CRUD/run, athlete card component, coach mode on `PublicProfileView` (save, record view, honest contact-locked state), extraction of shared subviews. | 2B, E2 #1–3 |
| **2D — Recruiting Board + Home counts** | Stage chips, stage picker, tags/notes with limits, Home tiles (board size, unread). | 2B |
| **2E — Messages** | Coach inbox, shared `ThreadDetailView`, preflight display per rules spec §18, block/RLS error handling, `/coaches/messages` routing. Enforcement-flag decision applies here. | 2B, E2 #4–6 |
| **2F — Program tab + release prep** | Program card + memberships, staff list (if approved), program switcher (if approved), App Store questionnaire + review notes, legal/privacy review for discovery, TECH-DEBT + STATUS updates. | 2C–2E, E2 #10–11 |

Urgent independent of Phase 2 scheduling: **E1 #3 (storage folder-level policy)** is a live exposure path today.

---

## Appendix 1 — Effective RLS and triggers relevant to coaches (verified 2026-09-30)

Helpers (setup.sql, all `security definer`): `has_role(text)`, `owns_athlete`, `is_guardian_of`, `can_manage_athlete` (= owns OR guardian OR admin), `athlete_is_published`. None has its PUBLIC execute revoked.

| Table | select | insert | update | delete |
|---|---|---|---|---|
| athletes | `user_id = auth.uid() or is_guardian_of(id) or has_role('admin') or (is_published and has_role('coach'))` | `user_id = auth.uid()` | owner/guardian/admin | owner/admin |
| athlete_photos / _videos / _events | `can_manage_athlete or (athlete_is_published and has_role('coach'))` | manage | manage | manage |
| athlete_contacts | `can_manage_athlete or (has_role('coach') and athlete_is_published and exists saved row)` | manage | manage | manage |
| athlete_college_interests, athlete_ncaa_readiness, athlete_guardians | managers (admin may read readiness) | — | — | — |
| coach_saved_athletes | `coach_user_id = auth.uid()` | `coach_user_id = auth.uid() and has_role('coach') and athlete_is_published` | owner | owner |
| coach_saved_searches | owner AND coach role (all ops) | | | |
| messages | `coach_user_id = auth.uid() or can_manage_athlete` | `sender = auth.uid() and ((coach = auth.uid() and has_role('coach') and published) or can_manage_athlete)` | same as select; immutability trigger allows `read_at` only | none |
| notifications | owner | none (triggers/RPCs only) | owner | owner |
| user_blocks | blocker (all) + admin select | | | |
| content_reports | reporter insert/select; admin select/update | | | |
| athlete_profile_views | managers select; no client insert | | | |
| user_profiles | own + admin | — | own | — |
| recruiting_programs | authenticated read; admin write | | | |
| coach_program_memberships | own + admin read; admin write (guards in 014) | | | |
| storage `athlete-media` | owner folder; admin; coach if folder owner is a published athlete's user **or any guardian of a published athlete** | owner folder | owner folder | owner folder |

Message triggers in order: `trg_enforce_message_blocks` (BEFORE), `trg_enforce_recruiting_rules` (BEFORE; coach sender only; stamps or raises `RECRUITING_ACTION_PROHIBITED` when flag ON + prohibited + hard_block + verified_program), RLS, `trg_notify_on_message` (AFTER), `trg_message_immutable` (BEFORE UPDATE).

## Appendix 2 — Rules engine facts Phase 2 depends on

- Preflight RPC: `evaluate_my_coach_action` → `recruiting_enforce_coach_action` → program = the single verified membership whose program is active, verified, basketball, and matches the athlete's gender. 0 or >1 → `needs_review` (`coach.verified_program` / `.ambiguous`). Never uses `coach_requests.college`.
- Decision JSON keys: `status, action, actor, reason, user_message, next_permitted_at, next_permitted_on, rule_time_zone, enforcement, missing_context, conflict, governing_body, division, sport, sport_gender, context_source, evaluated_at, rule_id, rule_key, rule_version, source_title, source_url, source_reference, effective_from, effective_until, last_verified_at` (+ `program_id` on the 013 path). `context_source ∈ {verified_program, unverified_program, client_supplied, none}`.
- Seeded rules (012, NCAA D1 basketball): coach electronic correspondence men's (June 15 grad−2, hard_block) / women's (June 1, hard_block) / women's nontraditional; coach phone call men's/women's (informational); athlete intro message (permitted); coach non-recruiting response (permitted_with_restrictions, informational, **unused by enforcement**). Other action types (off-campus contact, evaluations, visits, institution materials) exist in Swift but have no rules → `needs_review`.
- Flags: `recruiting_rules_engine_enabled` gates only the client; the trigger ignores it. `recruiting_rules_enforcement_enabled` gates the hard block; shadow mode still stamps and audits.
- Hard-block rejections lose their audit row (TECH-DEBT #26).
- iOS: `RecruitingRulesError.fromServerError` maps the PostgREST error (`message == "RECRUITING_ACTION_PROHIBITED"`, `details` = decision JSON, `hint` = user message). `AthleteService.sendMessage` already rethrows it.

## Appendix 3 — Web app (athlete-connect) coach features for parity reference

From `GAP-ANALYSIS.md` §D6–D10 (2026-09-11): public athlete profile hides DOB/SAT/ACT/NCAA-id; coach directory with place (state/zip/city), radius chips 10–250 mi with haversine sort, position groups, grad year, min height/GPA, name search, "playing" date windows (weekend/7d/30d) joined to events, save-search, save-to-pipeline, 500-row cap; games near me (ZIP + radius + date window + MAYB-only, ICS export); pipeline with stage chips + counts, tags ≤10, notes ≤2000, CSV export; coach inbox mirroring the athlete side; `list-approved-coaches` picker.
