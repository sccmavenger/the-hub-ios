# Integrations Research — NCAA Eligibility Center, Hudl, Instagram/TikTok

**Researched:** 2026-09-12 (three deep-dive research passes; full source lists at bottom of each section)

---

## 1. NCAA Eligibility Center ("Clearinghouse")

### Hard verdict on APIs
**No public API, no verification program, no partner channel for apps — period.**
- College compliance offices verify status via the closed, MFA-protected EC Portal (member institutions only).
- High schools use the HS Portal (CEEB-code login) for transcripts and course lists.
- The only third-party door is the approved e-transcript vendor list (Parchment, National Student Clearinghouse/SPEEDE, SCOIR, Naviance…) — document delivery, not eligibility data.
- Closest precedent: **Honest Game** (Hudl's "Official Academic Partner", NJCAA's official clearinghouse 2026) has **no NCAA data access either** — they independently mirror the rules. Nobody has an NCAA integration; not NCSA, not SportsRecruits.
- ⚠️ If the app ever sells prospect info **to college programs** for a fee, that requires NCAA **ECAG approval** (recruiting/scouting service rules).

### What we CANNOT do
Look up whether a kid has an NCAA ID, verify a claimed ID, or pull certification status. The ID is self-reported everywhere in the industry.

### Facts to build with (2026-27)
- **Account types:** free **Profile Page** (any age; now REQUIRED for D3 enrollees too, new 2026-27); paid **Certification Account** $120 US / $180 intl (required for D1/D2); fee waivers exist. Unpaid cert accounts are deleted after 30 days. Profile Pages "transition" in place — never create a duplicate account.
- **NCAA ID:** 10-digit number, issued immediately with ANY account type incl. the free one. Shown top-right of the student dashboard.
- **Recommended timing:** free Profile Page in 9th grade → transition to Certification Account in 10th if D1/D2 is the goal.
- **D1:** 16 core courses, min 2.3 core GPA, 10/7 rule locks grades before 7th semester; 2.0–2.299 = academic redshirt.
- **D2:** 16 core courses, min 2.2 core GPA; partial qualifier below.
- **Test scores/sliding scale: ELIMINATED (Jan 2023).** GPA-only. Do not ship a sliding-scale calculator.
- **Amateurism:** cert requested from April 1 before enrollment; NIL-era rules churning in 2026 — link out, don't hardcode.
- **Key URLs:** register: `web3.ncaa.org/ecwr3/register/PROFILE` (free) / `.../register/CERTIFICATION?accountSubType=FULL` (paid); dashboard: `web3.ncaa.org/ecwr3/dashboard`; free guide PDF: `fs.ncaa.org/Docs/eligibility_center/Student_Resources/CBSA.pdf`.

### Branding rules
"NCAA" referentially in copy = standard practice (all competitors do it). Never in app name/icon/logo. Add "not affiliated with or endorsed by the NCAA." Deep-linking to their URLs is unrestricted. Never guarantee scholarships or charge contingency fees in copy (athlete-side amateurism risk).

### Product implication — the "NCAA Readiness" feature set (no API needed)
1. NCAA ID capture with 10-digit validation + "Don't have one? Register free" deep links (grade-aware: Profile Page vs Certification copy).
2. Persistent signals: readiness card on dashboard/insights, "NCAA ID on file" pill on the coach-facing profile (web already does the pill).
3. Grade-by-grade checklist (9th–12th) mirrored from the free NCAA guide.
4. D1/D2 core-course + GPA requirement explainers (already partially in the Colleges compliance card).
5. Existing web-app `complianceChecks` (DOB on file, guardian consent, guardian linked, NCAA ID) ported into the profile editor.

---

## 2. Hudl

### Hard verdict
**No public API, no "Sign in with Hudl," no import-my-highlights — impossible without a negotiated deal.** Their data APIs (Wyscout, StatsBomb/IQ) are pro-sport, contract-only. Nobody in recruiting has API access; SportsRecruits/NCSA paste URLs like we do.

### What DOES work (verified by direct HTTP probes)
- **Embed URL format `hudl.com/embed/video/{v}/{userId}/{videoId}` serves `frame-ancestors *`** → renders in WKWebView. This is sanctioned — Hudl's own athlete guides encourage embedding reels on recruiting sites.
- Watch pages (`/video/...`) send `X-Frame-Options: Deny` — must transform pasted URLs to embed form. Short links (`/v/{code}`) need a redirect-follow first.
- No oEmbed. Metadata (thumbnail, title, direct MP4) is in og: tags — but scraping is a ToS gray zone; **iframe embed only**; never hot-link the MP4.
- Private highlights can't embed — athletes must set them public.

### Product implication
Upgrade video rows to inline players: normalize pasted Hudl URLs → embed form, render in WKWebView (same for YouTube/Vimeo embeds). Add-time validation with a "make your Hudl video public" hint on failure. Hudl remains the dominant HS film platform in 2026; no better-API alternative exists (Balltime acquired by Hudl; GameChanger/BallerTV have no public APIs).

---

## 3. Instagram & TikTok

### Hard verdicts
- **Instagram Basic Display API: dead** (Dec 2024). The replacement (Instagram API with Instagram Login) works **only for Business/Creator accounts** and needs Meta business verification + App Review — and converting a teen's account to Professional forces it public. **Do not build OAuth import.**
- **Instagram oEmbed: tokenless since June 2026** for public posts — but Teen Accounts (all under-18s since 2024/25) are **private by default**, so embeds fail for most of our users.
- **TikTok oEmbed: open, no key — but "private accounts and underage accounts cannot be embedded"** (explicit TikTok policy). Display API/Login Kit exist (audit required) but return little for private under-16 accounts.
- **TikTok US regulatory status: resolved** (Jan 2026 USDS joint venture; platform stable).
- **Minors reality:** aggregating and redistributing teens' social content to adult strangers is exactly the pattern regulators are attacking (Meta's Aug 2026 multi-state settlement, TikTok's GDPR fines). Link-outs carry none of that liability.
- **Industry norm:** every recruiting platform stores handles and links out. On3 (the most social-driven) abandoned its follower-count model in July 2026.

### Deep links (the right integration)
- Instagram: `instagram://user?username={handle}` (add `instagram` to `LSApplicationQueriesSchemes`) with `https://instagram.com/{handle}` fallback.
- TikTok: use `https://www.tiktok.com/@{handle}` (universal link routes to app automatically).

### Current app state (audited)
Handles are captured in the profile editor and stored — but the iOS coach-facing profile (PublicProfileView) doesn't display or link them at all (the web app shows tappable links). That's a gap to fix regardless.

---

## Recommendation matrix

| Integration | Verdict | Effort | Priority |
|---|---|---|---|
| NCAA Readiness hub (ID capture+validation, register nudges, grade checklist, requirement explainers, readiness signals) | Build — no API needed, mirrors public content | Medium | High — core product ask |
| NCAA ID verification | Impossible (no API) | — | — |
| Hudl inline embed player + URL normalization | Build — sanctioned embed path | Small-Medium | High |
| "Sign in with Hudl" / import highlights | Impossible without negotiated deal | — | — |
| Social deep links on profiles (IG scheme + TikTok universal link) | Build | Small | High — fixes existing gap |
| Social oEmbed of selected public posts | Possible, degrades for private/minor accounts | Medium | Low — optional garnish |
| Social OAuth import | Don't build (minors risk, Meta review burden, industry anti-pattern) | — | Never |
