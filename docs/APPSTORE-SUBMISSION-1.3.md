# App Store Connect — Version 1.3 submission worksheet

**Use this file every time we touch the 1.3 submission form.** It lists what
App Store Connect holds, the value for each field, and the decisions behind
them.

> **STATUS 2026-10-01 14:05 CDT — form filled via the API** (`scripts/asc-apply-1.3.py`,
> verified by read-back): promotional text, description, What's New, review
> notes, demo athlete credentials, manual release, and the social-media age
> rating answer (Yes) are all set. Demo athlete + coach seeded with
> `scripts/seed-demo-accounts.py` (credentials in `.secrets/demo-accounts.json`).
> Build 3 is attached and contains every fix in `6de0b75` (archived 11:45 CDT,
> after the last source change at 11:33). **Remaining before "Add for Review":**
> gates G2 (device pass), G5 (website legal copy), G6 (Tony Stark), G8
> (adult-contact decision). After approval: `scripts/seed-demo-accounts.py --purge`.

The original "FILL IN / KEEP" markers below are kept as the record of what
changed. Snapshot first pulled **2026-10-01, 11:50 CDT**. Re-pull any time:

```bash
python3 scripts/asc.py get "appStoreVersions/5d7d0a83-d7fc-4eed-9c83-29b60b386ad9?include=appStoreVersionLocalizations,build,appStoreReviewDetail"
python3 scripts/asc.py get "appInfos/5df4189a-e2b8-4832-a935-196050f235eb/ageRatingDeclaration"
```

| Record | ID (for API patches) |
|---|---|
| App | `6813542102` (`com.summithoops.SummitHoops-TheHub`) |
| Version 1.3 | `5d7d0a83-d7fc-4eed-9c83-29b60b386ad9` — state PREPARE_FOR_SUBMISSION |
| en-US localization | `5ccfea50-c50d-4b41-b8b4-3fa7f0273d56` |
| App Review detail | `9133211e-efbe-43a2-b82d-950321106c89` |
| App Info (1.3) | `5df4189a-e2b8-4832-a935-196050f235eb` |
| Attached build | `ea872181-…` = **build 3**, uploaded 2026-10-01 09:48 PDT |

The 1.2 field reference (`docs/APPSTORE-CONNECT-FIELDS.md`) is still the
source for anything not mentioned here.

---

## 0. Before opening the form — release gates

