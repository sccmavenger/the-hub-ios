# Gap Analysis — iOS App vs. Lovable Web App (athlete-connect)

**Compared:** 2026-09-11
**Web app:** https://github.com/sccmavenger/athlete-connect (TanStack Start + Supabase project `ovzzmzjjvqsdhnpmepwt` via Lovable Cloud)
**iOS app:** this repo (SwiftUI + fresh Supabase project `fnlufxhznqclpajyadcc`)

Status key: `[ ]` open · `[~]` decided, not built · `[x]` resolved

---

## A. Strategic decisions (discuss first — everything else depends on these)

### A1. `[ ]` Two separate Supabase projects
The web app runs against Lovable Cloud project `ovzzmzjjvqsdhnpmepwt`. The iOS app
runs against the fresh project `fnlufxhznqclpajyadcc` we set up yesterday. If both
apps are supposed to share users/data, we must point iOS at the Lovable project
(or migrate the web app). If iOS is a clean replacement, we're fine — but then
the web app's production data/users never appear in iOS.

### A2. `[ ]` No server-side layer on iOS
The web app does ALL privileged work in TanStack server functions with a
service-role key (account deletion, guardian invites, admin ops, profile-view
recording with 6-hour dedupe, approved-coach listing, geocoding). iOS has no
server, so these need **Supabase Edge Functions**. The web repo has *zero* edge
functions — they must be written from scratch. Candidates:
- `delete-account` (Apple 5.1.1(v) requirement; iOS already calls `deleteMyAccount`)
- `record-profile-view` (dedupe + self-view exclusion; iOS already calls `recordProfileView`)
- `redeem-guardian-invite` / `create-child-athlete` (Phase 3)
- `list-approved-coaches` (messaging "start conversation" picker)
- `admin-*` (approve coach, manage users/roles, resolve reports) (Phase 5)

### A3. `[ ]` Storage privacy model
Web: `athlete-media` is **private**; app generates 365-day signed URLs.
Ours: bucket is **public** with public URLs. Web also gives coaches/admins
RLS read access to published athletes' media. Decide: keep public (simpler)
or match web's private+signed model (more private, Apple-friendlier).

---

## B. Database schema deltas (our fresh DB vs. web app's real schema)

### B1. `[ ]` Table name mismatches
- Web `profiles` ↔ ours `user_profiles`
- Web `profile_views` ↔ ours `athlete_profile_views` (iOS code queries the latter)

### B2. `[ ]` Missing tables: `content_reports`, `user_blocks`
Safety infra (report/block) — required for Apple guideline 1.2. No iOS models exist either.

### B3. `[ ]` Missing DB triggers the web app relies on
- `handle_new_user` role assignment from `role_intent` signup metadata
  (web: client never writes `user_roles`; ours allows self-insert of athlete/parent)
- Notification fan-out triggers: on message, on coach bookmark (also notifies guardian),
  on college-interest match (`normalize_college`), on first publish
- `enforce_college_interest_limit` (10 max, DB-enforced)
- `enforce_guardian_consent` (under-13 publish block)
- `enforce_message_blocks` (blocked users can't message)

### B4. `[ ]` RLS differences (web is stricter)
- Contacts: web requires coach be approved AND have the athlete saved AND published;
  ours only requires coach role + published
- `coach_saved_athletes`/`coach_saved_searches`: web requires `coach` role; ours only ownership
- `profile_views`: web inserts via service role only; ours allows any authenticated insert
- `notifications`: web has no client INSERT (triggers only); ours allows self-insert... (ours: none — OK)
- Web `athletes` grants column-filtered SELECT to `anon` (public profile pages);
  ours is authenticated-only (fine unless iOS needs public web-style sharing)

### B5. `[ ]` Missing columns/types
- Web `athletes.gpa` is `numeric(3,2)` (ours 4,2 — harmless)
- Web enums `app_role`, `coach_request_status` are PG enums (ours text+check — fine)
- `athlete_invites.expires_at` default now()+30 days (ours requires explicit value)

---

## C. Gaps inside screens we already built (Phase 2)

### C1. `[ ]` Completeness score formula differs
Web (`src/lib/completeness.ts`): 14 items, weights sum to 110, score = round(earned/110*100):
name 5, photo 10, school 5, grad 10, position 10, height+weight 10, gpa 10,
**zip 10**, video 15, photos 3, events 7, bio 3, contact 5, **published 7**.
Tones: ≥90 Recruit-ready / ≥65 Almost there / ≥35 Needs work / else Just getting started.
iOS uses STATUS.md's 8-item/100-pt formula (photo 20, bio 15, video 15, events 15,
gpa 10, size 10, contact 10, gallery 5). Decide which is canonical.

### C2. `[ ]` Profile editor missing behaviors
- ZIP → geocode lat/lng on save (web: zippopotam.us, free; blank ZIP nulls coords)
- Validation ranges (web zod): grad_year in [thisYear-1, thisYear+8], height 40–96,
  weight 60–400, gpa 0–5, SAT 400–1600, ACT 1–36, state 2 letters, zip 5 digits,
  bio ≤1000 with live counter, handles ≤50, phone regex
- Video cap: 8 (iOS currently unlimited); photo captions (web has them, 120 max)
- Guardian consent capture: consent name+email fields; `guardian_consent_at` stamped
  when both present; **under-18 publish requires consent** (client rule) and
  under-13 blocked by DB trigger
- Public profile link display when published
- Image pipeline: web caps source 25 MB / 6 MP decode, profile 1200px, gallery 1600px,
  JPEG 0.85 (iOS: only 0.85 quality, no dimension cap — memory risk from Apple 2.1(a) history)

