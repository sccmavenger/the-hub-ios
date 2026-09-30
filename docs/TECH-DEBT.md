# Technical Debt Register

**This is the living, canonical list of known debt for The Hub.** Every work
session must check this file and add anything new it discovers or defers.
When an item is fixed, mark it `done` with the date — don't delete the row;
the history is the point. `docs/SUBMISSION-READINESS.md §3` is the frozen
pre-submission snapshot; this file supersedes it as the tracker.

Severity: **S1** = security/compliance risk · **S2** = user-visible problem
· **S3** = operational/process risk · **S4** = polish.

| # | Sev | Item | Status | Added |
|---|-----|------|--------|-------|
| 1 | S3 | Email sender is `noreply@gforcedigital.net` — brand mismatch lands confirmation emails in spam. Switch to `noreply@thehubsh.net`. | **done (2026-09-24)** — thehubsh.net verified in Resend (all 4 records), Supabase SMTP sender switched, live signup verified: `"The Hub" <noreply@thehubsh.net>`, delivered | 2026-09-23 |
| 2 | S1 | Under-13 signup blocked client-side only — raw API can create an under-13 athlete account. Add DB enforcement (raise in `handle_new_user` when athlete DOB < 13 yrs). Publish gate already blocks publishing minors without consent, so exposure is pre-publish only. | **done (2026-09-23)** — migration `supabase/009-under13-signup-block.sql`, applied to prod, verified both directions (age 10 rejected, exactly-13 accepted) | 2026-09-23 |
| 3 | S1 | Admin account `dguilloryjr@msn.com` password is `P@ssw0rd` — weak, was pasted in chat, account can read all athlete data and flip prod flags. Change before launch. | open | 2026-09-18 |
| 4 | S1 | Resend API key was pasted in chat (and is in `.secrets/resend-api-key`). Rotate it, update Supabase SMTP password + the secrets file. Do this together with #1's SMTP edit to avoid two auth outages. | **done (2026-09-24)** — two scoped keys created (`the-hub-smtp` sending-only for Supabase SMTP, `the-hub-admin` full-access in `.secrets`); old keys deleted. ⚠️ Incident: the cleanup deleted ALL four pre-existing keys on the shared Resend account, including keys other projects (gforcedigital, MSF Toolkit, bookings) may have been using — their email sending breaks until re-keyed. Danny notified in chat 2026-09-24 with replacement steps. | 2026-09-20 |
| 5 | S1 | `ctguillory@mailinator.com` test athlete — mailinator inboxes are public; anyone can password-reset into the account. Change its email or delete the account before launch. | open | 2026-09-18 |
| 6 | S1 | 1-year signed media URLs stored in DB — they outlive unpublish/block/delete of *viewer* rights. Correct fix: store storage paths, sign on read. Touches every media read path. | open | 2026-09-18 |
| 7 | S1 | Guardian consent is self-attested (name+email typed in-app). Needs a real verification flow: edge function emails the guardian a confirmation link. | open | 2026-09-18 |
| 8 | S3 | No CAPTCHA on auth endpoints — email confirmation is the only friction. Supabase supports Turnstile/hCaptcha; needs client SDK work. Revisit if abuse appears. | open | 2026-09-18 |
| 9 | S3 | Athlete-ID enumeration via `record-profile-view` 404 responses. Fold into next edge-function deploy. | open | 2026-09-18 |
| 10 | S4 | Dashboard athlete-switcher can briefly show stale data on fetch failure; gallery captions save only on Return; college sheet closes on failed save. Also (2026-09-23, found during deep-link verification): on Create Account, the "I am a…" section header scrolls under the nav bar and shows through it, overlapping the title. | open | 2026-09-18 |
| 11 | S2 | Confirmation links expire after 1 hour (`mailer_otp_exp=3600`). Combined with spam-foldering (#1), real users will hit expired links. Consider 24 h. | **done (2026-09-23)** — `mailer_otp_exp` set to 86400 (24 h) via management API | 2026-09-23 |
| 12 | S3 | App Store seller shows the personal developer account name, not "Summit Hoops". Needs an Organization account (D-U-N-S) + app transfer. Plan, don't rush. | open | 2026-09-19 |
| 13 | S3 | Legal text lives in three places that must change together: `LegalView.swift`, `docs/legal/*.md`, and the Lovable site. No sync mechanism — process discipline only. | open | 2026-09-21 |
| 14 | S2 | Demo/review account emails are non-routable (`@summithoops.example`) — password reset impossible by design. If a password is lost, reset via admin API. Documented in STATUS.md. | accepted | 2026-09-23 |
| 15 | S1 | Review/demo account deletion hazard: in-app Delete Account on a seeded profile destroys it (happened 2026-09-23 to the Apple review account; rebuilt same day). Rule: only delete throwaway signups. Consider a DB guard refusing deletion of `@summithoops.example` accounts. | open | 2026-09-23 |
| 16 | S2 | Auth emails use the stock Supabase templates — unbranded, generic wording, raw `supabase.co` link, and the post-confirm redirect lands on the site homepage with no "confirmed, now sign in" message. Fix: branded confirmation/recovery templates (management API) + a `/confirmed` page on the site. Bundle with #1's sender switch. | **templates done (2026-09-23)**; **deep-link auto-login done (2026-09-23)** — signup passes `redirectTo: thehub://auth-callback`, app registers the scheme and exchanges the code via `session(from:)`; verified end-to-end on simulator (tap email link → app opens signed-in on dashboard). In app code for **build 4** — build 3 (currently with Apple) still redirects to the site. Still open: raw `supabase.co` link domain (paid custom domain, post-launch) and #17. | 2026-09-23 |
| 17 | S2 | Cross-device confirmation gap: with `redirect_to=thehub://auth-callback`, clicking the email on a desktop confirms the email but the browser can't open the app scheme — user sees a dead browser tab. Fix: universal link (`https://thehubsh.net/confirmed` + AASA file + Associated Domains entitlement) so phones open the app and desktops land on a "confirmed — open the app and sign in" page. Needs Lovable to host `/.well-known/apple-app-site-association` and the `/confirmed` page. | **done (2026-09-23)** — Lovable shipped `/confirmed` + AASA (both verified 200, correct content-type); app has `applinks:thehubsh.net` entitlement, signup redirects to the universal link, `onOpenURL` handles both link styles, `thehub://` kept as fallback. Builds clean; ships in build 4. ⚠️ On-device universal-link behavior not yet verified — Apple's CDN caches AASA; confirm on a physical device before relying on it in the review video. | 2026-09-23 |

## How to work this list

- **Adding:** one row, tersely stated, with why it matters and the shape of
  the fix. Date it.
- **Fixing:** change status to `done (YYYY-MM-DD)` and note where the fix
  landed (migration number, commit, config).
- **Reviewing:** any conversation touching auth, media, minors' data, or
  email should scan the S1 rows first.
