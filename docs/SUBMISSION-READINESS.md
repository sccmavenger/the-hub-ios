# Submission Readiness — Change Log & Status

**When:** 2026-09-18
**Who:** Claude Code (autonomous session authorized by Danny), driven by a full
pre-submission review: an end-to-end code review, a security/privacy review of
the app + live Supabase backend, and an App Review guideline audit.
**Why:** Prepare The Hub iOS v1.2 for first App Store submission. Each item
below cites the finding it closes. Findings marked *accepted risk* were
deliberately deferred — reasons noted.

---

## 1. Backend changes (live Supabase project `fnlufxhznqclpajyadcc`)

### `supabase/007-launch-hardening.sql` — applied to prod 2026-09-18, verified by behavior tests
| # | Change | Why |
|---|---|---|
| 1 | Dropped `trg_auto_approve_coach` + its function (from 003, "REMOVE BEFORE LAUNCH") | Any anonymous signup instantly became an approved coach with access to minors' profiles, gated contact info, and DMs. The single worst finding of the review. |
| 2 | `handle_new_user` trigger now creates `user_profiles`, `user_roles`, and `athletes` rows from signup metadata (`signup_role`, `full_name`, `date_of_birth`) | With email confirmation on, the client has no session after signUp and can't insert its own rows; the old client-side flow was also non-atomic (could strand half-created accounts). |
| 3 | `enforce_guardian_consent` now requires a DOB to publish and guardian consent for ALL under-18s (was: under-13 with non-null DOB only) | A minor could publish by simply clearing their date of birth. Verified both existing published athletes already satisfy the new rule before deploying. |
| 4 | `messages insert`: coaches can only start threads with **published** athletes | Coaches could previously DM any athlete UUID, including unpublished ones. |
| 5 | New `trg_message_immutable`: messages are immutable after send except `read_at` | The old update policy let either party rewrite message bodies — unacceptable where conversations may be evidence in abuse reports. |
| 6 | `coach_saved_athletes`: insert requires published athlete (select/update/delete unchanged) | Bookmarks unlock contact info; pre-bookmarking unpublished athletes must not be possible. |

Verified live after apply: trigger gone, policies present, body-edit attempt
rejected, consent-removal on a published minor rejected, athlete reply via RLS
works, signup trigger creates all three rows (tested in a rolled-back
transaction).

### Auth configuration (Supabase management API)
| Setting | Before | After | Why |
|---|---|---|---|
| `mailer_autoconfirm` | true | **false** | Coach/guardian emails were never verified; throwaway accounts were free. |
| `password_min_length` | 6 | **8** | Weak minimum for accounts holding minors' PII. Client validation updated to match. |
| `site_url` | http://localhost:3000 | https://summithoops.com | Confirmation-link redirect target pointed at localhost. |

**SMTP — DONE 2026-09-18:** auth email now goes through **Resend**
(smtp.resend.com:465, key in `.secrets/resend-api-key`, gitignored; email rate
limit raised to 100/hr). Verified end to end: a live signup produced a real
"Confirm your email address" send in Resend. Sender is currently
**"The Hub" <noreply@gforcedigital.net>** because summithoops.com is NOT
verified in the Resend account — once it is, update `smtp_admin_email` via
Supabase dashboard → Auth → SMTP (or the management API). The API key was
shared in chat; rotate it in Resend whenever convenient. Also note: with
confirmations on, the auth server rejects non-routable signup domains
(`.example` etc.) — existing `.example` review accounts are unaffected
(already confirmed).

### Demo data
- Rotated 6 demo coach accounts (`coach.*@mailinator.com` →
  `coach.*@summithoops.example`, passwords scrambled). Mailinator inboxes are
  public and the old shared password was in git history — anyone could
  password-reset into an approved coach account. Seeded demo data (messages,
  views, saves) kept: user IDs unchanged. See STATUS.md.
- **Left alone deliberately:** `ctguillory@mailinator.com` (Danny's personal
  test athlete). Same public-inbox risk applies — **Danny should change this
  account's email before launch.**
