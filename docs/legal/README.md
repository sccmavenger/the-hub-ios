# Website content for App Store submission

Apple requires two publicly reachable URLs before you can submit:

| Field | Required? | Page |
|---|---|---|
| Privacy Policy URL | **Yes** | `privacy-policy.md` |
| Support URL | **Yes** | `support-page.md` |
| Marketing URL | No | any landing page |
| Age Suitability URL | No, but recommended | `age-suitability.md` |

The Age Suitability page is worth publishing because we override Apple's
calculated 4+ rating up to 13+, and Apple asks for an explanation when you
raise a rating.

## Build these pages in whatever tool you prefer

The markdown files here are the source copy — paste them in. There is no
hosting requirement beyond the URLs resolving over **HTTPS** (Apple rejects
plain http for the privacy policy).

## Keep the app and the website in sync

`privacy-policy.md` and `terms-of-service.md` mirror the text compiled into
the app at `TheHub/Views/Legal/LegalView.swift`, which users agree to at
sign-up. If you change the policy, change both — users and Apple should see
the same terms in the app and on the web. The other two pages are web-only.

## The domain does not gate submission

Nothing is locked to a domain:

- The **app binary contains no site URL** (verified) — only the contact
  address `info@summithoops.net` is compiled in.
- **App Store Connect metadata URLs can be changed after release without
  resubmitting the binary.**
- The Supabase `site_url` (where the email-confirmation link redirects) is
  server config, changeable in seconds. It currently points at a placeholder
  and should be updated once the real site is live.

So you can submit on any working URL and move to the final domain later.

## Contact address

`info@summithoops.net` — confirmed live on the Summit Hoops Google Workspace.
Single address for privacy, security, support, and general questions. It
appears in all four documents and in the app's legal screens.
