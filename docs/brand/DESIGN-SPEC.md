# The Hub — design spec for the website

Paste this into Lovable (or any builder) so the site matches the iOS app.
Every value here was read out of the shipping app's source, not approximated.

The goal: someone who taps a link in the app, or downloads the app after
seeing the site, should never wonder whether they're in the right place.

---

## 1. Color palette

The app is **dark-mode only** — it forces `.preferredColorScheme(.dark)` and
has no light variant. **The website must be dark too.** A white site linked
from a black app is the single biggest "is this fake?" signal.

| Token | Hex | Use |
|---|---|---|
| Background | `#070707` | Page background. Near-black, not pure black. |
| Surface | `#0F0F0F` | Cards, panels, sections |
| Surface elevated | `#292929` | Chips, badges, inputs, hover states |
| **Primary / brand** | **`#1387FE`** | Buttons, links, headings, active states |
| Text primary | `#F8F8F8` | Body and headings (not pure white) |
| Text secondary | `#B7B7B7` | Captions, helper text, metadata |
| Border | `rgba(255,255,255,0.20)` | Dividers, input outlines |
| Success | `#2EC773` | Confirmations, "Visible to coaches" |
| Warning | `#FFA600` | Cautions, incomplete states |
| Error | `#EE3533` | Errors, destructive actions |

Tailwind config (Lovable uses Tailwind):

```js
colors: {
  bg:        '#070707',
  surface:   '#0F0F0F',
  elevated:  '#292929',
  primary:   '#1387FE',
  ink:       '#F8F8F8',
  muted:     '#B7B7B7',
  success:   '#2EC773',
  warning:   '#FFA600',
  danger:    '#EE3533',
  brandNavy: '#262658',
}
```

### ⚠️ Resolve this before building

The **logo is navy `#262658`**, but the **app's accent is dodger blue
`#1387FE`**. They don't match. The app works around it by placing the navy
logo on a white card — which looks like a patch, and would look worse on a
website.

**Recommendation: use the white logo on dark backgrounds** (provided in this
folder) and let `#1387FE` be the only accent color on the site. Keep navy
out of the palette entirely. That way the logo reads as intentional
monochrome branding instead of a third competing blue.

Do **not** put the navy logo on a white card on the website. It's the one
thing that will look stitched together.

---

## 2. Logo files

In `docs/brand/`:

| File | Use |
|---|---|
| `thehub-logo-white.png` | **Primary for the website.** White on transparent — sits directly on `#070707` or `#0F0F0F`. |
| `thehub-logo-offwhite.png` | `#F8F8F8` variant, matches body text exactly. Slightly softer. |
| `thehub-logo-navy.png` | Original `#262658`. Only for light/print contexts. |

All are 1024×460 with transparency. The lockup reads **THE HUB** in an italic
condensed athletic face, with a rule line and **POWERED BY SUMMIT HOOPS**
beneath. Keep the whole lockup together — don't separate the tagline, and
don't retype it in a different font.

Clear space: at least the height of the "T" on all sides. Minimum width
about 180px before the tagline stops being legible.

---

## 3. Typography

The app uses the **iOS system font (SF Pro)** throughout. On the web the
closest honest match is the system stack — it renders as SF Pro on Apple
devices, which is exactly where most visitors will be:

```css
font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
             Helvetica, Arial, sans-serif;
```

Do not import Inter, Poppins, Montserrat, or similar. They're close enough to
look like a near-miss, which reads worse than a plain match.

Scale, mapped from the app's actual usage (most-used first):

| Role | Web size | Weight | App equivalent |
|---|---|---|---|
| Caption / meta | 12–13px | regular | `.caption` (most used) |
| Body | 15–16px | regular | `.subheadline` |
| Section heading | 17px | semibold | `.headline` — **often in `#1387FE`** |
| Card title | 20px | bold | `.title3` |
| Page title | 22–28px | bold | `.title2` |
| Hero | 34–40px | bold | `.title` / large nav title |

Line height ~1.4 body, ~1.2 headings.

**A signature detail:** in the app, section headings inside cards are
**blue (`#1387FE`), not white** — "Academics", "About", "Action Photos",
"Upcoming Schedule". Reproduce that on the site and it will feel like the
same product immediately.