- The App Review athlete (`apple.review.athlete@summithoops.example` /
  `ReviewAthlete2026!`) is the fully seeded fictitious profile "Jalen Brooks"
  (photos in private storage with 1-year signed URLs, schedule, college list,
  NCAA readiness, coach messages/views/saves). Built 2026-09-18 for App Store
  screenshots and reviewer use.

## 2. iOS app changes

| File | Change | Why (finding) |
|---|---|---|
| `Views/Auth/SignUpView.swift` | Coach signup removed (athlete/parent only); terms/privacy consent line with in-app document sheets; "confirm your email" alert when signUp returns no session; 8-char password hint | Coach tabs were placeholder shells reachable from public signup (Guideline 2.1); UGC apps must present terms (1.2); email-confirmation flow |
| `Services/AuthService.swift` | signUp sends role/name/DOB as metadata; returns whether email confirmation is pending; client-side role/athlete inserts and signUpCoach removed | Server trigger owns signup now (atomic); coach onboarding is web-only |
| `Views/Legal/LegalView.swift` | **New** — in-app Terms of Service + Privacy Policy (drafts pending counsel) | No terms/privacy existed anywhere (1.2, 5.1.1) |
| `Views/Account/AccountView.swift` | Legal card (Terms/Privacy); block-list load failure shows retry instead of "you haven't blocked anyone" | Legal access; a safety feature misreporting state |
| `Views/Main/MainTabView.swift` | Coach/admin "coming soon" tabs replaced with "tools are on the web" signpost + More tab; role-fetch failure shows retry screen instead of the pending-approval dead end | 2.1 placeholder UI; transient network failure stranded signed-in users |
| `ViewModels/Auth/AuthViewModel.swift` | `roleLoadFailed` flag; failed role fetch keeps existing roles | Same dead-end fix |
| `ViewModels/Profile/ProfileEditViewModel.swift` | Publish requires DOB; missing DOB treated as blocker (mirrors DB trigger); non-numeric text in numeric fields is an error instead of silently nulling the saved value | Consent bypass; silent data loss |
| `Views/NCAA/NCAAJourneyView.swift` | Failed load shows error+retry (never an editable empty state), failed autosave shows banner with retry; More-menu entry no longer spins forever on nil session | Silent fetch failure could overwrite saved NCAA progress with an empty snapshot — the worst data-loss bug found |
| `Views/Dashboard/ActivityDetailViews.swift` | **In-app message replies** (compose bar, send via new `AthleteService.sendMessage`, RLS-verified live); "Replying arrives with the Messages update" future-promise removed; block/unblock failures alert the user; Bookmarks/Threads network failures show retry instead of fake empty states; shared `LoadErrorState` view | Messaging was read-only with "coming soon" copy (2.1); silent safety/empty-state failures |
| `Services/AthleteService.swift` | `sendMessage` added; `fetchMessages` capped at newest 1000 | Reply feature; unbounded fetch |
| `Views/Insights/InsightsView.swift` | Load failure shows retry instead of zeroed stats; "Summit Hoops staff" → "The Hub staff"; root view no longer spins forever on nil session | Misleading zeros; brand leak |
| `Views/Messages/MessagesTabView.swift`, `Views/Dashboard/DashboardView.swift` | Spinner no longer hangs on nil session; parent empty-state copy now points to the real create-profile flow instead of "arrives in an upcoming update" | 2.1 future-promise copy; hangs |
| `Utilities/Extensions/String+Validation.swift` | Password minimum 6 → 8 | Match server config |
| `docs/legal/terms-of-service.md`, `privacy-policy.md` | **New** — website copies generated from the in-app text (keep in sync) | For the future summithoops.com |

Earlier same day (also this session): `HubFormFields.swift` gained `maxLength`
(jersey 2 digits, grad year 4); `PublicProfileView.swift` photo grid fixed
(square cells) + fullscreen swipeable photo viewer added.

Build verified clean after all changes (2026-09-18 11:36).

## 2b. Full-app stress test — 2026-09-18 afternoon

