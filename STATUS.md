# The Hub iOS — Project Status

**Repo:** https://github.com/sccmavenger/the-hub-ios (private)
**Plan doc:** `/Users/dannyjr/Documents/TheHub-NativeiOS-RebuildPlan.md`
**Last updated:** September 2026

---

## New Device Setup (do this first)

```bash
git clone https://github.com/sccmavenger/the-hub-ios.git
cd the-hub-ios/TheHub
open TheHub.xcodeproj
```

Then in Xcode:
1. **File → Add Package Dependencies**
   Paste: `https://github.com/supabase/supabase-swift`
   Click Add Package → check **Supabase** → Add to Target: **TheHub**

2. Open `TheHub/Core/Supabase/SupabaseClient.swift`
   Replace the two placeholder strings:
   ```swift
   static let supabaseURL = "YOUR_SUPABASE_URL"       // from app.supabase.com → Settings → API
   static let supabaseAnonKey = "YOUR_SUPABASE_ANON_KEY"
   ```

3. Select an iPhone 17+ simulator, hit **Run (⌘R)**
   → Sign-in screen should appear with dark theme + gold branding

---

## Phase Status

| Phase | What | Status |
|---|---|---|
| 1 | Foundation — models, auth, tab scaffold | ✅ Done |
| 2 | Athlete Core — dashboard, profile editor, public profile, college list | ⬜ Next |
| 3 | Messaging & Family | ⬜ |
| 4 | Coach Features — onboarding/verification/Coach Mode entry ✅ (2026-09-30); Coach Workspace 2.0 (Discover, Board, Home, Program) ✅ and 2.1 (Messages, Notifications center, saved-search alerts, enforcement ON) ✅ code complete 2026-10-01 per `docs/COACH-MODE-WORKSPACE-SPEC.md` | ✅ |
| 5 | Insights & Admin | ⬜ |
| 6 | Polish & App Store submission | ⬜ |

---

## What Phase 1 Built

```
TheHub/
├── App/
│   ├── TheHubApp.swift        @main — injects AuthViewModel
│   └── RootView.swift         Auth gate: splash → sign-in OR tab view
├── Core/
│   ├── Supabase/
│   │   └── SupabaseClient.swift   Global `supabase` singleton + Secrets enum
│   └── Models/                    14 Codable structs (snake_case CodingKeys)
│       ├── Enums.swift            AppRole, PipelineStage, CollegeStatus, SportGender
│       ├── Athlete.swift
│       ├── UserProfile.swift / UserRole.swift
│       ├── AthleteContact / Photo / Video / Event / CollegeInterest
│       ├── AthleteGuardian / Invite / ProfileView
│       ├── CoachRequest / CoachSavedAthlete / CoachSavedSearch
│       ├── Message.swift / AppNotification.swift
├── Services/
│   └── AuthService.swift      signIn, signUp (athlete/parent/coach), signOut,
│                              fetchUserRoles, deleteAccount (calls edge fn)
├── ViewModels/
│   └── Auth/
│       └── AuthViewModel.swift  @Observable, session persistence, primaryRole,
│                                authStateChanges listener
├── Views/
│   ├── Auth/
│   │   ├── SignInView.swift
│   │   ├── SignUpView.swift    Role picker (athlete/parent/coach) + coach fields
│   │   └── ResetPasswordView.swift
│   └── Main/
│       └── MainTabView.swift   Role-branched: AthleteTabView / CoachTabView /
│                               AdminTabView / PendingApprovalView / MoreView
├── Components/
│   └── HubFormFields.swift    HubTextField, HubSecureField, HubPrimaryButton,
│                              HubErrorText  ← use these everywhere, never raw TextField
└── Utilities/Extensions/
    ├── Color+Theme.swift       hubBackground, hubGold, hubSurface, hubBorder, etc.
    ├── Date+Formatting.swift   String.asFormattedDate(), String.asDate(), Date.toISO8601String()
    └── String+Validation.swift isValidEmail, isValidPassword, isBlank, trimmed
```

---

## Phase 2 — What to Build Next

