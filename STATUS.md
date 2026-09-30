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
| 4 | Coach Features — directory, games, pipeline | ⬜ |
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
  `recruiting_rules_enforcement_enabled` = **false** (Stage B hard-block; needs verified
  coach→program rows, which wait for the coach-experience spec).
- D2/D3/NAIA/NJCAA have no sourced rule → `needs_review`. D3/NAIA/JUCO rows on the Colleges
  card keep their legacy orientation note by decision (TECH-DEBT #21).
- Tests: `supabase/tests/*.test.sql` (3 suites, run via `scripts/db-query.sh`) and
  `TheHubTests/RecruitingRulesTests.swift` (13 tests).
- Terms §6 rewritten in `docs/legal/terms-of-service.md` + `LegalView.swift`
  (last updated 2026-09-30). **Website `/terms` on Lovable still needs the same text.**

## Tech Decisions Made
- **iOS 17+ only** — uses `@Observable` macro, no Combine
- **supabase-swift** (official SDK) for all DB/Auth/Storage/Functions calls
- **Kingfisher** for async image loading — add in Phase 2 alongside AthleteService
- All DB strings stored as `String` not `Date` — use `Date+Formatting` helpers to display
- `HubFormFields.swift` components are the design system — use them everywhere
- No SwiftData — all data comes from Supabase