Four device-driven adversarial passes (profile editor, colleges/NCAA/insights/
dashboard, messaging/safety/account, auth) on the iPhone 18 Pro Max simulator,
deliberately trying to crash the app with garbage input, rapid taps, limit
abuse, and backgrounding.

**Zero crashes.** Same process ID survived every pass; no `.ips` crash reports
exist for the app; console had no fatal/exception/termination entries. Apple's
2.1(a) crash-on-review risk looks low.

Bugs found and fixed (all verified on a rebuilt binary unless noted):

| Bug | Fix | File |
|---|---|---|
| **Game dates displayed/stored one day early** — date-only strings parsed as UTC while pickers produce local midnight | Date-only strings now parse AND format in local time; timestamps still parse as instants | `Date+Formatting.swift`, `ProfileEditViewModel.swift` |
| Accidental college delete (bare 16pt trash, list reflows under the finger) — cost two real rows during testing | Confirmation dialog before removal; same added for videos and games | `CollegeListView.swift`, `ProfileEditView.swift` |
| Rapid pull-to-refresh showed raw `Swift.CancellationError` and blanked the colleges list | Cancellation is swallowed (a superseded refresh is not a user-facing error) | `CollegeListViewModel.swift` |
| Invalid video URL was rejected **silently** — field cleared, no message | Inline error next to the field; input retained on failure; error clears on edit | `ProfileEditViewModel.swift`, `ProfileEditView.swift` |
| Game with no opponent and no location created a blank profile row | Requires opponent or location, inline error otherwise | same |
| Bio could be typed past 1000 chars, only failing at save | Hard cap at the limit while typing | `ProfileEditView.swift` |
| No input caps on height/weight/GPA/SAT/ACT/NCAA ID/major/titles | Per-field `maxLength` (18-digit SAT input no longer possible) | `ProfileEditView.swift` |
| NCAA GPA decimal pad could not be dismissed (no return key) and covered the toggles | Keyboard "Done" accessory + scroll-to-dismiss | `NCAAJourneyView.swift` |
| Keyboard covered Save/Cancel/Send on sign-in, sign-up, report sheet, account | `.scrollDismissesKeyboard(.interactively)` on those scroll views | 4 files |
| Sign-up SecureField dropped keystrokes for fast typists — the validation hint appearing/disappearing re-created the field | Hint occupies reserved space instead of being inserted; also added a "passwords don't match" message | `SignUpView.swift` |
| Leading space in email (iOS autofill) → misleading "Invalid login credentials" | Email trimmed + lowercased on sign-in and password reset | `AuthViewModel.swift` |
| Stale "Invalid login credentials" appeared on the Forgot Password sheet | Shared error cleared when the sheet opens | `ResetPasswordView.swift`, `SignInView.swift` |
| Sent message rendered off-screen (no scroll-to-bottom) | `ScrollViewReader` scrolls to newest on open and on send | `ActivityDetailViews.swift` |
| Gallery caption lost unless the user pressed Return | Also saves on focus loss | `ProfileEditView.swift` |
| Block/unblock had a ~2s dead zone with no feedback | Spinner in the toolbar while the change is in flight | `ActivityDetailViews.swift` |
| ZIP geocode warning was invisible at the bottom of a long form | Shown in the "Profile Saved" alert | `ProfileEditView.swift` |

Verified passing under abuse (no change needed): 2-digit jersey / 4-digit grad
year caps, all numeric range validation, the 10-college limit, core-course
stepper clamping, rapid toggle flipping, division switching, rapid tab cycling,
dashboard drill-ins, background/restore, block→unblock→restore, report submit
and cancel, delete-account confirmation gate (not executed), legal sheets,
under-13 signup block, coach role absent from signup, duplicate-send guard,
whitespace-only send guard, 150-char college name, unread badge clearing.

Known-remaining cosmetic items (non-blocking): the game-delete confirmation
popover anchors to the top of the screen rather than its row; the Forgot
Password sheet does not prefill the email already typed; secure fields render
empty when unfocused (simulator rendering); Sign Out has no confirmation.

## 2c. Submission prep — 2026-09-18 afternoon (autonomous pass)