Tell Claude Code: **"Start Phase 2 from the rebuild plan. Build AthleteService, DashboardView, ProfileEditView, and CollegeListView."**

### AthleteService (`Services/AthleteService.swift`)
- `fetchAthlete(userId:)` → `Athlete`
- `updateAthlete(_ athlete: Athlete)` → patch `athletes` table
- `fetchPhotos/Videos/Events/CollegeInterests/Contact(athleteId:)`
- `uploadProfilePhoto(data: Data, userId: String)` → Supabase Storage `athlete-media` bucket
- `recordProfileView(athleteId:)` → call `recordProfileView` edge function

### DashboardViewModel + DashboardView
- Profile completeness score (photo 20pts, bio 15pts, GPA 10pts, height/weight 10pts, videos 15pts, events 15pts, contact 10pts, gallery 5pts)
- Activity cards: profile views (last 90 days), coach saves count, unread messages
- Quick action buttons → navigate to profile editor sections

### ProfileEditView (multi-section scroll form)
Sections: Basic · Physical · Academics · Social · Bio · Profile Photo · Gallery (6 max) · Videos · Schedule · Contact · Guardian · NCAA ID · Publish toggle

### CollegeListView
- List of `AthleteCollegeInterest` records (up to 10)
- Add/edit/delete schools
- Division, state, status, notes fields

---

## Key Credentials Needed (not in repo — keep these safe)

- **Supabase URL:** get from app.supabase.com → your project → Settings → API
- **Supabase anon key:** same location
- **Google Geocoding API key:** console.cloud.google.com (needed for Phase 4 coach directory)

---

## Admin Account (created 2026-09-18)
- `dguilloryjr@msn.com` / `P@ssw0rd` — role: **admin only** (the athlete role
  and the empty "Danny Test" athlete row were removed 2026-09-23 at Danny's
  request — admin accounts should not carry athlete profiles).
- Signing in lands on the **Admin** tab (Admin Settings + More). For athlete
  testing use `dguilloryjr@gmail.com` or sign up a throwaway account.
- First admin had to be bootstrapped with SQL: `user_roles` only allows
  self-assigning athlete/parent, and granting `admin` requires an existing
  admin. To add more admins later, an existing admin can insert the row, or
  run: `insert into public.user_roles (user_id, role) select id, 'admin'
  from auth.users where email = '<email>';`
