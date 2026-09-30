# App Store Connect — field-by-field content

> **STATUS 2026-09-21 (verified live via the API).** Everything is set:
> name, subtitle, both categories, content rights, age rating (13+),
> description, keywords, promotional text, screenshots (6, COMPLETE),
> App Review contact/demo/notes, manual release, build 3 attached
> (minOS 18.0, VALID), privacy/support/marketing URLs on thehubsh.net,
> App Privacy label, and **copyright `© 2026 Summit Hoops`** — the last
> one was missed on the first Add for Review attempt (Apple's only
> blocker) and was patched via the API on 2026-09-21.
>
> Nothing remains except clicking **Add for Review**.
> The rest of this file is reference.

Paste-ready values for The Hub v1.0. Prepared 2026-09-18.
Every field is filled. The only prerequisite is deploying the site so the
Privacy Policy and Support URLs resolve (page copy: docs/legal/).

---

## 1. New App (My Apps → + → New App)

| Field | Value |
|---|---|
| Platform | iOS |
| Name | `The Hub by SummitHoops` (as registered 2026-09-19) |
| Primary Language | English (U.S.) |
| Bundle ID | `com.summithoops.SummitHoops-TheHub` |
| SKU | `SUMMITHOOPS-THEHUB-001` |
| User Access | Full Access |

Apple indexes the app name for search, so the keyword list below
deliberately avoids repeating "hub" and "summit".

## 2. App Information

| Field | Value |
|---|---|
| Subtitle | `Get seen by college coaches` |
| Primary Category | Sports |
| Secondary Category | Education |
| Content Rights | **"Does not contain, show, or access third-party content."** ⚠️ Correct **only while the `college_logos_enabled` admin flag is OFF**, which is its current and recommended shipping state — crests render as letter monograms and no third-party imagery is fetched. If you switch that flag ON, you must change this answer to "Yes… and I have the necessary rights" and be ready to defend a fair-use basis. See SUBMISSION-READINESS.md §2d. |

### Age Rating questionnaire

Apple replaced this questionnaire in 2025: tiers are now 4+, 9+, 13+, 16+, 18+
(12+ and 17+ were retired), with new sections for in-app controls, app
capabilities, violent themes, and medical/wellness. Since September 2026 there
are also mandatory social-media questions. Apple does not publish the wording,
so match these by category to whatever the form shows.

**Every content category → `None`** (most offer None / Infrequent / Frequent):

| Category | Answer |
|---|---|
| Violence — cartoon, fantasy, or realistic | None |
| Violent themes | None |
| Sexual content or nudity | None |
| Profanity or crude humor | None |
| Horror or fear themes | None |
| Alcohol, tobacco, or drug use | None |
| Mature or suggestive themes | None |
| Medical or wellness content | None — height/weight/GPA are athletic stats, not medical advice |
| Chance-based: gambling, simulated gambling, contests, loot boxes | None (all four) |

**In-app controls and capabilities** — this is what actually drives the rating:

| Question | Answer | Basis |
|---|---|---|
| User-generated content | **Yes** | Photos, bios, messages |
| Messaging / chat between users | **Yes** | Athlete ↔ approved coach |
| Unrestricted web access | **No** | No WKWebView or SFSafariViewController anywhere; the 4 external links hand off to system Safari |
| Social media capability | **No** | No feed, no discovery, no amplification. Apple defines this as redistributing/amplifying/interacting with UGC via a feed or similar discovery method. Athletes can only fetch their own profile; coach browsing lives on the web app |
| Made for Kids | **No** | Under-13 signup is blocked |
| In-app purchases | **No** | Free; no StoreKit |
| Advertising | **No** | No ad SDKs |

**Apple's 2025 questionnaire calculated 4+ for this app** (confirmed
2026-09-19). Under the new system the capability answers drive content
descriptors and the Social Media label, but do not by themselves raise the
age band — with no mature content, the calculation lands at 4+.

**Age Suitability URL** (optional field at the end of the rating flow):
`<your-site>/age-rating.html` — a page explaining the
13+ override, the under-13 signup block, guardian consent, and coach
verification. Apple recommends supplying this specifically when you override
to a higher rating, which is our case. Leave blank only if the site is not
deployed yet; a dead link is worse than none.

**Override it to 13+.** Apple explicitly allows setting a higher minimum age
when your app's own policy requires one, and that is exactly the case here:
The Hub blocks under-13 signups. Shipping at 4+ would advertise an app to
four-year-olds that (a) refuses to let under-13s register, (b) lets adult
college coaches message minors, and (c) collects date of birth, GPA, photos,
and phone numbers — a 4+ badge on that is both misleading and a poor COPPA
signal. Set 13+ in the Edit dialog; do not go to 16+/18+, which would push the
app away from the 14–18 year olds it is built for.

## 3. Pricing and Availability

| Field | Value |
|---|---|
| Price | Free (USD 0) |
| Availability | **United States only** for v1 — the product is NCAA/US-specific (US ZIP geocoding, SAT/ACT, US colleges) |

## 4. App Privacy

**Privacy Policy URL:** `<your-site>/privacy.html`

⚠️ The website is being built separately. Page copy is in `docs/legal/`
(privacy-policy, terms-of-service, support-page, age-suitability). The URLs
must resolve over **HTTPS** before you can submit. **They are metadata and can
be changed after release without resubmitting the binary**, so the domain
decision does not gate submission.

Data collection: **Yes**. For every type below choose
**Linked to the user** = Yes, **Used for tracking** = No,
**Purpose** = App Functionality.