Danny delegated everything except the website and support inbox (deferred).

**ESPN / third-party logos — REMOVED.** `CollegeDirectory.logoURLs` now returns
an empty array. The old chain hot-linked ESPN's CDN for NCAA team marks plus
Google and DuckDuckGo favicon services. Those are third-party trademarks with
no license, so the App Store Connect content-rights question could not be
answered truthfully, and the favicon calls added two more third-party
recipients to the privacy disclosure. College crests now use the existing
monogram fallback. **Answer "Does not contain third-party content."**
Reversible: return URLs from that one function and the whole loader still works.

**Crest monograms rebuilt.** They now derive from the school's own web domain
(ku.edu → "KU", umkc.edu → "UMKC", slu.edu → "SLU"), which is the abbreviation
each school chose for itself. The previous name-initials rule rendered
University of Kansas as "UK" — which is Kentucky — and produced inconsistent
1–2 letter results that collide across 1,351 programs. Simulated over the full
dataset: every school yields 1–4 characters, no blanks, no overflow. Badges
also got a tinted fill plus border so the tile is visible on both the card and
the search list, and shrink-to-fit so 4-letter monograms no longer truncate.

**Deployment target 26.5 → 18.0.** iOS 26.5 would have excluded all but very
recently updated devices; it appears to have been a new-project default rather
than a decision. Compiles clean at 18.0 (the compiler verifies API
availability, so there is no missing-symbol crash risk). **Caveat: not
runtime-tested below iOS 27 — only the iOS 27 simulator runtime is installed.**
Install an iOS 18 runtime and smoke-test before submitting if you want
certainty; reverting is a one-line build-setting change. It also builds clean
at 17.0 if you want to go wider.

**Two bugs found during screenshot review and fixed:**
- Profile Preview → Contact Info hyphenated long emails mid-address
  (`…summithoops.exam-` / `ple`), showing a character that isn't in the
  address. Fixed with baseline alignment and layout priority so the label
  wraps instead of the value.
