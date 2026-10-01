# The Hub — Coach Mode Workspace
## Claude Code Implementation Specification (Phase 2)

**Repository:** `sccmavenger/the-hub-ios`
**Primary client:** iOS / SwiftUI · **Backend:** Supabase / PostgreSQL
**Prepared:** 2026-10-01 (Danny + Claude, from `COACH-MODE-PHASE2-DECISIONS.md` and `COACH-MODE-PHASE2-GAP-ANALYSIS.md`)
**Status:** Phase 2A (§6–§7 backend, media) **implemented 2026-10-01** in `supabase/015`, `supabase/016`, `record-profile-view` v2, `MediaService`/`HubRemoteImage`. Phase 2B (§5 program context, §9.1–§9.2/§9.5–§9.6 board data, §15 data layer) **implemented 2026-10-01** in `supabase/017`, `CoachProgramService` selection + `CoachProgramSwitcherView`, `CoachWorkspaceService` + `CoachWorkspaceModels`. Phase 2C (§8 Discover, athlete detail, save/contact unlock, saved searches, profile-view recording) **implemented 2026-10-01** in `supabase/018` (search items carry `board_stage`/`next_event_date`), `CoachDiscoverView`, `DiscoverFiltersSheet`, `SavedSearchesView`, `CoachAthleteDetailView`, `AthleteCardView`, `HubPhotoPager`. Phase 2D (§9.3–§9.4 Board UI, §10 Home, §11 Program tab, §17 docs) **implemented 2026-10-01**: `CoachBoardView`, `TagEditor`/`StageChipBar`, detail board section (tags, assignee, private note, activity), `CoachHomeView` on `coach_home_summary`, `CoachProgramView` (switcher, staff roster, membership, account), four-tab `CoachTabView`. **Release 2.0 code complete**; release gates still open: App Store "Social media capability" re-answer (TECH-DEBT #40), demo coach + athlete accounts (#18/#29), website privacy/terms copy (#13/#22). **Release 2.1 — Phase 2E (Messages) implemented 2026-10-01**: `supabase/019` (program-scoped sends, `send_coach_message` with durable `recruiting_denied_attempts`, `evaluate_my_coach_action(p_program_id)`, `coach_inbox`, blocked/revoked read cut-off, `user_settings.show_message_previews`, `notifications.destination`), `CoachInboxView`, `CoachThreadView` (preflight via `RecruitingStatusView(coachMode:)`, Send disabled on hard-block when enforcement is ON, shadow-mode warning otherwise), Messages tab. **Phase 2F implemented 2026-10-01**: `supabase/020` (typed `destination` for every notification via a BEFORE INSERT trigger mapping legacy `link`s, `mark_notifications_read`, `unread_notification_count`, Discover refactored into `coach_search_athletes_internal` shared with `run_saved_search_alerts()` — `pg_cron` job `saved-search-alerts` hourly at :15, opt-in, baseline-seeded, deduped by `notified_athlete_ids`, eligibility re-checked every run), `NotificationsView` + `NotificationBellButton` (Coach Home and athlete Dashboard toolbars), `NotificationService`/`UserSettingsService`, "Show message previews" toggle in Account, live alerts toggle in `SavedSearchesView`. **Enforcement flag ON in prod since 2026-10-01 16:05 UTC** (8 SQL suites + 55 Swift tests green first). **Release 2.1 code complete.** **Amendment 2026-10-01 (TestFlight feedback, `supabase/021`)**: contact unlock (D25) now withholds a **minor's** own email and phone from coaches — only guardian and club-coach details unlock; adults 18+ unchanged; coaches read contacts solely through `coach_athlete_detail` (the `athlete_contacts` coach RLS branch is gone). See `docs/FEEDBACK-BACKLOG.md` F2 and `docs/COACH-MODE-TEST-CASES.md` for the device script. Note: `PublicProfileView` keeps its private photo viewer/chips; the coach detail is a separate view over the allowlisted payload (routine call — the athlete-side view fetches tables coaches can no longer read). Sections marked **[routine call]** are choices Claude made where the decision record was silent; overrule by editing.
**Implementation notes (2A):** migration order is 015 = media paths, 016 = security (the detail RPC needs the path column). No SQL signing RPC exists — Supabase signs in the Storage service — so the per-row `storage.objects` policies are the authorization boundary and the client requests 60-minute signed URLs directly (§7 amended). Helper EXECUTE grants cannot be revoked from `authenticated` because RLS evaluates helpers as the caller; `athlete_is_published()` instead returns false for callers with no coach/admin/manager relationship (§6.5 amended).
**Scope:** Release **2.0** = security foundation, program context, Discover, shared Recruiting Board, contact unlock, Home. Release **2.1** = Messages, Notifications, saved-search alerts.
**Out of scope:** Event Mode (games/tournament browsing), CSV export, AI features, pre-window message templates, program-wide blocks, Admin/Coach switching.

---

# 0. Instructions to Claude Code

Read this entire specification before making changes. Inspect the repository first; the facts in §3 were verified on 2026-10-01 and must be re-verified against `main` before coding.

This is a continuation of Coach Mode Phase 1 (`COACH-MODE-ONBOARDING-AND-VERIFICATION-SPEC.md`, shipped 2026-09-30 in migration 014 and `Views/Coach`, `Views/Admin`). **Preserve Phase 1**: the application lifecycle, admin review, derived coach role (`sync_coach_role`), guards, `CoachProgramService`/`CoachProgramContext`, and `AccountStateResolver` are inputs, not things to redesign.

Authority order when documents disagree: this spec → `docs/COACH-MODE-PHASE2-DECISIONS.md` (the 30 decisions, cited here as **D#**) → `docs/COACH-MODE-PHASE2-GAP-ANALYSIS.md` → `GAP-ANALYSIS.md` (web parity, 2026-09-11).

Hard constraints (from D1–D30 and Phase 1):
- Supabase is authoritative. The client never decides authorization, visibility, or recruiting compliance.
- Do not weaken RLS, guardian/minor protections, coach verification, block/report, or recruiting-rule enforcement.
- No AI features. No NCAA rules in Swift; the rules engine (010–013) is the only source.
- Admin is an exclusive role (D24). No Admin/Coach switcher.
- Per-phase delivery: each phase builds, passes its tests, lands in its own commit, and **waits for Danny's go-ahead before the next phase starts**. Migrations are applied to prod with `scripts/db-query.sh` and their DO-block tests run as the `authenticated` role.
- Report honestly. If a phase is partial, say which parts.

---

# 1. Product Goal

Give a verified college coach the daily recruiting workflow inside the app:

```text
choose program → discover athletes → evaluate profile and schedule → save to the program's shared board
→ collaborate with staff → (2.1) message within the applicable rules → (2.1) get useful notifications
```

A coach does all of this under one explicitly chosen verified program. Every read and write is scoped to that program and re-authorized server-side.

## 1.1 Release shape

| Release | Tabs | Contains |
|---|---|---|
| **2.0** | Home · Discover · Board · Program | §6 security foundation, §7 media model, §5 program switcher, §8 Discover + athlete detail + contact unlock, §9 shared Board with private notes, §10 Home, §11 Program/staff, §12 athlete-side corrections |
| **2.1** | + Messages, + bell | §13 Messages, Notifications center (both roles), saved-search alerts |

Why two releases (Danny, 2026-10-01): 2.0 is a complete find–evaluate–save workflow on its own; messaging carries the enforcement-ON decision, durable audit, a scheduler, and athlete-side UI, each of which can slip. Apple also reviews discovery and adult-to-minor messaging as separate changes.

No placeholder tabs. In 2.0, if a coach has unread athlete-initiated threads, Home shows one line: "Messages arrive in the next update." Otherwise nothing.

---

# 2. Locked Decisions

## 2.1 From `COACH-MODE-PHASE2-DECISIONS.md` (D1–D30)
All 30 are inputs. Those that shape 2.0 most: D1–D3 media first and path-based; D4 blocks remove all access; D5 suspended coaches lose reads; D6 interest routing by verified membership; D7 only authorized profile views; D8 tighten helpers/RPCs; D11 program-owned shared board + separate private notes; D12 server-side Discover only; D16 explicit Program Switcher; D19 Discover filter set and safe fields; D21 10 tags / 2,000-char notes in UI and DB; D22 staff roster; D24 admin exclusivity; D25 board save unlocks contact; D26 blocks remove board visibility, no auto-restore on unblock; D27 saved searches personal + program-scoped; D30 non-destructive board migration.

## 2.2 Decided 2026-10-01 (Danny, one question at a time)

| # | Decision |
|---|---|
| W1 | **Two releases**: 2.0 without Messages; 2.1 adds Messages, Notifications, alerts. |
| W2 | **Four tabs in 2.0**, Messages appears in 2.1. Home shows "Messages arrive in the next update" only when unread threads exist. |
| W3 | **Block scope = athlete (or guardian) blocks one coach, everywhere.** That coach loses the athlete in Discover, detail, media, contacts, board visibility, and (2.1) messaging. Teammates unaffected. Program-wide block is a possible later addition, not 2.0. |
| W4 | **Assignment = one optional "assigned to" staff member per board entry**, settable/clearable by any active staff member, shown on the card, filterable as "Mine". No assignment notifications in 2.0. |
| W5 | **Board permissions = any active verified staff member can save, change stage, edit tags, assign, remove.** Every change is written to a board activity log. Private notes are author-only. |
| W6 | **Athlete sees program + coach**: "Saved by" and the save notification show the verified program name and the saving coach's name. Stage, tags, notes, assignee are never shown to athletes. |
| W7 | **Media fix in full in 2.0**: object paths stored, ~1-hour signed URLs issued at read time by an authorized RPC, images cached by path, storage policy checks the photo row not the folder, existing 10 photos backfilled by parsing their signed URLs and verifying each object. |
| W8 | **Profile views: record detail-screen opens only**, deduped 6 h per coach per athlete (existing), labeled with the verified program, via the hardened edge function. Results impressions are not views. |

## 2.3 Carried into 2.1 — **confirmed by Danny 2026-10-01** (all four accepted as a package)
- **No template system.** Pre-window coach sends are blocked and show the rule, source, and opening date. D14 permits "no exception offered."
- **`needs_review` = allowed with a visible warning** (current Phase 1 policy; D15 "distinct").
- **All coach sends go through one RPC** (`send_coach_message`) that evaluates, writes the audit row, and returns a structured denial *without raising*, so denied attempts persist (D29). The 013 trigger stays as the final guard for direct inserts.
- **`messages.program_id`** (sender's representing program), set by the RPC, validated by the trigger (D16).
- **Enforcement flag ON** as part of the 2.1 launch configuration, after the 2.1 test gate (D15). **Done 2026-10-01.**
- **Alerts need `pg_cron`** — enabled 2026-10-01 (`pg_cron` 1.6.4); job `saved-search-alerts` scheduled by 020.

---

# 3. Current Repository State (verified 2026-10-01)

Claude must re-confirm these on `main` before coding.

- `CoachTabView` (`Views/Main/MainTabView.swift`) has two tabs: Home (`CoachHomeView`) and More.
- `CoachProgramService.currentContext` = most recently verified membership; **no persisted selection**.
- `coach_saved_athletes` (setup.sql) is per-coach: `stage` check (watching/evaluating/contacted/offered/passed), `tags text[]`, `notes`, unique (coach_user_id, athlete_id). Insert requires coach role + published (014). Select/update/delete owner-only (007). **0 rows in prod.**
- `coach_saved_searches`: `filters jsonb`, `alerts_enabled`, `last_run_at`; owner + coach role (002). **0 rows in prod.** iOS `SearchFilters` keys: `zip_code, radius, position, grad_year, min_height_inches, min_gpa, sport_gender, playing_within_days`.
- `athlete_contacts` select for coaches = coach role AND published AND a `coach_saved_athletes` row (002:384).
- Coach select on `athletes`/photos/videos/events = published AND coach role; **every column** returned (no column grants).
- Media: `athletes.profile_photo_url` and `athlete_photos.url` hold **1-year signed URLs** (`AthleteService.signedURL`, 365 d). Bucket private; coach storage policy is **per folder** (002:447–464). Prod: 1 athlete, 10 photos, 11 storage objects, 0 videos.
- Blocks (`user_blocks`) enforced **only** by the message-insert trigger. Guardians' blocks ignored there.
- `notify_coaches_of_interest` keys on `coach_requests.status = 'approved'` and claimed college.
- `record-profile-view` edge function: no publish/block check; coach label = `coach_requests.college`. Never called by the app.
- `coach_directory_names` has no caller check; setup.sql helpers (`has_role`, `athlete_is_published`, …) have default PUBLIC execute.
- `messages` select/update keyed on `coach_user_id = auth.uid()` (revoked coach keeps reading). Athlete-side insert does not check the recipient is a coach.
- Notifications `link` are web paths; no client reads notifications.
- Roles: 1 admin, 0 mixed-role accounts. Extensions: no `pg_cron`, `pg_net`, `earthdistance`, `postgis`.
- Tests: `supabase/tests/*.test.sql` (4 suites), `TheHubTests/CoachOnboardingTests.swift` (17), `RecruitingRulesTests.swift` (13).

---

# 4. Navigation & Shell

```text
CoachTabView (2.0)
├─ Home      (house)                 §10
├─ Discover  (magnifyingglass)       §8
├─ Board     (rectangle.stack)       §9
└─ Program   (building.columns)      §11
More (Account, Legal, Sign Out) moves into Program → "Account" row and Home toolbar  [routine call]
2.1 adds: Messages (message) tab; bell in every tab's toolbar.
```

- Every coach screen renders inside the **selected program** (§5). A program chip (short institution name · Men's/Women's) sits in the navigation bar title area of Home, Discover, Board; tapping it opens the switcher.
- **Revoked state**: if `CoachProgramService` returns zero valid contexts while the coach role is present (race during suspension), every tab shows `CoachAccessUnavailableView` ("Your program access is being updated") with Retry and Account. The resolver already routes a role-less account to the paused screen; this covers the in-session window.
- Loading / empty / error / retry states are required on every list and detail. Empty states say what to do next, never show zeros as if they were data.
- All existing dark-theme components (`HubFormFields`, `LoadErrorState`, `CollegeCrestView`, `RecruitingStatusView`) are reused. New shared components live in `Components/` (see §16).

---

# 5. Program Context & Switcher (D16, W-)

## 5.1 Selection
- `CoachProgramService` gains `selectedContext: CoachProgramContext?` and `select(_:)`. Selection persists per user in `UserDefaults` (`coach.selectedProgramId.<userId>`) **[routine call]**.
- On launch / refresh: if the persisted id is among current valid contexts → select it. Else if exactly one context → select it. Else (several, none persisted) → **present the switcher modally** before any tab loads; do not silently pick the newest (D16).
- Switching clears every coach cache (search results, board, home summary, media URL cache for that program's views) and cancels in-flight tasks via `.task(id: selectedProgramId)`.

## 5.2 Server validation
Every coach RPC takes `p_program_id uuid` and starts with:
```sql
perform coach_assert_program(p_program_id);  -- raises 'not authorized' unless
-- exists verified membership for auth.uid() in that program, program.active, program.verified_at not null
```
Direct table reads for program-scoped tables use the same predicate in RLS (`coach_has_program(program_id)`).

## 5.3 Switcher UI (`CoachProgramSwitcherView`)
List of valid contexts: institution, program label, division label, title/role, "Current" badge. Tap selects and dismisses. Footer: "Changing schools? Contact {HubSupport.email}." No add/remove here (admin-owned).

---

# 6. Security Foundation (Release 2.0, Phase 2A)

Migration **015-coach-workspace-security.sql**. All items below are mandatory before any Discover UI ships (D1).

## 6.1 Authorization matrix (documented in the migration header and `docs/COACH-MODE-AUTHZ.md`)

| Operation | Checks (all must pass) |
|---|---|
| Coach reads athlete card/detail | authenticated · coach role · verified membership in `p_program_id` · athlete published · program sport_gender = athlete sport_gender (or athlete null → excluded from Discover, allowed in detail only if already on board **[routine call]**) · not blocked (§6.3) |
| Coach reads media | as above, resolved per photo row (§7) |
| Coach reads contact | as above **and** board entry exists for `p_program_id` and athlete (D25) |
| Coach board write | authenticated · coach role · verified membership in entry's program |
| Coach private note | owner only |
| Athlete/guardian reads "saved by" | `can_manage_athlete` |
| Profile view record | edge fn: publish · block · active coach · membership → label |

## 6.2 Safe-field allowlist (D12, D19)
Coach-facing payloads expose **only**:
`athlete_id, full_name, profile_photo_path, high_school, hometown, state, grad_year, position, jersey_number, height_inches, weight_lbs, gpa, bio, intended_major, instagram_handle, tiktok_handle, sport_gender, is_published, distance_miles (rounded to nearest 5, only when a radius search supplied a center)`.
**Never**: `user_id, date_of_birth, sat_score, act_score, ncaa_id, zip_code, latitude, longitude, guardian_consent_*, academic_calendar_type, sophomore_completed_on, email`.
**[routine call]** Social handles are included because the athlete entered them for coaches; strike them if you disagree.
Implemented as a view `coach_athlete_card_v` + RPCs; the coach branch of the `athletes` select policy is **removed** (coaches no longer read the table directly). Photos/videos/events coach branches gain the block check and stay (needed by detail RPC; detail RPC is the client path).

## 6.3 Blocks everywhere (D4, D26, W3)
```sql
create function coach_is_blocked(p_athlete_id uuid) returns boolean  -- stable, security definer
-- true if exists user_blocks where blocked_user_id = auth.uid()
--   and blocker_user_id in (athlete owner, any athlete_guardians.user_id for the athlete)
```
Applied to: search RPC, detail RPC, photos/videos/events coach policies, contacts coach policy, storage coach policy, board entry visibility (hidden from the blocked coach; colleagues still see it), profile-view function, and in 2.1 messaging. The message-block trigger is extended to consider guardians.
Unblock does **not** restore anything automatically beyond visibility of rows that still exist; a board entry removed because of a block (if the program chooses to remove it) stays removed (D26). **[routine call]** 2.0 does not auto-remove board entries on block; it hides them from the blocked coach and shows colleagues a "Blocked this coach" marker on the card.

## 6.4 Revocation (D5)
- `coach_saved_athletes` legacy policies unchanged (table retired, §9.6). New board tables require verified membership for select/update; delete of **own** entries remains allowed for cleanup after revocation **[routine call]**.
- 2.1 changes `messages` select/update to require coach role (§13).

## 6.5 Helpers and lookups (D8)
- `revoke execute on function has_role, owns_athlete, is_guardian_of, can_manage_athlete, athlete_is_published from public, anon, authenticated` (they are only used inside policies/definer functions).
- `coach_directory_names`: require a shared message thread or board relationship with each requested user; otherwise omit.
- `evaluate_recruiting_action`: unchanged (already authorized).

## 6.6 Admin exclusivity (D24)
- BEFORE INSERT trigger on `user_roles`: if inserting `admin` and other roles exist, or inserting another role when `admin` exists → raise. `approve_coach_request` rejects applicants holding admin. One-time audit query reports conflicts (expected 0).

## 6.7 Interest notifications (D6)
`notify_coaches_of_interest` targets users with a **verified membership** in a verified program whose `normalized_institution_name` matches the normalized college name; excludes blocked coaches.

## 6.8 Profile views (D7, W8)
`record-profile-view` edge function: require `is_published`, not blocked, active coach role; `viewer_label` = program label from the caller's `p_program_id` membership (passed in the body, validated). Non-coach viewers unchanged. 404 replaced by a uniform 204 to stop existence probing (TECH-DEBT #9).

## 6.9 Recipient validation for athlete sends (D9)
`messages insert` manager branch additionally requires `coach_user_id` to hold the coach role (helper `is_active_coach(uuid)`). Lands in 015 even though the coach inbox is 2.1.

---

# 7. Media Model (D1–D3, W7)

Migration **016-media-paths.sql** + iOS `MediaService`.

- Columns: `athlete_photos.storage_path text`, `athletes.profile_photo_path text`. `url` columns kept (legacy), no longer written.
- **Backfill**: parse `/storage/v1/object/sign/athlete-media/<path>?token=` from existing URLs; verify `storage.objects` has the path; set `storage_path`; report rows that fail to parse or verify (expected 0 of 11). Nothing deleted.
- **Uploads** (`ProfileEditViewModel`) store the path, not a URL.
- **Reads**: `media_signed_urls(p_paths text[], p_program_id uuid default null) returns jsonb` — for each path, resolves the owning row (photo or profile) and applies §6.1; returns `{path: url}` with **60-minute** expiry **[routine call: 60 min balances revocation vs refetch]**. Owners/guardians/admins pass; coaches pass only with program + published + not blocked.
- **Storage policy**: coach select requires the object path to exist in `athlete_photos.storage_path` or `athletes.profile_photo_path` of a published, unblocked athlete. The folder-based clause is dropped (fixes TECH-DEBT #32).
- iOS: `MediaService.url(for path:)` memoizes `(url, expiresAt)`; Kingfisher uses `cacheKey = path` so a new signed URL hits the same cache. All current `KFImage(URL(string: athlete.profilePhotoUrl))` call sites switch to the resolver (Dashboard, ProfileEdit, PublicProfile).
- Residual limit (documented, D-4.1): an already-issued URL stays valid up to 60 min after a block/unpublish.
- Verification: existing athlete photos render in Dashboard/Profile/Public preview after migration; a signed-out `curl` of a stored legacy URL is still valid (known, expires within a year) — **record this** and schedule the legacy `url` columns to be nulled in 2.1 once all clients are on paths **[routine call]**.

---

# 8. Discover (D12, D18, D19, D25, W8)

## 8.1 Search RPC
```sql
search_published_athletes(
  p_program_id uuid,
  p_query text default null,            -- name, ilike, trimmed
  p_positions text[] default null,      -- matches athletes.position (free text today) case-insensitively  [routine call: no position taxonomy in 2.0]
  p_grad_years int[] default null,
  p_center_lat double precision default null,  -- coach's search center (geocoded ZIP, client-side via existing GeocodingService)
  p_center_lng double precision default null,
  p_radius_miles int default null,      -- one of 25, 50, 100, 150, 250
  p_states text[] default null,
  p_min_height_in int default null,
  p_min_gpa numeric default null,
  p_playing_within text default null,   -- 'weekend' | '7d' | '30d'  (athlete_events.event_date in window, America/Chicago  [routine call])
  p_cursor text default null,           -- keyset: (sort key, athlete_id)
  p_limit int default 25
) returns jsonb  -- { items: [coach_athlete_card...], next_cursor, total_estimate }
```
Rules: program membership asserted; `sport_gender` forced to the program's; published only; `not coach_is_blocked`; haversine in SQL; athlete coordinates never returned; sort = distance when a center is given, else `full_name` **[routine call]**; cap 25/page, 500 total.

## 8.2 Discover screen (`CoachDiscoverView`)
- Search bar (name). Filter bar of chips: Position, Class (grad year multi-select), Location (ZIP + radius chips 25/50/100/150/250 or State), Height ≥, GPA ≥, Playing (This weekend / Next 7 days / Next 30 days). Active filters show as removable chips; "Clear all".
- Results: `AthleteCardView` (photo, name, class year, position, height, school · state, distance if any, GPA if present, "On board" badge with stage if saved by this program, next event date if "Playing" filter active). Infinite scroll by cursor. Empty: "No athletes match. Try widening the radius or clearing a filter."
- Toolbar: "Save search" (§8.5), program chip.
- Pull to refresh re-runs the query.

## 8.3 Athlete detail (`CoachAthleteDetailView`, built on `PublicProfileView` in coach mode)
RPC `coach_athlete_detail(p_program_id, p_athlete_id) returns jsonb` → allowlisted athlete, photo paths, video URLs (external, unchanged), **upcoming** events (next 30 days, D18), board status for this program (entry id, stage, tags, assignee, saved by), contact (only if unlocked), and `recruiting_status` placeholder null in 2.0.
- Header: photo, name, class, position, height/weight, school/hometown; chips. About, Academics (GPA, intended major only), Photos (signed via §7), Videos, Upcoming schedule, Contact card.
- Contact card locked state: lock icon + **"Save to Recruiting Board to unlock contact information"** (D25). Unlocked: athlete email/phone, guardian name/email/phone, club coach name/phone — exactly the fields the athlete entered. Copy for minors: "Contact a minor's guardian first when one is listed." **[routine call]**
- Primary action: **Save to Board** (stage defaults to Watching) or, if saved, stage menu + "Remove from board". Secondary: Report profile (existing `ReportSheet`, target athlete_profile).
- On appear: call `record-profile-view` with program id (W8).
- Hidden: DOB, SAT/ACT, NCAA id, consent, exact location, Instagram/TikTok **shown** as tappable handles **[routine call]**.

## 8.4 Save to board
RPC `board_save_athlete(p_program_id, p_athlete_id, p_stage default 'watching') returns board_entry` — asserts membership, published, not blocked; upsert on (program, athlete); sets `saved_by`; logs activity `saved`; triggers athlete/guardian notification "{Program} saved your profile" with coach name (W6).

## 8.5 Saved searches (D27)
`coach_saved_searches` gains `program_id uuid not null` (015) and RLS = owner AND `coach_has_program(program_id)`. CRUD via PostgREST. `filters` = the §8.1 parameters as JSON (same keys). Alerts toggle was disabled in 2.0; **live since 2.1 (020)**: toggling on sets `alerts_enabled`, the hourly job seeds a baseline on its first pass (no replay), then notifies about athletes not previously seen with destination `{type: saved_search, saved_search_id, program_id}`; editing filters or the program re-seeds. Saved searches screen reachable from Discover toolbar: list, run, rename, delete, alerts.

---

# 9. Recruiting Board (D11, D21, D25, D26, D30, W4, W5)

## 9.1 Data model (migration **017-program-board.sql**, additive)
```sql
program_board_entries (
  id uuid pk, program_id uuid → recruiting_programs, athlete_id uuid → athletes,
  stage text check in (watching, evaluating, contacted, offered, passed) default 'watching',
  tags text[] default '{}' check (cardinality(tags) <= 10 and each tag length <= 30),
  assigned_to uuid null → auth.users,         -- W4
  saved_by uuid → auth.users, created_at, updated_at,
  removed_at timestamptz null, removed_by uuid null,  -- soft removal keeps history (D26/D30)
  unique (program_id, athlete_id)
)
program_board_activity (
  id, program_id, entry_id, actor_user_id, action text check in
   (saved, stage_changed, tags_changed, assigned, unassigned, removed, restored, note_added),
  from_value text, to_value text, created_at
)
coach_private_notes (
  id, coach_user_id, athlete_id, body text check (char_length(body) <= 2000), updated_at,
  unique (coach_user_id, athlete_id)        -- per coach per athlete, independent of program  [routine call]
)
```
RLS: entries/activity select+update+insert require `coach_has_program(program_id)` and (for entries) `not coach_is_blocked(athlete_id)`; delete of entries disallowed (use soft removal) except `saved_by = auth.uid()` cleanup after revocation. Private notes: owner-only all ops. Admin: read all.

Contact unlock (`athlete_contacts` coach branch) is rewritten to: coach role AND published AND not blocked AND exists active (`removed_at is null`) entry in a program where the coach has a verified membership.

## 9.2 RPCs
`board_save_athlete` (§8.4) · `board_set_stage(p_entry_id, p_stage)` · `board_set_tags(p_entry_id, p_tags)` · `board_assign(p_entry_id, p_user_id|null)` (assignee must be active staff of the program) · `board_remove(p_entry_id)` / `board_restore(p_entry_id)` · `board_list(p_program_id, p_stage|null, p_assigned_to|null, p_cursor, p_limit)` returns entries joined to allowlisted athlete cards and the caller's private note excerpt · `board_activity(p_program_id, p_entry_id|null, p_limit)` · `private_note_upsert(p_athlete_id, p_body)`.
Every mutation writes one activity row. Tag/note limits enforced in SQL (D21) and mirrored in UI counters.

## 9.3 Board screen (`CoachBoardView`)
- Stage chips with counts across the top (All · Watching · Evaluating · Contacted · Offered · Passed) plus an "Assigned to me" toggle.
- Cards: photo, name, class, position, height, school, stage pill, up to 3 tags (+n), assignee initials, "you have a note" dot. Swipe: change stage, remove.
- Tap → `CoachAthleteDetailView` with a Board section: stage picker, tag editor (chips, ≤10, ≤30 chars), assignee menu (program staff), **Private note** editor (counter /2000, "Only you can see this"), activity list for this prospect.
- Removed entries: hidden by default; "Show removed" footer; restore action.
- Empty: "No prospects yet. Find athletes in Discover and save them here."

## 9.4 Blocks on the board (W3, D26)
A blocked coach does not see the entry at all (RLS). Colleagues see the card with a "Blocked by athlete" marker only on **that coach's** assignment, i.e. if the blocked coach is the assignee the card shows "Reassign" **[routine call]**. No automatic removal.

## 9.5 Legacy migration (D30)
`coach_saved_athletes` has 0 rows in prod. 017 still includes an idempotent backfill: for each legacy row whose coach has **exactly one** verified membership, create the program entry (saved_by = coach), copy stage/tags, move `notes` into `coach_private_notes` (never shared), log `saved` activity; rows with 0 or >1 memberships are left in place and reported. After backfill, the legacy table's insert policy is dropped (read/delete kept for cleanup). Drop the table in a later migration after 2.1.

## 9.6 Athlete-side "Saved by" (W6)
`bookmarks_for_athlete` rewritten to read `program_board_entries` (active) joined to `recruiting_programs` and the saving coach's display name: returns `program_label, coach_name, title, saved_at`. Notification on save: "University of X Men's Basketball saved your profile" body "Coach {name}". `BookmarksView`/dashboard labels updated.

---

# 10. Home (dashboard)

RPC `coach_home_summary(p_program_id) returns jsonb`: `{ board_counts: {stage: n}, assigned_to_me: n, unread_threads: n, saved_searches: n, recent_activity: [last 10 board_activity rows with athlete name + actor name] }`. All counts honor blocks and `removed_at`.
Screen: program header (chip + Verified badge), stage tiles (tap → Board filtered), "Assigned to me" tile, recent activity list, quick actions (Discover, Saved searches), the conditional "Messages arrive in the next update" line (W2), Account link. Pull to refresh.

---

# 11. Program tab (D16, D22)

- Program card (institution, label, division, verified date) — reuse `CoachHomeView.programCard` extracted to `ProgramCardView`.
- **Switch program** row → `CoachProgramSwitcherView` (hidden if only one context).
- **Staff**: RPC `program_staff(p_program_id)` → active verified members: display name (from `user_profiles.display_name`, fallback request full_name), title, role display name; suspended/inactive excluded (D22). No emails/phones.
- "Your membership": title, role, verified date. "Changing schools? Contact {support}."
- Account / Legal / Sign Out rows (replaces More for coaches) **[routine call]**.

---

# 12. Athlete-side changes in 2.0
- "Saved by" list and notification labels (§9.6).
- Insights recent viewers: coach rows labeled with the verified program (§6.8).
- Media reads through `MediaService` (§7) — behavior unchanged for the athlete.
- No new athlete screens.

---

# 13. Release 2.1 (scoped here, specified in detail before 2.1 starts)

- **Messages**: coach inbox (`messages` where coach_user_id = me AND coach role, grouped by athlete, allowlisted athlete label), shared `ThreadDetailView` with an "other party" abstraction, preflight via `evaluate_my_coach_action(p_athlete_id, p_action_type, p_program_id)` (RPC gains program param), `send_coach_message(p_program_id, p_athlete_id, p_body)` with durable audit (`recruiting_denied_attempts` or audit rows written before any raise), `messages.program_id`, block text and RLS denials surfaced, representing program shown in the thread header. Revoked coaches lose message reads. Enforcement flag ON at launch after the gate (D15).
- **Notifications center** (both roles): bell + unread badge, list, mark read / mark all read, typed `destination jsonb` written by triggers (legacy `link` mapped), `user_settings.show_message_previews` default false and trigger bodies redacted unless opted in (D10, D17, D28).
- **Saved-search alerts**: `pg_cron` job re-running §8.1 per saved search with per-search checkpoint (`last_run_at`, `notified_athlete_ids`, `last_alert_at`), opt-in only (D13). **Implemented in 020** (see status header); known limit: evaluates the first 50 matches per search (TECH-DEBT #41).
- **Notification routing (as built)**: coach taps open athlete detail / the thread (loaded through `coach_athlete_detail`), switch to Messages or Discover (saved search applied via `NotificationRouter`); athlete taps open Bookmarks or the Messages tab (TECH-DEBT #42 for the exact-thread deep link). Unknown destination types mark read only.
- §2.3 confirmations: all done 2026-10-01.

---

# 14. Migrations (2.0)

| # | File | Contents |
|---|---|---|
| 015 | `015-coach-workspace-security.sql` | helpers `coach_has_program`, `coach_assert_program`, `coach_is_blocked`, `is_active_coach`; coach view + `search_published_athletes`, `coach_athlete_detail`, `program_staff`, `coach_home_summary`; remove coach branch from `athletes` select; block checks on media/events/contacts coach policies; helper grants revoked; `coach_directory_names` tightened; admin exclusivity trigger + `approve_coach_request` check; `notify_coaches_of_interest` by membership; athlete-send recipient check; `coach_saved_searches.program_id` + policy. |
| 016 | `016-media-paths.sql` | path columns, backfill with verification report, `media_signed_urls`, storage coach policy by row. |
| 017 | `017-program-board.sql` | §9.1 tables, RLS, RPCs, activity, contact-unlock rewrite, `bookmarks_for_athlete` rewrite, save notification, legacy backfill + retire insert policy. |
Edge function `record-profile-view` redeployed per §6.8.

All re-runnable; applied to prod with `scripts/db-query.sh`; each has a `supabase/tests/*.test.sql` DO-block suite that switches to `set local role authenticated` with JWT claims for coach, blocked coach, suspended coach, colleague, athlete, guardian, admin.

---

# 15. iOS Structure (2.0)

```text
Services/
  CoachWorkspaceService.swift     search, detail, board, saved searches, home summary, staff (all RPCs with p_program_id)
  MediaService.swift              path → signed URL cache; Kingfisher cacheKey = path
  CoachProgramService.swift       + selectedContext, select(), persistence, switcher gating
Core/Models/
  CoachAthleteCard.swift, CoachAthleteDetail.swift, BoardEntry.swift, BoardActivity.swift,
  CoachPrivateNote.swift, ProgramStaffMember.swift, CoachHomeSummary.swift, SearchFilters (extend)
Views/Coach/
  CoachDiscoverView.swift, DiscoverFilterBar.swift, SavedSearchesView.swift
  CoachAthleteDetailView.swift (PublicProfileView coach mode + board/contact sections)
  CoachBoardView.swift, BoardEntryEditorSections.swift, PrivateNoteEditor.swift
  CoachHomeView.swift (rebuilt), CoachProgramView.swift, CoachProgramSwitcherView.swift, CoachAccessUnavailableView.swift
Components/
  AthleteCardView.swift, StageChipBar.swift, TagEditor.swift, ProgramCardView.swift, extracted PhotoViewer/FlowChips
Views/Main/MainTabView.swift      CoachTabView four tabs; MoreView no longer used for coaches
```
Refactors: `PublicProfileView` gets `mode: .athletePreview | .coach(programId:)`; its private subviews move to `Components/`. `AthleteService` media call sites use `MediaService`.

---

# 16. Tests (2.0)

**SQL** (`supabase/tests/coach-workspace.test.sql`, `media-paths.test.sql`, `program-board.test.sql`), as `authenticated`:
- Coach with membership: search returns only published, gender-matched, unblocked athletes; **no forbidden columns in any payload** (assert JSON keys); radius math excludes far athletes; cursor pagination stable; detail works; contact null before save, present after; blocked coach gets nothing (search, detail, media URLs, contact, board entry hidden); colleague still sees the entry; suspended coach denied everywhere; forged `p_program_id` denied; cross-program board read denied.
- Board: save/stage/tags/assign/remove/restore each writes activity; 11 tags / 2,001-char note rejected; private note invisible to colleague and admin payloads; legacy backfill maps single-membership rows and reports ambiguous ones.
- Admin exclusivity both orders; `approve_coach_request` rejects an admin applicant.
- Media: owner/guardian/admin/coach signing matrix; blocked/unpublished denied; storage policy denies folder-sibling object not referenced by a photo row.
- Interest notification reaches verified-membership staff only; profile view function (unit-tested via SQL where possible) denies unpublished/blocked.
- Regression: all Phase 1 suites still pass.

**Swift** (`TheHubTests/CoachWorkspaceTests.swift`): model decoding incl. forbidden-key absence, `SearchFilters` ↔ RPC params round-trip, cursor handling, `MediaService` cache expiry, program selection persistence/validation, stage/tag limit validation.

**Manual** (simulator, recorded in the completion report): existing athlete photos render after 016; two coach accounts on one program see shared changes; blocked coach loses the athlete; switcher with a two-program coach; athlete sees "Saved by {program}".

---

# 17. App Store, Legal, Docs (2.0 gate, D23)
- Re-answer "Social media capability" (currently **No**, basis "no discovery"): Discover is coach-only discovery of UGC. Document the decision in `APPSTORE-CONNECT-FIELDS.md` with the official questionnaire text, and update review note 3.
- Privacy policy: coaches may view published profiles and, after saving, contact details; profile views recorded; program label shown to athletes. Update `LegalView` + `docs/legal/privacy-policy.md` + website (TECH-DEBT #13/#22).
- Demo accounts: a demo athlete (TECH-DEBT #18) **and** a demo coach with a verified program for reviewers. Delete `tstark@mailinator.com` or re-key it first.
- STATUS.md, TECH-DEBT (#6, #9, #28, #32–#37 → done), RECRUITING-RULE-MAINTENANCE (program labels).

---

# 18. Phases & Gates (2.0)

| Phase | Deliver | Gate (Danny approves before next) |
|---|---|---|
| **2A Security + media** | 015, 016, edge fn, `MediaService`, call-site switch, SQL suites | all suites pass; photos render; forbidden columns absent; blocked/suspended denied; TECH-DEBT #6/#32–#37 closed |
| **2B Program context + board data** | 017, `CoachProgramService` selection + switcher, `CoachWorkspaceService`, models, Swift tests | board SQL suite passes; switcher works for 1 and 2 programs; cross-program denied |
| **2C Discover + detail + contact unlock** | Discover screens, filters, saved searches (no alerts), detail in coach mode, save, profile-view call | manual: search → detail → save → contact unlock on simulator; athlete sees program label |
| **2D Board + Home + Program + release prep** | Board screens, Home, Program/staff, docs/App Store/legal, TECH-DEBT, completion report | full regression; two-coach shared board manually verified; §17 done |

---

# 19. Acceptance Criteria (2.0)

- [ ] Coach never receives DOB, test scores, NCAA id, zip, coordinates, consent fields, or `user_id` through any coach path (asserted in SQL tests).
- [ ] Discover runs server-side with the seven D19 filters, program gender forced, 25/page, blocked and unpublished absent.
- [ ] Media: paths stored, 60-min signed URLs via RPC, per-row storage policy, legacy photos render, backfill report shows 0 unresolved.
- [ ] Blocked coach loses Discover/detail/media/contact/board visibility; colleagues unaffected; no auto-restore.
- [ ] Suspended/inactive coach denied all recruiting reads; cleanup deletes still allowed.
- [ ] Shared program board: any active staff can save/stage/tag/assign/remove; activity log complete; private notes author-only; 10 tags / 2,000 chars enforced in DB and UI.
- [ ] Contact card locked until the program saves the athlete; copy per D25.
- [ ] Program switcher required when >1 program and none persisted; every RPC validates `p_program_id`.
- [ ] Staff roster shows active verified members only, no contact info.
- [ ] Athlete "Saved by" and save notification show verified program + coach; profile views recorded on detail open with program label.
- [ ] Admin exclusivity enforced; 0 conflicts.
- [ ] Interest notifications by verified membership.
- [ ] No placeholder tabs; Home shows the Messages note only when unread threads exist.
- [ ] iOS builds; all SQL and Swift suites pass; App Store/legal/docs updated; completion report delivered.

---

# 20. Completion Report Format

```text
COACH MODE 2.0 — IMPLEMENTATION SUMMARY
1. Migrations added/applied (015–017) + edge function
2. RLS/authorization changes (matrix)
3. Media migration report (parsed / verified / unresolved; residual URL window)
4. Files added / modified
5. RPC catalog
6. SQL test results (per suite)   7. Swift test results   8. Manual verification notes
9. Board legacy backfill report  10. Athlete-side changes
11. App Store / legal / docs updates   12. TECH-DEBT rows closed/opened
13. Known limitations   14. Items carried to 2.1 (with §2.3 confirmations still needed)
```

---

# 21. Routine calls made in this draft (overrule by editing)
- More tab replaced by Program → Account rows for coaches.
- Social handles included in the coach allowlist.
- Position filter matches free text (no taxonomy) in 2.0.
- Playing-window dates in America/Chicago.
- Sort by distance when a center is given, else name.
- Signed URL expiry 60 min; legacy `url` columns nulled in 2.1.
- Private notes keyed per coach per athlete (not per program).
- Blocks hide, never auto-remove, board entries; "Reassign" prompt if the blocked coach is assignee.
- Saved-search alerts toggle shown disabled in 2.0.
- Program selection persisted in UserDefaults per user.
- Athlete with null `sport_gender` excluded from Discover; visible in detail only if already on the board.
- Delete of own board entries allowed after revocation for cleanup.