| Apple category | Data type | Covers |
|---|---|---|
| Contact Info | Name | Athlete, guardian, club coach names |
| Contact Info | Email Address | Account, guardian, consent emails |
| Contact Info | Phone Number | Athlete, guardian, club coach phones |
| Location | Coarse Location | Hometown (city), state, ZIP, and the ZIP-derived coordinates used for coach distance search. **Do NOT declare Physical Address** — the app has no street-address field anywhere; city/ZIP is coarse location by Apple's definition (Physical Address means a deliverable home/mailing address). Verified in schema and UI 2026-09-21. |
| User Content | Photos or Videos | Profile photo, gallery photos, highlight links |
| User Content | Other User Content | Bio, schedule, target schools, messages, reports |
| Identifiers | User ID | Supabase account UUID. ⚠️ Easy to miss — this was left unchecked on the first pass through the Data Types dialog (2026-09-21), leaving 8 types instead of 9. If the App Privacy page shows no **Identifiers** section, it's missing. |
| Usage Data | Product Interaction | Profile-view events |
| Other Data | Other Data Types | Date of birth, GPA, SAT/ACT, NCAA ID, height/weight, social handles |

Tracking: **No.** No ad SDKs, no analytics SDKs, no data broker sharing.

## 5. Version 1.2

### Screenshots
6.9" iPhone, 1320×2868 portrait. Six captured and verified in
`.screenshots/` (gitignored — regenerate any time):

| Order | File | Shows |
|---|---|---|
| 1 | `01-home.png` | Dashboard: profile strength, views/bookmarks/unread tiles |
| 2 | `02-profile-preview.png` | Public profile as coaches see it |
| 3 | `03-action-photos.png` | Action photo gallery |
| 4 | `04-ncaa-journey.png` | NCAA eligibility roadmap |
| 5 | `05-insights.png` | Recruiting insights and trends |
| 6 | `06-colleges.png` | Target school list with statuses |

No iPad set required (iPhone-only app).

### Promotional Text (166 / 170 chars)
```
Build your recruiting profile, track your NCAA eligibility journey, and see which college programs are viewing, saving, and messaging you — all in one place.
```

### Description
```
The Hub puts a high school basketball player's entire recruiting story in one place — and puts it in front of real college coaches.

BUILD A PROFILE THAT GETS NOTICED
Add your stats, academics, highlight video links, action photos, and game schedule. A profile completeness score shows exactly what to add next. When you're ready, publish — only approved college coaches can see your profile and contact info.

KNOW WHO'S WATCHING
See profile views, bookmarks, and messages from college programs as they happen. Insights show which schools are paying attention so you can focus your outreach.

OWN YOUR NCAA JOURNEY
A step-by-step eligibility tracker covers the Eligibility Center, core courses, transcripts, and amateurism certification — with plain-language summaries of the official recruiting calendars for your class year.

TARGET YOUR SCHOOLS
Keep a list of the programs you're pursuing, from first interest to committed, with notes on every conversation.

TALK TO COACHES
Read and reply to messages from approved college coaches, with block and report tools built into every conversation.

BUILT FOR FAMILIES
Parents can manage a young athlete's profile, and publishing a minor's profile requires recorded guardian consent. You can delete your account and all of your data at any time.

The Hub is free for athletes. Coach accounts are individually reviewed and approved before they can see any athlete.
```

### Keywords (91 / 100 chars)
```
aau,hoops,recruit,ncaa,athlete,college,coach,scout,highlights,eligibility,hs sports,prospect
```
Do not repeat words already in the app name or subtitle — Apple indexes those
separately.

### URLs and copyright

| Field | Value |
|---|---|
| Support URL | `<your-site>/support.html` |
| Marketing URL | `<your-site>/` (optional) |
| Version | `1.0` |
| Copyright | `© 2026 Summit Hoops` (adjust to your registered legal entity) |

### App Review Information

| Field | Value |
|---|---|
| Sign-in required | Yes |
| Demo username | `apple.review.athlete@summithoops.example` |
| Demo password | `ReviewAthlete2026!` |
| First name | Danny |
| Last name | Guillory Jr |
| Email | `dguilloryjr@msn.com` |
| Phone | `+1 636-362-4590` |

Verified 2026-09-18: that account is email-confirmed, signs in successfully,
and loads the fully populated "Jalen Brooks" demo profile.

### Review Notes
```
The Hub is a recruiting profile platform for high school basketball players, most of whom are minors. Key context for review:

1. The demo account above is a fully populated athlete profile containing fictitious data. Its email domain is intentionally non-routable; the password provided always works.

2. Minor safety: publishing a profile requires a date of birth, and any athlete under 18 must have recorded parent/guardian consent (name, email, timestamp) before the profile can be published. This is enforced in the database, not just the UI. Contact details are visible only to approved coaches who have saved the athlete.

3. Coach accounts cannot self-activate. Every coach application is manually reviewed and approved by our staff before the account can view any athlete. Coach onboarding and athlete browsing happen on our web platform; this iOS app is the athlete and family experience. A coach or admin who signs in here sees a screen directing them to the web tools.

4. User-generated content (photos, bios, messages) is moderated by our admin team using web-based tools. Every conversation has in-app Report and Block actions; reports notify all administrators and are reviewed within 24 hours.

5. Account deletion is available in-app at More → Account → Delete Account. It permanently removes the profile, photos, messages, consent records, and the login itself.

6. Athletes under 13 cannot create an account; the sign-up flow blocks them and directs them to have a parent or guardian create and manage the profile instead.
```

### Release
Choose **Manually release this version** for a first submission.

---

## Build settings already verified (no action needed)

| Item | Value |
|---|---|
| Version / Build | 1.2 / 2 |
| Deployment target | iOS 18.0 (was 26.5 — see SUBMISSION-READINESS.md §2c) |
| Devices | iPhone only, portrait |
| App icon | 1024×1024, no alpha ✓ |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` already in the build, so App Store Connect will not ask per-build |
