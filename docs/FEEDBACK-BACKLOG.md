# TestFlight Feedback Backlog

Every piece of tester feedback pulled from App Store Connect (TestFlight →
Feedback), what we decided, and where the fix landed. Pull new items with:

```bash
python3 scripts/asc.py get "apps/6813542102/betaFeedbackScreenshotSubmissions?limit=50&sort=-createdDate"
python3 scripts/asc.py get "apps/6813542102/betaFeedbackCrashSubmissions?limit=50&sort=-createdDate"
```

(The collection lives under `apps/{id}/…`; the top-level collection endpoint
returns 403. Screenshot URLs are signed and expire.)

| # | Submitted | Build | Screen | Feedback (paraphrased) | Decision | Status |
|---|-----------|-------|--------|------------------------|----------|--------|
| F1 | 2026-10-01 | 1.3 (2) | NCAA Journey | Tapping the D1 / D2 / D3 / Unsure pills makes the page jump; feels clunky. | **Bug.** Changing division reloaded the recruiting-status card *above* the pills into a spinner, so the content under the finger shifted. Fix: division picker moved to the top of the page so everything it changes is below it, and the previous decision stays on screen while the new one loads. | **done (2026-10-01)** — `NCAAJourneyView` |
| F2 | 2026-09-30 | 1.3 (1) | Edit Profile → Contact Info | Don't collect or show a minor's phone; email is enough to block; never show a minor's phone/email to a coach. | **Policy change, adopted.** Minors (under 18 by DOB, or DOB unknown): the editor no longer shows the Athlete Phone field, stored minor phones were nulled, and the coach detail RPC withholds the athlete's own email and phone (guardian / club coach still unlock on the board; coaches can message in-app). Adults 18+: unchanged. Coaches can no longer read `athlete_contacts` directly at all; the RPC is the only path. | **done (2026-10-01)** — `supabase/021`, `ProfileEditView`, `CoachAthleteDetailView` |
| F3 | 2026-09-30 | 1.3 (1) | Edit Profile → Game Schedule | Let me upload the school's .ics file instead of typing games. | **Feature, built.** "Import from a calendar file (.ics)" opens the Files picker, parses VEVENTs (all-day, zoned, UTC; folded lines; escaped text), derives opponent from "vs / @ / at" phrasing, pre-deselects past games and duplicates, and shows a review list before anything is saved. | **done (2026-10-01)** — `ICSParser`, `ICSImportSheet`, `ProfileEditViewModel.importEvents` |
| F4 | 2026-09-30 | 1.3 (1) | Edit Profile | Page is very long; make sections accordion-style with a "complete" measure per section (e.g. 1 of 1, 0 of 1). | **UX change, built.** Every card collapses to a header with an "x of y" chip; edit mode starts collapsed with "N of 12 sections complete" and Expand/Collapse all; create mode opens everything. | **done (2026-10-01)** — `HubFormSection`, `ProfileEditView` |
| F5 | 2026-09-30 | 1.3 (1) | Edit Profile → Photo Gallery | "Hire a photographer" — let photographers register and be hired from here. | **Product idea, not scheduled.** A two-sided marketplace (photographer accounts, payments, vetting around minors) is a separate product line. Parked here for a roadmap conversation. | **backlog** |
| F6 | 2026-09-30 | 1.3 (1) | Edit Profile → Bio | AI could turn a few bullet points into a bio. | **Not building now.** The project's standing decision is no AI features (recruiting engine spec); generating text about a minor would also need a third-party model, a privacy-policy change, and App Review disclosure. Revisit only as a deliberate product decision. | **backlog (declined for now)** |
| F7 | 2026-09-30 | 1.3 (1) | My Colleges | Content can be dragged left and right; it should only scroll vertically. | **Bug.** The recruiting-status card sized itself wider than the screen. Fix: card extracted to `RecruitingStatusCard`, pinned to the available width, rule-source links wrap left-aligned, and the scroll view is explicitly vertical. Verified in a rendered preview; confirm on device (see test cases). | **done (2026-10-01)** — `RecruitingStatusCard`, `RecruitingRuleSourceView`, `CollegeListView` |

## Process

- Pull feedback at the start of any release-prep session and add rows here.
- A row is **done** only when the fix is in a build the tester can install;
  until then note the commit.
- Product ideas (F5, F6) stay here rather than in `TECH-DEBT.md`, which is
  for defects and risk.