- ⚠️ **Change this password before launch.** It was set in a chat transcript,
  it's a well-known weak string, and this account can read every athlete's
  data (including minors' contact info), manage roles, and flip production
  feature flags.

## Demo / Reviewer Accounts — NONE (purged 2026-09-29)

All 12 demo accounts (`*@summithoops.example`: the Apple review athlete +
coach, the 4 marketing athletes, and the 6 seeded coaches) were **fully purged
on 2026-09-29** at Danny's request after App Store approval — auth logins,
profiles, photos in storage, messages, views, saves, and every dependent row.
Verified zero leftovers. Reason: published fictitious athletes would appear
in real coaches' searches once the app is live.

⚠️ **Before the next App Review submission, a demo athlete account must be
created** (sign-in is required, so Apple needs working credentials) and
entered in App Store Connect → App Review Information. Ask Claude to build
one; the seeding approach is documented in
docs/SUBMISSION-READINESS.md §2g. The App Review demo-account fields were
cleared on 2026-09-29 so they don't point at a dead login.

Remaining accounts (as of 2026-09-30): **only `dguilloryjr@msn.com` (admin)**.
`dguilloryjr@gmail.com` and `ctguillory@mailinator.com` were purged
2026-09-30 at Danny's request; the `athlete-media` bucket is empty.

## Recruiting Rules Engine (added 2026-09-30)

Recruiting rule authority moved out of the app into Supabase. Spec:
`docs/RECRUITING-RULES-ENGINE-SPEC.md`; operations: `docs/RECRUITING-RULE-MAINTENANCE.md`.

- Migrations 010–013 applied to prod. Seven NCAA D1 basketball rules seeded from the
  2026-27 D1 Manual (LSDBi 90008). **The spec's bylaw numbers were wrong** — basketball is
  13.4.1.5 (men's, June 15) / 13.4.1.6 (women's, June 1), not 13.4.1.3/4.
- One deterministic SQL evaluator (`evaluate_recruiting_action`) serves iOS, web, and the
  `messages` BEFORE INSERT trigger. Swift only deserializes `RecruitingDecision`.
- Flags in `app_settings`: `recruiting_rules_engine_enabled` = **true** (Stage A, display),
  `recruiting_rules_enforcement_enabled` = **true since 2026-10-01** (Stage B hard-block,
  switched on at the Coach Mode 2F gate after all suites passed). Verified-coach sends that a
  published hard-block rule prohibits are refused; the iOS send RPC records each denial in
  `recruiting_denied_attempts`. Rollback: More → Admin Settings.
- D2/D3/NAIA/NJCAA have no sourced rule → `needs_review`. D3/NAIA/JUCO rows on the Colleges
  card keep their legacy orientation note by decision (TECH-DEBT #21).
- Tests: `supabase/tests/*.test.sql` (8 suites as of 2026-10-01, run via `scripts/db-query.sh`;
  each saves and restores the enforcement flag) and `TheHubTests/*` (55 tests).
- Terms §6 rewritten in `docs/legal/terms-of-service.md` + `LegalView.swift`
  (last updated 2026-09-30). **Website `/terms` on Lovable still needs the same text.**

## Coach Onboarding & Verification (added 2026-09-30)

College Coach sign-up is back in the iOS app as an **application, not access**.
Spec: `COACH-MODE-ONBOARDING-AND-VERIFICATION-SPEC.md` (Danny's Downloads);
backend: `supabase/014-coach-onboarding.sql`; tests:
`supabase/tests/coach-onboarding.test.sql` + `TheHubTests/CoachOnboardingTests.swift`.

- **Sign-up** (`SignUpView`): Athlete / Parent-Guardian / College Coach. Coach claims
  (title, institution, men's/women's, association, division, optional URLs/phone/note)
  travel as signup metadata; `handle_new_user` files a **pending** `coach_requests` row
  and grants **no role**. Email confirmation unchanged.
- **Routing** (`AccountStateResolver`): roles win (admin > coach > athlete > parent).
  A role-less account routes by its application — pending / needs info / rejected /
  withdrawn / approved-but-paused — or to a retry screen, or to "account needs setup"
  when no application exists. `nil role` is never assumed to mean "pending coach".
- **Applicant screens** (`Views/Coach/`): status (claims under review, dates, reason),
  edit/resubmit (`update_coach_application`), withdraw. No athlete content.
- **Admin review** (`Views/Admin/CoachApplications*`, Coaches tab): queue → detail →
  Approve (pick existing program or confirm a new one prefilled from claims) /
  Request info / Reject (user-visible message + internal note) / Suspend-Reinstate.
  All writes are 014 RPCs; approval is one transaction (program verified → membership
  → `user_roles.coach` → request → notification).
- **Coach role is derived**: `sync_coach_role()` keeps `user_roles.coach` = "has ≥1
  verified membership in an active, verified program". Suspension removes it in the
  same statement. BEFORE-trigger guards stop any authenticated client — including the
  web admin portal — from flipping status / inserting coach / verifying membership
  directly (TECH-DEBT #27).
- **Coach Mode Phase 1** (`CoachHomeView`): verified program card + account; no
  placeholder tabs. `CoachProgramService` exposes `CoachProgramContext` for the
  Coach Workspace spec and the rules engine.
- **Also fixed**: 007 had dropped the coach-role check on `coach_saved_athletes`
  insert (any signed-in account could bookmark a published athlete); restored in 014.
- Prod: one test coach (`tstark@mailinator.com`, University Of IronMan, approved in-app
  2026-09-30; public inbox — delete before real athletes publish) plus the admin.
  ⚠️ Before the next App Review submission: update review notes (coach sign-up exists,
  access is manually approved) and consider a demo coach path (TECH-DEBT #18, #29).
- **Phase 2 (Coach Workspace)** — spec `docs/COACH-MODE-WORKSPACE-SPEC.md` (2.0 = Home ·
  Discover · Board · Program; 2.1 = Messages · Notifications · alerts). Decisions in
  `docs/COACH-MODE-PHASE2-DECISIONS.md`; gap analysis `docs/COACH-MODE-PHASE2-GAP-ANALYSIS.md`.
  - **2A done 2026-10-01** (migrations 015–016 applied, `record-profile-view` v2 deployed):
    media stored as paths and signed for 60 min per photo row; coaches read athletes only
    through allowlisted RPCs scoped to a verified program; blocks apply to every coach read;
    admin role exclusive; interest notifications by membership. TECH-DEBT #6/#9/#32/#33/#34/#36/#37
    closed. ⚠️ Until 2C ships Discover, an approved coach's app shows the program card only.
  - **2B done 2026-10-01** (migration 017 applied): program-owned Recruiting Board tables +
    RPCs, private notes, contact unlock keyed on the board, "Saved by" names the program;
    iOS program selection (persisted, switcher required when >1 program), `CoachWorkspaceService`
    + models for every coach RPC. Coach still sees Home + More; 2C adds Discover.
  - **2C done 2026-10-01** (migration 018 applied): **Discover tab** — server-side search
    with name, position, class, ZIP+radius or states, height, GPA, playing-window filters;
    saved searches (alerts toggle disabled until 2.1); coach athlete detail with photos,
    videos, 30-day schedule, Save to Recruiting Board, stage menu, contact card locked until
    the program saves the athlete, report; detail opens record a profile view labeled with
    the verified program. Coach now sees Home · Discover · More.
  - **2D done 2026-10-01 — Coach Mode 2.0 code complete.** Tabs: **Home** (program header,
    board counts by stage → Board, assigned-to-me, quick actions, recent staff activity,
    "messages arrive in the next update" note when athletes have written) · **Discover** ·
    **Board** (stage chips with counts, assigned-to-me / show-removed, swipe remove/restore,
    context-menu stage/assign; detail gains tags ≤10×30, assignee from staff, private note
    ≤2,000 author-only, per-prospect activity) · **Program** (card, switcher, verified staff
    roster, membership, Account & Legal, Sign Out). More tab retired for coaches.
    Privacy policy (app + md) describes coach discovery/contact unlock/profile views
    (last updated 2026-10-01; website copy pending #13/#22). App Store review note 3
    rewritten; "Social media capability" flagged for re-answer (#40).
  - **Release gates before submitting 2.0:** #40 questionnaire answer, #18/#29 demo athlete +
    demo coach, website legal copy, delete/re-key `tstark@mailinator.com`, then-current
    reviewer notes. Enforcement flag stays OFF until 2.1 Messages (D15).
  - **2.1 / 2E done 2026-10-01** (migration 019 applied): **Messages tab** for coaches —
    inbox scoped to the program, thread view with a live recruiting-rules preflight for the
    selected program, Send disabled when the rule hard-blocks and enforcement is ON (shadow
    warning when OFF), sends through `send_coach_message` (denials recorded durably in
    `recruiting_denied_attempts`, nothing delivered), block/report, Message button on the
    athlete detail. Coaches lose thread reads when suspended or blocked. Message
    notification bodies are redacted unless the recipient opts into previews (setting UI
    lands in 2F). Spec §2.3 confirmations accepted by Danny 2026-10-01.
  - Next: **2F** — Notifications center (coach + athlete), previews toggle, saved-search
    alerts (`pg_cron` available, not yet enabled), then flip enforcement ON after its gate.

## Tech Decisions Made
- **iOS 17+ only** — uses `@Observable` macro, no Combine
- **supabase-swift** (official SDK) for all DB/Auth/Storage/Functions calls
- **Kingfisher** for async image loading — add in Phase 2 alongside AthleteService
- All DB strings stored as `String` not `Date` — use `Date+Formatting` helpers to display
- `HubFormFields.swift` components are the design system — use them everywhere
- No SwiftData — all data comes from Supabase