### C3. `[ ]` Colleges screen missing features
- Searchable database of 1,300+ programs with typeahead (name/acronym/state),
  auto-fills division+state (web `colleges-data.ts` — portable to Swift or an API)
- College crest/logo (web has `/api/public/college-logo` with ESPN/Clearbit fallbacks)
- NCAA compliance card: contact windows per division (D1/D2 open June 15 of gradYear−2),
  gendered calendar links, outreach note
- Duplicate-school check; "coaches get notified" toasts tied to publish state

### C4. `[ ]` Dashboard deltas
- Web activity tiles = Profile views (all-time via head count), Bookmarks, Unread
  (iOS: views limited to 90d — close enough, discuss)
- Web supports multiple managed athletes with a switcher (parent case!) — iOS
  assumes exactly one athlete owned by the signed-in user; parents with no
  athlete row see an error state rather than "create/link" prompts

### C5. `[ ]` Sign-up flow deltas
- Web athlete signup REQUIRES date of birth; blocks under-13 with "sign up as
  parent instead" flow
- Web passes `role_intent` metadata; DB trigger assigns roles server-side
  (coach gets NO role until approval — iOS matches behaviorally here)
- Web parent signup path + info banner
- iOS `signUpAthlete` inserts role+athlete client-side (works on our DB; won't
  work against web DB where user_roles has no client INSERT)

---

## D. Screens/features not yet built in iOS (mapped to phases)

### D1. `[ ]` Messaging (Phase 3) — web reference behavior
Threads keyed (athlete_id, coach_user_id); 60s list polling / 30s thread polling;
unread = inbound && !read_at; auto-mark-read on view; 2000-char cap w/ counter;
"start conversation" from approved-coach list; compliance banner; per-message
report; block/unblock integration (composer replaced when blocked).

### D2. `[ ]` Family / guardians (Phase 3)
Invite codes (8-char unambiguous alphabet, 30-day expiry, single-use, copy/cancel);
redeem flow (grants parent role, links guardian, notifies owner); create child
profile (consent checkbox required, max 5 athletes/account, under-13 messaging);
"people with access" management; athlete switcher everywhere (dashboard, editor,
colleges, insights, messages).

### D3. `[ ]` Safety / UGC (Apple 1.2 — required before submission)
Report dialog (7 reasons + details ≤2000) for profiles/messages/users;
block/unblock; blocked-people list in Account; admin reports queue; DB tables
+ trigger (see B2/B3). **The web app was rejected by Apple until this existed.**

### D4. `[ ]` Account screen (Apple 5.1.1(v) — required)
Email + roles display; blocked list; type-DELETE-to-confirm account deletion
with full cascade (web deletes 15+ row types + storage + auth user). Needs the
edge function from A2.

### D5. `[ ]` Insights (Phase 5 → likely earlier; web ships it to athletes)
4 stat tiles (views 7d, coach views 7d, views 30d, bookmarks); 8-week bar chart;
unique college programs list (30d); recent viewers feed (role-labeled);
completeness card. Data comes from `profile_views` with `viewer_label`.

### D6. `[ ]` Public athlete profile (web `/a/:athleteId`)
iOS has no athlete-detail screen yet. Needed for: athlete "view my profile",
coach directory tap-through, save/message actions, contact card (gated),
video embeds (YouTube/Hudl/Vimeo/TikTok/Instagram), schedule + ICS export,
profile-view recording. Web hides DOB/SAT/ACT/NCAA-ID from public payload.

### D7. `[ ]` Coach directory (Phase 4)
Filters: place (state name OR zip OR city via free geocoders — zippopotam +
Nominatim, NOT Google as STATUS.md assumed), radius chips 10–250mi w/ haversine
sort, position groups + free-text position parser, grad year, min height/GPA,
name search, "playing" date windows (weekend/7d/30d) joined to events;
save-search; save-to-pipeline; 500-row query cap.

### D8. `[ ]` Games near me (Phase 4)
ZIP + radius (default 100mi) + date window (default 7d) + MAYB-only toggle;
grouped by date; ICS calendar export of visible games.

### D9. `[ ]` Pipeline (Phase 4)
Stage chips w/ counts; stage select per card (watching/evaluating/contacted/
offered/passed); tags ≤10; private notes ≤2000; CSV export of filtered rows.

### D10. `[ ]` Coach inbox (Phase 4) — mirror of D1 from coach side.

### D11. `[ ]` Admin (Phase 5)
Stats (6 head-counts); users list w/ role toggles + delete (can't self-delete /
self-demote); coach request review (idempotency: reject if already reviewed);
reports queue w/ resolution notes + hide-profile action.

### D12. `[ ]` Notifications UI
Bell w/ unread badge (9+ cap), mark-all-read, 20 most recent, deep links.
Trigger-generated (message/bookmark/interest/publish/guardian-join/report).
Push notifications: deferred on web too (APNs — genuinely new work).

---

## E. Reference details worth keeping (from web code)

- Completeness formula: see C1.
- Profile view dedupe: 1 per viewer/athlete/6h; self+guardian views never recorded;
  signed-out views recorded as role "public" (service role).
- Contact windows: D1/D2 open June 15 of (gradYear − 2); D3/NAIA/JUCO always open.
- Invite code alphabet: `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, 8 chars.
- Message/notes/report/details caps: 2000; bio/college-notes: 1000; caption: 120.
- Apple review seeds: "Jordan Blake" published demo athlete + coach thread + pipeline.
- Web reviewer accounts live in the LOVABLE project, not ours (ours were recreated).
- AGENTS.md (web repo): never force-push/rebase the Lovable-connected branch.
