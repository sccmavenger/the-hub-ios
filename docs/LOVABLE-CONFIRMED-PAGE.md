# Lovable request — /confirmed page + Apple app-site-association file

Prepared 2026-09-23. Tracks TECH-DEBT #17. Paste the prompt below into
Lovable verbatim. After it ships, verify both URLs (curl, see bottom) and
tell Claude — the app's Associated Domains entitlement gets added then.

---

## Prompt for Lovable

Two additions to thehubsh.net. Keep the existing dark design system
(background #070707, cards #0F0F0F with 14px radius, accent #1387FE,
body text #F8F8F8, secondary #B7B7B7, system font stack, white logo).

**1. New page at `/confirmed`**

This is where people land after clicking the confirmation link in our
sign-up email, so it must answer "did it work, what do I do now?" at a
glance. Content, centered in a single card:

- A large green checkmark icon (use #2EC773)
- Heading: "Email confirmed"
- Body: "You're all set. Open The Hub app on your iPhone and sign in
  with your email and password."
- A smaller secondary line: "Don't have the app yet? Download The Hub
  by SummitHoops from the App Store."
- Keep it minimal — no marketing sections, no nav distractions beyond
  the standard header/footer. A confused parent should read two lines
  and know they're done.

Do not add any query-string or fragment parsing — the page is static.

**2. Host a static JSON file at exactly this path:**

`/.well-known/apple-app-site-association`

- It must be served over HTTPS with `Content-Type: application/json`
- No redirect — a direct 200 at that exact path
- No file extension (not .json)
- Exact contents:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appIDs": ["CB4AAVWWUD.com.summithoops.SummitHoops-TheHub"],
        "components": [
          { "/": "/confirmed", "comment": "email confirmation opens the app" }
        ]
      }
    ]
  }
}
```

This file is what lets iPhones open our iOS app directly when a user
taps a link to thehubsh.net/confirmed (Apple universal links). It is
harmless for normal web visitors.

---

## Verification (run after Lovable deploys)

```bash
curl -s -o /dev/null -w "%{http_code} %{content_type}\n" https://thehubsh.net/confirmed
curl -s https://thehubsh.net/.well-known/apple-app-site-association | python3 -m json.tool
# both must return 200; the second must be the JSON above, no redirect
```

## What happens after (Claude's side, app v1.3)

1. Add the Associated Domains entitlement (`applinks:thehubsh.net`).
2. Switch the signup `redirectTo` from `thehub://auth-callback` to
   `https://thehubsh.net/confirmed` — phones with the app open it
   directly (auto-login), desktops land on the friendly page instead
   of a dead thehub:// tab.
3. Keep `thehub://auth-callback` registered as a fallback.
