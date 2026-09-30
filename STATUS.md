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
- Signing in lands on the **Admin** tab (Admin Settings + More). Use the
  reviewer athlete account below for athlete testing.
- First admin had to be bootstrapped with SQL: `user_roles` only allows
  self-assigning athlete/parent, and granting `admin` requires an existing
  admin. To add more admins later, an existing admin can insert the row, or
  run: `insert into public.user_roles (user_id, role) select id, 'admin'
  from auth.users where email = '<email>';`
- ⚠️ **Change this password before launch.** It was set in a chat transcript,
  it's a well-known weak string, and this account can read every athlete's
  data (including minors' contact info), manage roles, and flip production
  feature flags.

## Reviewer Test Accounts (already in Supabase DB)
- Athlete: `apple.review.athlete@summithoops.example` / `ReviewAthlete2026!`
  ⚠️ This account was **accidentally deleted in-app on 2026-09-23** (the
  delete-account flow was exercised while signed into it) and **rebuilt from
  scratch the same day** with identical credentials — Apple's App Review notes
  still match. New user id `646144c2-…`; profile is Jalen Brooks, published,
  with regenerated photos, schedule, colleges, coach messages, and NCAA data.
  Do not use this account to demo account deletion — use a throwaway signup.
- Coach: `apple.review.coach@summithoops.example` / `ReviewCoach2026!`

## Marketing / Demo Athlete Accounts (seeded 2026-09-23)
Five fully populated, published athlete profiles for demos, screenshots, and
marketing. All have: profile photo + 5 captioned gallery images (generated
sports-card graphics in Supabase storage, 1-year signed URLs), bio, academics,
physicals, socials, hometown+coords, guardian consent, contact card, 5
schedule events (Oct–Dec 2026), 4–6 target colleges, coach messages, NCAA
readiness data, and seeded profile views/saves from the demo coach accounts.
Emails are intentionally non-routable (`@summithoops.example`) — password
reset is impossible, so keep these passwords safe.

| Athlete | Email | Password | Class / Position |
|---|---|---|---|
| Jalen Brooks | `apple.review.athlete@summithoops.example` | `ReviewAthlete2026!` | 2027 SG (mens) — also the Apple review account |
| Darius Cole | `demo.darius.cole@summithoops.example` | `DemoDarius2026!` | 2027 PG (mens) |
| Maya Thompson | `demo.maya.thompson@summithoops.example` | `DemoMaya2026!` | 2027 SG (womens) |
| Elijah Reed | `demo.elijah.reed@summithoops.example` | `DemoElijah2026!` | 2028 PF (mens) |
| Sofia Ramirez | `demo.sofia.ramirez@summithoops.example` | `DemoSofia2026!` | 2027 SF (womens) |

## Demo Coach Accounts (rotated 2026-09-18 — see docs/SUBMISSION-READINESS.md)
Emails moved from public mailinator.com inboxes to non-routable
`@summithoops.example` addresses and passwords scrambled (the old
`DemoCoach2026!` password was committed to git history, and anyone could
read a mailinator inbox and password-reset their way into an approved coach
account). Their seeded data (messages, views, saves) is unchanged. These
accounts are no longer sign-in-able; to use one, reset its password via SQL.
- `coach.boudreaux.lsu@summithoops.example` — Marcus Boudreaux, LSU
- `coach.jackson.uh@summithoops.example` — Darnell Jackson, Houston
- `coach.landry.latech@summithoops.example` — Louisiana Tech
- `coach.rizzo.slu@summithoops.example` — Southeastern Louisiana
- `coach.carter.mostate@summithoops.example` — Missouri State
- `coach.whitfield.ku@summithoops.example` — Kansas
- Athlete: `ctguillory@mailinator.com` (Danny's test athlete — left untouched
  deliberately; NOTE: mailinator inboxes are public, so consider changing this
  account's email before launch)

---

## Tech Decisions Made
- **iOS 17+ only** — uses `@Observable` macro, no Combine
- **supabase-swift** (official SDK) for all DB/Auth/Storage/Functions calls
- **Kingfisher** for async image loading — add in Phase 2 alongside AthleteService
- All DB strings stored as `String` not `Date` — use `Date+Formatting` helpers to display
- `HubFormFields.swift` components are the design system — use them everywhere
- No SwiftData — all data comes from Supabase
