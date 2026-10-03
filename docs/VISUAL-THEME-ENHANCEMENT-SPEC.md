# Visual Theme Enhancement Spec

**Repository:** `sccmavenger/the-hub-ios`  
**Client:** Native SwiftUI iOS  
**Status:** Approved visual direction  
**Scope:** Visual enhancement only — not a redesign

---

## 1. Goal

Give The Hub more basketball personality and visual polish without changing the product structure, workflows, navigation, or existing information architecture.

The app should still feel like the same product that exists today, but less visually generic and less "AI-built."

The enhancement should use:

- stronger iconography
- selective real basketball photography
- subtle basketball visual texture
- better visual hierarchy
- imagery as atmosphere, not as a replacement for information

---

## 2. Current Design Must Remain the Foundation

The implementation must start from the current code and current screens.

Do **not** invent replacement layouts when an existing screen already works.

Preserve:

- current tab structure
- current screen hierarchy
- current functional cards and controls
- current typography unless a specific accessibility/legibility issue exists
- current black / charcoal visual foundation
- current Dodger-blue primary accent from `Color+Theme.swift`
- current status colors
- current recruiting logic
- current NCAA Journey content
- current college-list behavior
- current school/logo treatment
- current athlete media
- current parent/athlete/coach permissions

This is a visual layer enhancement, not a product redesign.

---

## 3. Brand Palette

Keep the existing palette from `TheHub/Utilities/Extensions/Color+Theme.swift`.

Primary existing colors include:

- `hubBackground` — near-black
- `hubSurface` — dark card surface
- `hubSurfaceElevated`
- `hubPrimary` / `hubBlue` — Dodger-blue accent
- white / muted-gray text
- existing success / warning / error colors

Do not introduce a competing new primary brand color.

---

## 4. Photography Direction

Use **real basketball photography**, not AI-generated imagery.

Preferred photography subjects:

- empty basketball courts
- hoops and nets
- basketballs on hardwood
- gym interiors
- court lines / floor details
- arena lighting
- scoreboard / gym atmosphere where licensing permits

Avoid using recognizable people unless licensing and publicity/model rights are clearly appropriate for production use.

Athlete-specific people imagery should primarily come from the athlete's own uploaded photos and videos.

### Licensing

Only use imagery whose production use is clearly permitted.

For free stock sources, verify license terms before adding files to the app.

Do not hotlink remote stock images in production. Download approved production assets, retain source/license metadata, and include any attribution required by the source.

---

## 5. Imagery Usage Rules

Imagery should be secondary to the user's data.

Good uses:

- screen hero/header backgrounds
- feature-entry cards
- empty states
- onboarding/welcome surfaces
- NCAA Journey visual context
- subtle basketball texture behind otherwise empty regions

Avoid:

- putting important body text directly over busy photos
- using images behind dense statistics
- adding decorative photography to every card
- making screens visually noisy
- replacing existing data visualizations with photos
- using imagery where existing product-specific content already carries meaning

Every photo background must have sufficient dark overlay/contrast for text readability.

---

## 6. Home / Dashboard Direction

Keep the current Dashboard structure and existing data.

Enhance it with:

### Athlete header / hero
Introduce a restrained basketball-environment image as visual atmosphere around the top athlete context area.

The athlete's own profile photo remains the athlete identity.

Do not replace athlete data with generic photography.

### Metrics
Keep existing metrics such as:

- Profile Strength
- Profile Views
- Bookmarks / coach saves
- Unread messages

Use clearer icons to reinforce meaning.

Suggested SF Symbols should be evaluated first before custom icon assets.

Examples:

- profile views → eye
- bookmarks → bookmark
- unread messages → envelope / message
- profile strength → gauge / chart / progress treatment

### Quick actions
Existing actions can gain stronger iconography and, selectively, image-backed treatment where it improves the screen.

Do not change the underlying actions or destinations.

---

## 7. Colleges Screen Direction

This screen has existing domain-specific treatment that should not be disrupted.

### Preserve
Do **not** replace or redesign existing school/college logos or school identity treatment.

Do not use generic stock basketball imagery inside the existing Target Schools rows/cards.

The existing college-specific UI should remain authoritative.

### Enhance
Visual enhancement is appropriate for:

- Recruiting Status
- page header / section atmosphere
- discovery / explore entry points
- empty states

The Recruiting Status area can use a clearer status icon.

Approved direction from review:

- recruiting status iconography is desirable
- hourglass/timing iconography is useful where it accurately represents waiting/timing state

Do not change recruiting status semantics.

---

## 8. NCAA Journey Direction

This is a strong candidate for basketball imagery because the screen is information-heavy and benefits from additional personality.

Use selective basketball photography in:

- top/header area
- major journey/roadmap introduction
- one supporting visual feature area if appropriate