---

## 4. Shape and spacing

Corner radii, by frequency in the app:

| Radius | Use |
|---|---|
| **14px** | Cards and panels — the dominant radius, use this by default |
| 10px | Inputs, small containers, inline banners |
| 12px | Primary buttons |
| 8px | Thumbnails, small badges |
| Pill (`999px`) | Status chips, tags |

Spacing uses a 4px grid. Most common values: **16px** (card padding),
**8px** (tight stacks), **12px**, **24px** (section gaps), **32px** (page
margins on wide layouts).

Cards: `#0F0F0F` background, 14px radius, 16px padding, usually **no border
and no shadow** — separation comes from the background contrast, not from
strokes. Don't add drop shadows; the app has none.

---

## 5. Components to mirror

**Primary button** — full-width in the app: `#1387FE` background, white text,
semibold, 12px radius, ~50px tall. On hover, darken slightly rather than
adding a glow.

**Status chip** — pill, `#1387FE` background, white bold 12px text, ~8px
horizontal / 3px vertical padding. Used for Offered, Contacted, Visiting.

**Stat tile** — `#0F0F0F` card, large bold number (~28px) over a `#B7B7B7`
caption. Used for profile views, bookmarks, GPA/SAT/ACT.

**Input** — `#0F0F0F` background, 1px `rgba(255,255,255,0.20)` border, 10px
radius, white text, and a small `#B7B7B7` caption label **above** the field
(not a placeholder inside it).

**Progress bar** — thin rounded track, `#292929` background, `#1387FE` fill.

---

## 6. Voice and content

The app talks to a high-school athlete and their parent — direct, practical,
never hypey. "Get seen by college coaches," not "Unlock your athletic
destiny." Short sentences. No exclamation marks.

Real product language to reuse: *profile strength*, *published*, *visible to
coaches*, *target schools*, *NCAA journey*, *recruiting timeline*,
*guardian consent*, *approved coaches*.

Trust matters more than polish for this audience — parents are handing over a
minor's photos and contact details. Lead with the safeguards: coaches are
manually approved, profiles are private until published, publishing a minor's
profile requires guardian consent, and accounts can be deleted at any time.
Those facts are true and they're the strongest thing the site can say.

Contact everywhere: **info@summithoops.net**.

---

## 7. Pages the site needs

Required for App Store submission — these two must resolve over **HTTPS**:

- **Privacy Policy** → copy in `docs/legal/privacy-policy.md`
- **Support** → copy in `docs/legal/support-page.md`

Strongly recommended:

- **Terms of Service** → `docs/legal/terms-of-service.md`
- **Age Suitability** → `docs/legal/age-suitability.md` (explains the 13+
  rating; Apple asks for this when a rating is overridden upward)

A landing page is optional for Apple but sensible for the Marketing URL.

Keep the legal pages' text **identical to the markdown** — the same wording is
compiled into the app and users agree to it at sign-up. Style it freely,
but don't rewrite the words.

---

## 8. Screenshots you can use

`.screenshots/` has six real 1284×2778 captures of the live app: dashboard,
public profile, photo gallery, NCAA journey, insights, and target schools.
Using genuine screenshots rather than generic mockups is the fastest way to
make the site feel real. Set them on `#070707` so the device bezel isn't
needed.

---

## 9. Quick prompt for Lovable

> Build a dark-mode marketing site for "The Hub," a basketball recruiting app
> for high school athletes. Background `#070707`, cards `#0F0F0F` with 14px
> radius and 16px padding, no shadows. Accent `#1387FE` for buttons, links,
> and section headings inside cards. Body text `#F8F8F8`, secondary text
> `#B7B7B7`. Borders `rgba(255,255,255,0.20)`. Use the system font stack
> (-apple-system first), not a Google font. Status chips are blue pills with
> white bold text. Primary buttons are full-width blue with 12px radius.
> Use the provided white logo on the dark background — never on a white card.
> Tone is direct and practical, aimed at student-athletes and their parents;
> emphasize that coaches are manually verified, profiles stay private until
> published, and guardian consent is required for minors. Pages: landing,
> support, privacy policy, terms, age suitability.
