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

## Reviewer Test Accounts (already in Supabase DB)
- Athlete: `apple.review.athlete@summithoops.example` / `ReviewAthlete2026!`
- Coach: `apple.review.coach@summithoops.example` / `ReviewCoach2026!`

---

## Tech Decisions Made
- **iOS 17+ only** — uses `@Observable` macro, no Combine
- **supabase-swift** (official SDK) for all DB/Auth/Storage/Functions calls
- **Kingfisher** for async image loading — add in Phase 2 alongside AthleteService
- All DB strings stored as `String` not `Date` — use `Date+Formatting` helpers to display
- `HubFormFields.swift` components are the design system — use them everywhere
- No SwiftData — all data comes from Supabase