Use icons to make milestones more scannable.

Possible icon concepts:

- journey / roadmap → map
- academic readiness → book
- eligibility / completion → checkmark seal
- recruiting communication → message
- timing / upcoming milestone → hourglass or clock
- NCAA profile / registration → person/document icon

All rules, disclaimers, source provenance, and eligibility language must remain unchanged.

Do not make NCAA guidance appear more authoritative than it is.

---

## 9. Icons

Prefer **SF Symbols** first because the app is native SwiftUI.

Use icons consistently for:

- metrics
- section headers
- status cards
- key quick actions
- timeline milestones
- empty states
- onboarding explanations

Do not add icons merely for decoration.

Each icon must reinforce the adjacent action or concept.

Keep icon treatment visually consistent across the app.

---

## 10. Screens That Should Stay Primarily Functional

Some surfaces should remain cleaner and more utilitarian.

Examples:

- forms
- profile-edit fields
- account/security settings
- consent flows
- legal screens
- admin screens
- messaging compose areas

Do not add decorative background images behind form fields or sensitive/account information.

---

## 11. Athlete Profile

The athlete's own media should provide most of the visual personality here.

Prioritize:

- athlete profile photo
- athlete gallery
- athlete video thumbnails
- sport/recruiting data

Do not place generic stock imagery in a way that could be mistaken for the athlete or their team.

---

## 12. Accessibility and Readability

All enhancements must preserve accessibility.

Requirements:

- sufficient text contrast
- support Dynamic Type where currently supported
- icons need accessibility labels when not accompanied by clear text
- imagery must not contain essential information
- dark overlays must keep overlaid text readable
- VoiceOver behavior must not regress
- tap targets must remain at least current size

---

## 13. Performance

Do not materially slow the app for decorative imagery.

Production assets should be:

- resized for intended display
- compressed appropriately
- cached
- bundled when appropriate rather than unnecessarily fetched every launch

Do not ship oversized original stock-photo files.

---

## 14. Existing Media Must Not Be Touched

This visual enhancement must not:

- delete athlete photos
- rewrite athlete storage paths
- replace profile photos
- modify video records
- migrate existing athlete media
- change media permissions

Existing athlete media is out of scope except for visual presentation improvements that do not mutate stored content.

---

## 15. Mockup Decisions Already Approved

The reviewed concept established the following direction:

### Approved
- more icons on the athlete/home experience
- basketball photography as visual atmosphere
- recruiting status icon treatment
- timing/hourglass icon where semantically accurate
- imagery on NCAA Journey
- imagery used as secondary background texture
- current black/blue foundation retained

### Do not change
- existing school/college logo treatment
- existing Target Schools identity presentation
- existing college-specific imagery/code
- current screen functionality
- current navigation

---

## 16. Suggested Implementation Order

### Phase A — Icon pass
1. Audit current SF Symbols
2. Add meaningful icons to high-value status and metric surfaces
3. Standardize size/alignment treatment

### Phase B — Home visual enhancement
4. Add restrained basketball hero/background treatment
5. Refine quick-action visual presentation
6. Validate text contrast and performance

### Phase C — NCAA Journey
7. Add top visual treatment
8. Add milestone icons
9. Keep all existing rule text and logic unchanged

### Phase D — Colleges
10. Enhance Recruiting Status iconography
11. Add visual atmosphere only outside Target Schools rows
12. Do not modify school logos

### Phase E — Empty/onboarding states
13. Add basketball-specific visual context where screens otherwise feel empty
14. Reuse the same small approved image set rather than introducing many unrelated styles

---

## 17. Regression Requirements

Verify after implementation:

- navigation unchanged
- all existing buttons work
- college rows/logos unchanged
- athlete profile media unchanged
- NCAA Journey calculations unchanged
- recruiting-rule status unchanged
- messages unchanged
- parent/athlete roles unchanged
- coach experience unaffected unless a shared component intentionally receives the same icon polish
- no meaningful launch or scrolling performance regression

---

## 18. Non-Goals

Do not use this effort to:

- redesign navigation
- restructure screens
- change copy broadly
- alter onboarding logic
- alter profile setup logic
- alter multi-athlete architecture
- alter athlete invite/claim logic
- change recruiting rules
- change school data
- change coach workflows
- add external integrations
- add AI-generated imagery

---

## 19. Definition of Done

The enhancement is complete when:

- The Hub still looks unmistakably like the current product.
- Basketball context is visible immediately on the most important athlete-facing screens.
- Key status/action areas have meaningful icons.
- Home feels more visual without sacrificing data clarity.
- NCAA Journey feels less clinical while preserving all factual/rule content.
- Colleges keeps its current school identity treatment.
- Generic stock imagery never competes with athlete or school-specific content.
- No existing user data, media, navigation, or functionality is changed.