| # | Gate | Owner | Status |
|---|------|-------|--------|
| G1 | **Build 3 contains the TestFlight-feedback fixes.** Verified: the build 3 archive (`~/Library/Developer/Xcode/Archives/2026-10-01/TheHub 10-1-26, 11.45 AM.xcarchive`) was created 11:45:51 CDT; the last fix file was saved 11:33:05 CDT. | Claude | ☑ |
| G2 | Device test pass per `docs/COACH-MODE-TEST-CASES.md` (at minimum groups C, F, G, H). | Danny | ☐ |
| G3 | Demo **athlete** and demo **coach** accounts seeded (§4 below). TECH-DEBT #18/#29. | Claude | ☑ 2026-10-01 |
| G4 | Social-media age-rating answer decided (§3). TECH-DEBT #40. | Claude (recommendation applied; Danny may flip) | ☑ Yes |
| G5 | Website `/terms` and `/privacy` on Lovable carry the 2026-09-30 and 2026-10-01 text from `docs/legal/`. TECH-DEBT #13/#22. Apple's reviewers do open the privacy URL. | Danny (Lovable) | ☐ |
| G6 | Delete or re-key the `tstark@mailinator.com` test coach (public inbox). | Claude, on Danny's go | ☐ |
| G7 | `college_logos_enabled` is still **false** (it is, verified 2026-10-01) so the Content Rights answer stays valid. | — | ☑ |
| G8 | Adult-athlete contact question answered (TECH-DEBT #44): today adults 18+ still share their own email/phone with coaches who saved them. Keep or make it never? Affects review-note item 2 below. | Danny | ☐ |

---

## 1. Version Information (App Store → iOS App → 1.3)

### Screenshots — **DECIDE**
Current: the six 1.2 screenshots (6.5" set, all COMPLETE). They still match the
app except Edit Profile (now collapsible) and the Home toolbar (new bell).
Reviewers accept these; refreshing is optional. If refreshing, recapture on a
6.9" simulator at 1320×2868:

| Order | Capture | Notes |
|---|---|---|
| 1 | Home with the bell badge showing | athlete account |
| 2 | Public profile preview | unchanged |
| 3 | Action photos | unchanged |
| 4 | NCAA Journey (division pills now at the top) | |
| 5 | Insights | unchanged |
| 6 | My Colleges | unchanged |
| 7 (optional) | Coach Discover | shows the coach side exists — use the demo coach |

### Promotional Text — **FILL IN** (currently empty on 1.3; 169/170)
```
Build your recruiting profile, track your NCAA eligibility, and hear from verified college coaches — in the app where every coach is approved before they can see you.
```

### Description — **REPLACE** (current text is the 1.2 copy; 2,541/4,000)
```
The Hub puts a high school basketball player's entire recruiting story in one place — and puts it in front of real, verified college coaches.

BUILD A PROFILE THAT GETS NOTICED
Add your stats, academics, highlight video links, action photos, and game schedule — or import the schedule straight from your school's calendar file. Each section shows what's complete so you always know what to add next. When you're ready, publish; only approved college coaches can see your profile.

KNOW WHO'S WATCHING
See profile views, saves, and messages from college programs as they happen, with a notification center that tells you which program it was. Insights show which schools are paying attention so you can focus your outreach.

OWN YOUR NCAA JOURNEY
A step-by-step eligibility tracker covers the Eligibility Center, core courses, transcripts, and amateurism certification — with the official recruiting rules for your class year, sourced and dated.

TARGET YOUR SCHOOLS
Keep a list of the programs you're pursuing, from first interest to committed, with notes on every conversation.

TALK TO COACHES — ON THE RULES
Read and reply to messages from approved college coaches. Every coach message is checked against the NCAA recruiting calendar before it sends, and block and report tools are built into every conversation.

BUILT FOR FAMILIES
Parents can manage a young athlete's profile, and publishing a minor's profile requires recorded guardian consent. A coach never sees an under-18 athlete's own phone number or email. You can delete your account and all of your data at any time.

FOR COLLEGE COACHES
Apply in the app. Once our team verifies your program, discover published athletes for your sport, keep a recruiting board your whole staff shares, set alerts for new prospects who match a saved search, and message athletes when the rules allow.

The Hub is free for athletes. Coach accounts are individually reviewed and approved before they can see any athlete.
```

### What's New in This Version — **FILL IN** (currently empty; 1,046/4,000)
```
College coaches are now in The Hub.

FOR COACHES
• Coach Mode: apply in the app; once verified, discover published athletes for your program's sport, keep a shared recruiting board with your staff, save searches with alerts, and message athletes.
• Recruiting rules, enforced: messages are checked against the official NCAA recruiting calendar before they send.

FOR ATHLETES AND FAMILIES
• Notifications: a new bell shows saves, messages, and alerts, with mark-all-read and an optional message-preview setting.
• Edit Profile is now a checklist — every section collapses and shows what's complete.
• Import your game schedule from your school's calendar (.ics) file.
• Stronger privacy for minors: a coach never sees an under-18 athlete's own phone or email.
• Fixes: NCAA Journey no longer jumps when you switch divisions; My Colleges no longer scrolls sideways.
```

### Keywords — **KEEP** (91/100)
```
aau,hoops,recruit,ncaa,athlete,college,coach,scout,highlights,eligibility,hs sports,prospect
```

### URLs, copyright, version — **KEEP**

| Field | Current value |
|---|---|
| Support URL | `https://thehubsh.net/support` |
| Marketing URL | `https://thehubsh.net/` |
| Copyright | `© 2026 Summit Hoops` |
| Version | `1.3` (binary reports 1.3.0 — Apple matches them) |

### Build — **VERIFY** (gate G1)
Build 3 is attached. If you upload build 4, re-attach it here.

### Release option — **DECIDE**
Current: **Automatically release after approval** (`AFTER_APPROVAL`).
Recommendation: switch to **Manually release this version**. This release flips
on coach messaging with enforcement, and we want to purge the demo accounts and
re-check production before anyone downloads it.

---

## 2. App Review Information — **FILL IN**

| Field | Current | Set to |
|---|---|---|
| Sign-in required | Yes | Yes (KEEP) |
| Demo account username | **empty** → set | `apple.review.athlete@summithoops.example` |
| Demo account password | **empty** → set | in `.secrets/demo-accounts.json` (never in chat or git) |
| Contact first / last name | Danny / Guillory Jr | KEEP |
| Contact phone | +1 636-362-4590 | KEEP |
| Contact email | dguilloryjr@msn.com | KEEP |
| Attachment | none | optional: a 30–60 s screen recording of the coach flow (sign in as demo coach → Discover → save → message) saves a round-trip if the reviewer can't reach Coach Mode |

### Review Notes — **REPLACED 2026-10-01** (the 1.2 notes said coach onboarding was web-only and that there was one account type — both false in 1.3)

Apple's limit is 4,000 characters; this text is ~3,630 with credentials. The
coach credentials are substituted from `.secrets/demo-accounts.json` by
`scripts/asc-apply-1.3.py`, which holds this same text.

```
The Hub is a free recruiting-profile platform for US high school basketball players (ages 13-18), their parents, and the college coaches who recruit them. Key context:

1. Sign-in is required. The demo account above is a fully populated ATHLETE (fictitious data). To see the coach side: COACH username [demo coach email], password [demo coach password]. Both accounts are created fresh for each submission; the passwords always work.

2. Minor safety: publishing requires a date of birth, and any athlete under 18 must have recorded parent/guardian consent (name, email, timestamp) before the profile can be published - enforced in the database, not just the UI. A coach never receives an under-18 athlete's own phone or email; only guardian or club-coach details the family chose to list become visible, and only after the coach saves the athlete to their program's board. Coaches never receive date of birth, test scores, NCAA ID, exact location, or consent details.

3. Coach accounts cannot self-activate. Creating a coach account in the app only files an application; the coach sees a status screen with no athlete content until our staff manually verifies their affiliation with a specific college program and approves it. Only then does the account receive the coach role (enforced in the database). An approved coach can search published athletes for their program's sport and gender, save them to the program's shared recruiting board, set alerts on saved searches, and message them. Athletes and guardians are notified of saves, views, and messages with the program's name. Blocking a coach removes the athlete from that coach's results, board, and messages everywhere.

4. Recruiting-rule enforcement: before a coach's message sends, the server checks it against the official NCAA recruiting calendar for the athlete's class year and the coach's verified program (sources shown in-app with bylaw references and dates). A prohibited message is refused and the coach sees the rule and the date it opens. Athletes may always message a coach first.

5. User-generated content (photos, bios, messages) is moderated by our admin team. Every conversation has in-app Report and Block; reports notify all administrators and are reviewed within 24 hours.

6. Account deletion is in-app: More > Account > Delete Account (athletes), Program > Account > Delete Account (coaches). It removes the profile, photos, messages, consent records, and the login.

7. Athletes under 13 cannot create an account; sign-up blocks them and directs a parent or guardian to create and manage the profile.

--- Background previously requested by App Review (Guideline 2.1) ---

8. Setup: sign in with the athlete demo above. Athlete tabs: Home (activity, notification bell), Profile (edit, preview, publish, .ics schedule import), Colleges, Messages (Report and Block in every thread), More (NCAA Journey, Insights, Account, legal). Coach tabs (credentials in item 1): Home, Discover, Board, Messages, Program. New accounts need a working email for the confirmation link.

9. External services: Supabase (auth, Postgres, scheduled jobs, private file storage); Resend (transactional email); zippopotam.us (public ZIP-to-city lookup; only the ZIP is sent). No payments, ads, analytics SDKs, AI services, or push notifications (notifications are in-app only).

10. Distributed in the United States only; no regional differences. Not a regulated industry. No third-party protected material: college crests are generic letter monograms, and NCAA rule text is our own plain-English summary linking to the NCAA's published manual.
```

---

## 3. Age Rating (App Information → Age Rating → Edit) — **DECIDE one answer**

Current declaration (1.3 App Info):

| Question | Current | Keep? |
|---|---|---|
| All content categories (violence, sexual, profanity, horror, drugs, mature, medical, gambling, contests, loot boxes, weapons) | None / No | KEEP |
| User-generated content | Yes | KEEP |
| Messaging and chat | Yes | KEEP |
| Unrestricted web access | No | KEEP |
| Parental controls | No | KEEP |
| Age assurance | No | KEEP (we verify age by self-reported DOB, not an assurance service) |
| **Social media** | **No** | **DECIDE — see below** |
| Social media age-restricted | No | follows the answer above |
| Advertising | No | KEEP |
| Age rating override | 13+ | KEEP |
| Age suitability URL | empty | optional: `https://thehubsh.net/age-rating` once the page exists |

**Social media — the only open question (TECH-DEBT #40).** Apple's September
2026 wording asks whether users can discover and interact with other users'
content. In 1.3 approved coaches search published athlete profiles and can
save and message them. There is still no feed, no athlete-to-athlete browsing,
no following, no reposting, and discovery is limited to adults holding an
admin-verified program membership.

- **Recommended: answer Yes.** Under-declaring a capability is a rejection
  reason; over-declaring only adds the Social Media descriptor and, with the
  13+ override already set, does not change the age band. If the form then
  asks whether social features are age-restricted, answer **Yes — restricted
  to verified adult coaches** (athletes cannot discover anyone).
- Alternative: keep No, on the basis that discovery is a vetted professional
  tool rather than social media. Defensible, but it is the answer a reviewer
  is most likely to challenge now that Discover exists.

**Recorded 2026-10-01:** `socialMedia = true`, `socialMediaAgeRestricted = false`
(the age-restricted option requires adopting Apple's Declared Age Range API,
which the app does not do), override stays 13+. Applied via API. Sources for
Apple's definition: [Apple Developer News](https://developer.apple.com/news/?id=tlur8uvi),
[9to5Mac, 2026-07-09](https://9to5mac.com/2026/07/09/apple-adds-social-media-questions-to-app-store-connect-age-rating-questionnaire/).
Consequence: the product page shows a Social Media descriptor and iOS 27 Time
Allowances files the app under Social Media. Flip back to `false` only if we
decide a vetted, adults-only search isn't "discovery" in Apple's sense.

---

## 4. Demo accounts — **SEEDED 2026-10-01** (`scripts/seed-demo-accounts.py`)

Re-runnable; `--purge` removes both accounts, their storage objects, the
fictitious program, and the credentials file after approval (§2h precedent).

| Account | Email | Password | What's in it |
|---|---|---|---|
| Demo athlete | `apple.review.athlete@summithoops.example` | `.secrets/demo-accounts.json` | "Jalen Brooks", men's, PG, class of 2027, DOB 2009-02-14 (17, so consent + contact redaction show), guardian consent recorded, profile photo + 4 gallery cards, 4 upcoming games (one MAYB), 3 target schools, NCAA readiness, contacts with guardian + club coach, 6 profile views, published |
| Demo coach | `apple.review.coach@summithoops.example` | `.secrets/demo-accounts.json` | "Casey Morgan", Head Coach, approved into the fictitious **Summit State University** (NCAA D1 men's); athlete saved to the board at Evaluating; one thread: athlete wrote first, coach replied through the rules-checked RPC (send succeeded — a 2027 grad is past the June 15 opening) |

Both sign-ins verified by password grant at seed time. Why a 2027 minor: the
reviewer sees consent, redaction, and a successful rules-checked send in one
account pair.

Why a minor demo athlete: it demonstrates the consent record and the contact
redaction the review notes describe. Why not reuse Tony Stark: public
mailinator inbox (gate G6).

---

## 5. App Privacy (App Information → App Privacy) — **REVIEW, likely KEEP**

1.2 declared nine data types (Name, Email, Phone, Coarse Location, Photos or
Videos, Other User Content, User ID, Product Interaction, Other Data Types),
all **Linked to user = Yes, Tracking = No, Purpose = App Functionality**. Still
accurate for 1.3:

| Change in 1.3 | Privacy label impact |
|---|---|
| Coach saved searches and alerts | Covered by **Other User Content**. Apple's "Search History" type is for search queries retained about the user; our saved searches are user-created content, so no new type is required. If you prefer to be conservative, add **Search History** (linked, not tracking, app functionality). |
| In-app notifications | No new type (no push tokens; no device identifiers). |
| Minors' phone no longer collected | **Phone Number** stays declared — guardians, club coaches, and adult athletes still enter phones. |
| Recruiting denial audit rows | Covered by **Product Interaction**. |
| pg_cron scheduled jobs | Server-side only; no label change. |

Tracking: **No** (unchanged). Privacy Policy URL: `https://thehubsh.net/privacy`
(KEEP) — but its page copy must be the 2026-10-01 text (gate G5).

---

## 6. App Information (unchanged) — **KEEP**

| Field | Value |
|---|---|
| Name | The Hub by SummitHoops |
| Subtitle | Get seen by college coaches |
| Categories | Sports / Education |
| Content Rights | Does not contain third-party content (valid while `college_logos_enabled` is false) |
| Pricing | Free, United States only |

---

## 7. Applying values by API instead of the web form

Once the blanks are filled, Claude can patch everything except screenshots,
the age-rating social-media answer (also patchable, but decide first), and the
build attachment:

```bash
# What's New / promotional text / description
python3 scripts/asc.py patch appStoreVersionLocalizations/5ccfea50-c50d-4b41-b8b4-3fa7f0273d56 \
  '{"data":{"type":"appStoreVersionLocalizations","id":"5ccfea50-c50d-4b41-b8b4-3fa7f0273d56","attributes":{"whatsNew":"…","promotionalText":"…","description":"…"}}}'

# Review notes + demo account
python3 scripts/asc.py patch appStoreReviewDetails/9133211e-efbe-43a2-b82d-950321106c89 \
  '{"data":{"type":"appStoreReviewDetails","id":"9133211e-efbe-43a2-b82d-950321106c89","attributes":{"notes":"…","demoAccountName":"…","demoAccountPassword":"…","demoAccountRequired":true}}}'

# Manual release
python3 scripts/asc.py patch appStoreVersions/5d7d0a83-d7fc-4eed-9c83-29b60b386ad9 \
  '{"data":{"type":"appStoreVersions","id":"5d7d0a83-d7fc-4eed-9c83-29b60b386ad9","attributes":{"releaseType":"MANUAL"}}}'
```

Never paste the demo passwords into chat for the API route; put them in
`.secrets/demo-accounts` and Claude will read them from there.

---

## 8. Submission log

| Date | Action | By | Result |
|---|---|---|---|
| 2026-10-01 | 1.3 version created in ASC; build 3 attached; metadata copied from 1.2 (review notes still web-only wording) | Danny | prepare for submission |
| 2026-10-01 | Demo athlete + coach seeded (`scripts/seed-demo-accounts.py`); promotional text, description, What's New, review notes + demo credentials, manual release, social-media = Yes applied via `scripts/asc-apply-1.3.py`; read-back verified | Claude | ready pending gates G2, G5, G6, G8 |
| | | | |