- Crest monogram tiles were invisible in the Add-College search list (badge
  fill matched that list's background) — see above.

**Demo data polish for screenshots:** the profile photo is now a tight action
crop (the previous one rendered as a tiny distant figure in the circular
avatar), and the demo coach's viewer label changed from "Summit Hoops" to
"Wake Forest" so Insights no longer lists the company as a college program.

**Screenshots captured:** six at 1320×2868 (6.9" iPhone) in `.screenshots/`,
now gitignored. See `docs/APPSTORE-CONNECT-FIELDS.md`.

**All App Store Connect field content written** to
`docs/APPSTORE-CONNECT-FIELDS.md` — name, subtitle, description, keywords,
promotional text, age-rating answers, privacy-label matrix, review notes, and
demo credentials. Only three fields remain unfillable by me: Privacy Policy
URL, Support URL (both blocked on the website), and your phone number.

## 2d. College logos — admin kill switch (2026-09-18)

Replaces the blanket removal in §2c. Logos are back, but behind a remote,
admin-controlled flag rather than hardcoded.

**How it works**
- `supabase/008-app-settings.sql` adds `public.app_settings` (key/value).
  Row `college_logos_enabled`, default **false**. Any signed-in client can
  read; only `has_role('admin')` can write (RLS-verified live: an athlete's
  PATCH was rejected with no rows changed).
- `Services/AppSettingsService.swift` loads flags once per session and
  **fails closed** — any fetch error, missing row, or null value leaves
  logos OFF. The risky state is displaying unlicensed marks, so uncertainty
  must resolve to monograms.
- `CollegeDirectory.logoURLs` returns `[]` and `CrestLoader.crest` returns
  nil when the flag is off; flipping the flag clears the crest cache, since
  cached results are flag-dependent.
- `Views/Admin/AdminSettingsView.swift` — in-app toggle under
  More → Admin Settings, visible only to admins. Writes the same row the web
  admin portal should write, so either surface controls all clients.
- `Compliance.trademarkNotice` renders on the Colleges screen **only while
  logos are on**, disclaiming ownership and affiliation (the pattern
  competitor CoachedUp ships).

**Verified end to end on device:** flag ON → all six demo schools show real
logos + notice visible; flag OFF → letter monograms + notice gone. No crashes.

**Name-resolution bug found and fixed during that test.**
`CollegeDirectory.find(named:)` matched only exact names, so a stored
"Louisiana State University" missed the directory's canonical "Louisiana
State University and Agricultural and Mechanical College" and silently fell
back to a monogram while other schools showed logos. Lookup now tries exact
name → common name → unique prefix → prefix disambiguated by acronym (the
flagship campus carries the bare acronym as its common name, e.g. "LSU" vs
"LSU Shreveport"). It deliberately returns nil when still ambiguous
("University of Texas" matches three campuses) because showing the wrong
school's logo is worse than showing a monogram. Simulated across all 1,351
directory entries before shipping.

**⚠️ DECISION REQUIRED BEFORE SUBMITTING.** The flag's state must match the
Content Rights answer in App Store Connect:

| Flag at submission | Content Rights answer |
|---|---|
| **OFF** (current, recommended) | "Does not contain, show, or access third-party content" |
| ON | "Yes… and I have the necessary rights" — defensible only on a fair-use basis, which is weak for logos (see below) |

Shipping OFF and flipping ON after approval is **not** a free workaround: it
changes what the app displays relative to what was reviewed and declared, and
Apple's 2.3.1 prohibits hidden or undocumented functionality. If you intend to
run with logos on, declare it at submission and be ready to defend it.

**Legal basis, honestly stated.** Nominative fair use (*New Kids on the
Block*, refined in the Lexus/*Tabari* case) protects using a school's **name**;
prong two limits you to only as much of the mark as necessary, and *Tabari*
turned on the defendants using the word "Lexus" but **not** the logo. So the
fair-use footing for logos specifically is weak. A disclaimer helps but does
not cure it. No data vendor can license these marks — Sportradar,
SportsDataIO and API-Sports all expressly disclaim owning them. The durable
fix is coach-supplied logos at coach onboarding (permission from the rights
holder's own representative). Get counsel's view before running with the flag
on in production.

## 2e. Domain, hosting, and account ownership — 2026-09-19

Findings from verifying who owns what, since several assumptions were wrong.

**`summithoops.com` is NOT the client's.** WHOIS registrant is
HugeDomains.com, registrant name "This Domain is For Sale". It was never
available to us. The client's real site is **`summithoops.net`** (Summit Hoops
MO — Missouri youth basketball tournaments, hosted on Wix, contact
`summithoopsmo@gmail.com`).

**Decision: ship on the developer's own domain to stay unblocked.** Danny is
building this for Summit Hoops but wants no dependency on the client's
accounts for launch. So v1 uses `thehub.gforcedigital.net` (a domain he owns;
already verified in Resend) for the privacy, terms, and support pages, and
`info@summithoops.net` as the contact address (the client's Google
Workspace domain, which does accept mail).

Migration path when the client is ready: App Store Connect **metadata URLs can
be changed without resubmitting the binary**, so the Privacy Policy and
Support URLs can move to `summithoops.net` later with no review cycle. The
in-app legal text and `docs/legal/*.md` would need matching edits (and those
ship in a binary), so plan that with a future version.

Everything now points at the new domain: Supabase `site_url`, Resend sender
(`noreply@gforcedigital.net`), the in-app legal screens, both markdown docs,
and the page copy in `docs/legal/` (the throwaway static site that
briefly lived in `site/` was deleted 2026-09-20 — the website is being built
with a separate tool).

**Apple Developer account: no dependency.** Signing team `CB4AAVWWUD` is
Danny Guillory's own account, and a distribution provisioning profile for
`com.summithoops.SummitHoops-TheHub` already exists locally — so the archive
and upload can be done today without the client.

⚠️ **Consequence worth deciding on later:** the App Store "seller" shown to
users will be the account holder's name, not "Summit Hoops". If the client
wants the listing under their business, that needs an Organization account
(requires a D-U-N-S number) and an app transfer. Apple supports transferring
an app between accounts, so shipping now under the developer account does not
foreclose it — but it is easier to plan than to undo.

**Contact address: `info@summithoops.net`** — confirmed existing and receiving (Summit Hoops Google Workspace; MX + SPF verified in DNS). Used everywhere a user, parent, or reviewer needs to reach the app owner: privacy requests, security reports, support, and general questions. Appears in the in-app legal screens, all four site pages, and `docs/legal/*.md`.

## 2f. First App Review outcome — rejected 2026-09-22, "Information Needed"

**What:** Submission `0e44c989-aa66-483b-ab00-4c861ebd1253` (submitted
2026-09-21 23:02 CDT) was rejected under **Guideline 2.1 — Performance: App
Completeness**, with the message "Information Needed — New App Submission."

**Why (per Apple's message):** the developer account has a limited App Review
history, so Apple wants extra material before completing review. **No bug,
crash, or policy violation was cited.** Before this, a first Add-for-Review
attempt on 2026-09-21 was blocked because the **Copyright field was empty**
(the one field never set via API); fixed same day via
`PATCH appStoreVersions` → `© 2026 Summit Hoops`.

**What Apple asked for** (must go in the Resolution Center reply AND the
Review Notes):
1. Screen recording from a **physical device on the latest OS** showing launch,
   typical flow, registration/login/**account deletion**, and UGC
   **report/block** mechanisms.
2. Purpose and target audience.
3. Setup/access instructions + credentials.
4. External services list.
5. Regional differences (or confirmation of none).
6. Regulated-industry / third-party-material documentation (N/A here).

**Done (who/when/how):** Claude, 2026-09-23, via `scripts/asc.py` — verified
demo account still signs in against prod Supabase and the Jalen Brooks profile
is intact (published, photo, 5 gallery photos, 5 events, 4 messages), then
appended items 2–6 to the App Review Notes (now 3,385/4,000 chars): purpose,
per-tab feature guide, external services (Supabase, Resend, zippopotam.us —
no payments/ads/analytics/AI), US-only distribution, no regulated industry,
crest monograms in lieu of logos.

**Remaining (Danny):** record the video on a physical iPhone (script provided
in chat 2026-09-23), then use **Reply to App Review** in the Resolution Center
with the reply text (also provided in chat), attach the video, and resubmit.

## 2g. Review account deleted and rebuilt; demo roster seeded — 2026-09-23

**What happened:** the Apple review account
(`apple.review.athlete@summithoops.example`, the Jalen Brooks demo profile)
was deleted in-app on 2026-09-23 — the delete-account flow was exercised
while signed into it, most likely while rehearsing the review screen
recording. Deletion worked exactly as designed: auth user, athlete row,
photos, messages, consent records, everything gone. Discovered by Claude the
same day while seeding new demo profiles (a photo-count query came back
empty).

**Fix (Claude, 2026-09-23, via Supabase admin API + management SQL):**
recreated the account with **identical credentials** — the demo login in
Apple's App Review Information still works unchanged — and rebuilt the Jalen
Brooks profile in full (published, guardian consent, photo + 5 gallery
images, 5 events, 6 colleges, 4 coach messages, NCAA readiness, 34 seeded
profile views, 2 coach saves).

**Also seeded — 4 new marketing/demo athletes** (credentials in STATUS.md):
Darius Cole (2027 PG), Maya Thompson (2027 SG, womens), Elijah Reed
(2028 PF), Sofia Ramirez (2027 SF, womens). Same completeness as Jalen.
Photos are PIL-generated sports-card graphics (dark gradient, jersey number,
caption plate — matches the app palette) uploaded to the private
`athlete-media` bucket with 1-year signed URLs. All 5 sign-ins and image
URLs verified live.

**Lesson recorded:** never demo account deletion on a populated account —
register a throwaway in the app and delete that.

## 2h. App approved; demo accounts purged — 2026-09-29

**App Store approval received 2026-09-29** (version 1.2, build 4).

**Purge (Claude, 2026-09-29, at Danny's request):** all 12
`@summithoops.example` accounts removed — 5 demo athletes (incl. the Apple
review athlete), the review coach, 6 seeded coaches. Deleted in order: every
dependent DB row (photos, events, colleges, contacts, NCAA readiness,
guardians, invites, profile views, messages, saves, searches, requests,
reports, blocks, notifications, athletes, roles, profiles), 30 storage
objects across 5 `athlete-media` folders, then the auth users. Orphan scan
across all tables returned zero. **Why:** published fictitious athletes would
surface in real coaches' searches now that the app is live.

**Consequence:** App Review Information no longer has a demo login (fields
cleared, notes reworded). A fresh demo athlete must be seeded before the
next submission — see TECH-DEBT #18. Recipe: create auth user via admin API
with `signup_role`/`full_name`/`date_of_birth` metadata (trigger builds the
rows), generate PIL sports-card images, upload to `athlete-media/{uid}/`,
sign 1-year URLs, then seed events/colleges/contacts/consent/NCAA rows.

## 3. Accepted risks / deferred (with reasons)

> **⚠️ This section is a frozen pre-submission snapshot.** The living tracker
> is **`docs/TECH-DEBT.md`** (created 2026-09-23) — all items below were
> migrated there and new debt goes there, not here.

- **1-year signed media URLs stored in DB** — outlive unpublish/block. Correct
  fix (store paths, sign on read) touches every media read path; deferred
  post-v1. Exposure requires already having had access to the URL.
- **ESPN/Google/DuckDuckGo college-logo fetches** — third-party trademarked
  content; affects the App Store "content rights" declaration. Kept for UX;
  Danny decides: keep + declare rights, or remove `CollegeDirectory` logo URLs.
- **ZIP → api.zippopotam.us geocoding** — 5-digit ZIP only, disclosed in the
  privacy policy and App Privacy label. Move server-side later if desired.
- **Guardian consent still self-attested** (name+email typed in-app, now
  DOB-gated and DB-enforced) — true guardian email verification needs a
  server-side flow (e.g. edge function + confirmation link); recommended
  fast-follow.
- **No CAPTCHA on auth** — requires client SDK integration; email confirmation
  now provides the main friction. Revisit if abuse appears.
- **Athlete-ID enumeration via `record-profile-view` 404s** — minor; requires
  edge-function redeploy; fold into next functions change.
- **Dashboard athlete-switcher can briefly show stale data on fetch failure;
  gallery captions save only on Return; college sheet closes on failed save** —
  minor UX, non-blocking.
- **Coach web experience** — iOS shows approved coaches a signpost to the web;
  the web app is a separate codebase and out of scope here.

## 4. Remaining human tasks before submission (Danny)

1. ~~Configure custom SMTP~~ — **done via Resend 2026-09-18** (see §1).
   Remaining sub-task: verify `summithoops.com` in Resend and switch the
   sender from `noreply@gforcedigital.net`.
1b. ~~Screenshots~~ — **done** (six, 1320×2868, in `.screenshots/`).
1c. ~~ESPN logo / content-rights decision~~ — **done**: removed, answer "no
   third-party content".
1d. **Smoke-test on iOS 18** before submitting (deployment target was lowered
   from 26.5; only the iOS 27 runtime is installed here so it is untested).
1e. **Your phone number** for App Review Information — the only other field
   I could not fill.
2. **Publish the website** (summithoops.com or GitHub Pages): privacy policy +
   terms (source in `docs/legal/`) + a support/contact page. App Store Connect
   requires live Privacy Policy and Support URLs.
3. ~~Stand up a support inbox~~ — address is now `info@summithoops.net`
   (client's Google Workspace). Remaining: confirm that mailbox/alias actually
   exists and delivers.
4. **Counsel review** of the terms/privacy drafts.
5. Change `ctguillory@mailinator.com` to a private email.
6. Decide on ESPN logo fetching (content-rights declaration).
7. App Store Connect data entry — full field-by-field content was provided in
   chat on 2026-09-18 (name/subtitle/keywords/description/age rating/privacy
   labels/review notes with the Jalen Brooks demo account).
8. Capture the three 6.9" screenshots (1320×2868) from the demo profile.
