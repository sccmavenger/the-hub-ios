# Profile Setup 2.0 — Autofill, Fast Creation, and Inline Validation

**Repository:** `sccmavenger/the-hub-ios`  
**Primary client:** iOS / SwiftUI  
**Backend:** Supabase / PostgreSQL  
**Status:** Approved for implementation  
**Purpose:** Reduce athlete profile setup time without weakening validation, privacy, consent, or existing profile/media behavior.

---

## 1. Product Goal

Make first-time athlete profile creation fast enough for real-world registration moments such as camps, tournaments, showcases, and team onboarding.

A new athlete or parent should be able to create a usable profile in a small number of taps, then complete the richer recruiting profile later.

The implementation must:

- Reuse information The Hub already knows.
- Autofill blank fields where safe.
- Replace avoidable typing with pickers/search.
- Provide inline validation before Save.
- Preserve the existing save-time validation as the final safety net.
- Avoid overwriting user-edited values.
- Preserve all existing athlete photos, videos, schedules, contacts, coach access rules, consent rules, and NCAA/recruiting behavior.

---

## 2. Current-State Findings

The current app already has useful foundations:

- Signup captures:
  - full name
  - email
  - role
  - athlete date of birth
- `ProfileEditViewModel.save()` already validates:
  - full name
  - state
  - ZIP
  - graduation year
  - height
  - weight
  - GPA
  - SAT
  - ACT
  - email
  - phone
  - bio length
- `ProfileValidation.swift` is the canonical save-time validation layer.
- `HubTextField` already supports:
  - keyboard type
  - `UITextContentType`
  - capitalization
  - max length
- Minor privacy/contact behavior already exists:
  - minor athlete phone is not collected
  - minor athlete contact information is withheld from coaches
  - guardian consent is required before publishing a minor
- Create mode currently opens all profile sections, which makes profile creation feel longer than necessary.

This work should enhance those foundations rather than replace them.

---

## 3. Success Criteria

A first-time athlete profile should be creatable with the following minimum information:

1. Athlete name
2. Date of birth
3. High school
4. Graduation year
5. Position
6. Basketball gender/category
7. Guardian information when required for a minor

Whenever The Hub already knows one of those values, it should be prefilled.

After the quick profile is created, the athlete should land in the normal profile experience where remaining sections can be completed progressively.

---

# 4. Functional Requirements

## 4.1 Reuse Existing Signup Data

### Athlete-created account

When an athlete creates their own account:

- Full Name should already be populated in the athlete profile.
- Date of Birth should already be populated from signup.
- Athlete Email should default from the authenticated account email if the contact field is blank.

Do not ask for these values again unless the athlete chooses to edit them.

### Parent-created / parent-managed athlete

When a parent creates or manages an athlete:

Autofill blank fields from the signed-in parent account:

- Guardian Name
- Guardian Email
- Consent Name
- Consent Email

If the parent's name/email are already stored on another managed athlete, they may be reused.

### Overwrite rule

**Never overwrite a nonblank value.**

Autofill may only populate a field when:

- the field is blank, and
- the source is trusted account/guardian data.

---

## 4.2 Reuse Guardian Contact Across Siblings

If the signed-in parent manages more than one athlete and a previously managed athlete has guardian contact information:

Offer:

> Use your saved guardian contact?

If accepted, populate blank values:

- Guardian Name
- Guardian Email
- Guardian Phone

Do not silently copy a phone number without user confirmation.

Consent fields may reuse the same guardian name/email when blank.

---

## 4.3 National High School Search

Replace the free-text High School field with a searchable school picker backed by a normalized national directory.

### Data sources

Use public U.S. school datasets as the canonical source:

- NCES Common Core of Data (public schools)
- NCES Private School Universe Survey (private schools)

### New table

Recommended table:

`school_directory`

Suggested fields:

- `id uuid primary key`
- `nces_id text null`
- `source text not null`
- `school_name text not null`
- `normalized_name text not null`
- `city text null`
- `state text not null`
- `zip_code text null`
- `school_type text null`
- `active boolean not null default true`
- `created_at timestamptz not null default now()`
- `updated_at timestamptz not null default now()`

Recommended indexes:

- normalized school name
- state
- ZIP
- trigram/search index for school name

### Athlete table

Add:

`high_school_id uuid null references school_directory(id)`

Keep the existing `high_school` text field for display/backward compatibility.

### Search behavior

As the user types, return school suggestions based on:

- school name
- city
- state
- ZIP

Each result should show enough context to disambiguate schools, for example:

> St. Charles High School  
> St. Charles, MO 63301

### Selection behavior

Selecting a school should populate:

- `highSchool`
- `highSchoolId`
- `state`
- `zipCode`

The school city may be suggested for Hometown, but must not be forced.

Prompt:

> Use St. Charles as your hometown?

User can accept, reject, or enter something else.

---

## 4.4 Replace Free Text with Pickers Where Appropriate

### Position

Replace the primary position free-text field with a picker.

Recommended initial options:

- PG
- SG
- SF
- PF
- C

Keep room for a later multi-position enhancement, but do not expand scope in this phase.

### State

Use a U.S. state picker instead of free text.

Store the two-letter code.

### Graduation Year

Use a year picker rather than requiring number entry.

Recommended options should be generated dynamically from the current year, using the same allowed range enforced by `ProfileValidation`.

---

## 4.5 Improve iOS Native Autofill

Use `textContentType` consistently.

Apply where appropriate:

- Full Name → `.name`
- Athlete Email → `.emailAddress`
- Athlete Phone → `.telephoneNumber` (adult only)
- Guardian Name → `.name`
- Guardian Email → `.emailAddress`
- Guardian Phone → `.telephoneNumber`
- Club Coach Name → `.name`
- Club Coach Phone → `.telephoneNumber`
- ZIP → `.postalCode`

Do not remove the existing field-level privacy rules.

---

## 4.6 Add Contact Picker for Guardian and Club Coach

Add a privacy-safe system contact picker.

Buttons:

- **Choose Guardian from Contacts**
- **Choose Club Coach from Contacts**

Selecting a contact may populate:

### Guardian

- Guardian Name
- Guardian Email
- Guardian Phone

### Club Coach

- Club Coach Name
- Club Coach Phone

If multiple emails or phone numbers exist, allow the user to choose.

Do not request unrestricted bulk Contacts access if the native picker can satisfy the requirement.

Suggested component:

`HubContactPicker.swift`

---

## 4.7 Inline Validation

Keep all current save-time validation.

Add inline field feedback so users do not discover errors only after pressing Save.

### Validation timing

Do not show red errors immediately on untouched fields.

Validate when:

- the user leaves a field, or
- the field has been edited and contains a complete-enough value to validate.

### Fields

At minimum:

- Full Name
- Athlete Email
- Guardian Email
- Athlete Phone
- Guardian Phone
- Club Coach Phone
- ZIP
- Graduation Year
- Height
- Weight
- GPA
- SAT
- ACT

### Examples

Invalid email:

> Enter a valid email address.

Invalid phone:

> Enter a valid phone number.

Invalid GPA:

> GPA must be between 0 and 5.

Invalid SAT:

> SAT score must be between 400 and 1600.

Invalid ACT:

> ACT score must be between 1 and 36.

### Component enhancement

Extend `HubTextField` to optionally support:

- `errorText: String?`
- valid/invalid visual state
- optional formatter
- optional validation callback/state

Do not duplicate validation rules in views. Reuse `ProfileValidation` or add field-level helpers to it.

---

## 4.8 Phone Normalization

Allow users to type common U.S. phone formats.

Examples:

- `3145551212`
- `314-555-1212`
- `(314) 555-1212`

Display normalized U.S. numbers as:

`(314) 555-1212`

Storage should be consistent.

Do not reject an otherwise valid phone number simply because punctuation differs.

If international phone support is not intentionally implemented in this phase, document the U.S.-focused behavior rather than pretending broader support exists.

---

# 5. Quick Profile Creation Flow

## 5.1 Current problem

Create mode currently expands every profile section:

`expandedSections = Set(SectionKey.allCases)`

This makes optional profile enrichment feel mandatory.

## 5.2 New create-mode behavior

Replace the current all-sections-open create experience with a focused Quick Profile flow.

### Step 1 — Athlete Basics

Show only:

- Full Name
- Date of Birth
- High School
- Graduation Year
- Position
- Basketball gender/category

Most known values should already be prefilled.

### Step 2 — Guardian / Consent if Minor

For minors:

- Guardian Name
- Guardian Email
- Guardian Phone
- Consent acknowledgment

Name/email should be prefilled where available.

For adult athletes, skip this step.

### Primary action

Use:

**Create My Profile**

Do not require:

- photo
- height
- weight
- GPA
- SAT
- ACT
- NCAA ID
- social handles
- bio
- gallery
- videos
- game schedule
- club coach

to complete initial creation.

## 5.3 After profile creation

Navigate to the existing profile/editor experience.

Show profile completion clearly, for example:

> 6 of 12 sections complete

or a comparable completion indicator.

Encourage progressive completion rather than blocking profile creation.

---

# 6. Files to Modify

## Existing iOS files

### `TheHub/ViewModels/Profile/ProfileEditViewModel.swift`

Add:

- autofill initialization
- current-account email prefill
- parent/guardian prefill
- sibling guardian-contact reuse support
- high-school selection state
- field-level validation state/helpers
- phone normalization before save

Preserve:

- existing save-time validation
- geocoding behavior
- minor phone suppression
- guardian consent rules
- media behavior

### `TheHub/Views/Profile/ProfileEditView.swift`

Change:

- create mode to Quick Profile
- high-school free text → searchable picker
- position → picker
- state → picker
- graduation year → picker
- add native text content types
- add contact-picker buttons
- add inline validation messages

Preserve:

- all existing edit-mode sections
- completion chips
- media sections
- ICS schedule import
- destructive-action alerts
- publish behavior

### `TheHub/Utilities/ProfileValidation.swift`

Refactor/add field-level helpers without weakening the aggregate validation methods.

Recommended helpers:

- `validateEmail(_:) -> String?`
- `validatePhone(_:) -> String?`
- `validateZip(_:) -> String?`
- `validateGradYear(_:) -> String?`
- `validateGPA(_:) -> String?`
- `validateSAT(_:) -> String?`
- `validateACT(_:) -> String?`

Existing `validateAthlete` and `validateContact` should call the same helpers so there is only one rule source.

### `TheHub/Components/HubFormFields.swift`

Enhance `HubTextField` with optional inline error support and validation presentation.

Do not break existing callers.

---

## Suggested new iOS files

- `TheHub/Services/SchoolDirectoryService.swift`
- `TheHub/Views/Profile/SchoolSearchView.swift`
- `TheHub/Components/HubContactPicker.swift`
- `TheHub/Utilities/PhoneFormatter.swift`

---

## Supabase

Add one migration for:

- `school_directory`
- indexes/search support
- optional `athletes.high_school_id`
- read policy suitable for authenticated users

Add a repeatable import script for NCES datasets rather than embedding the entire school dataset in migration SQL.

Suggested script:

`scripts/import-school-directory.py`

The importer must be idempotent.

---

# 7. Data/Privacy Guardrails

1. Never overwrite user-entered profile values with autofill.
2. Do not expose a minor's athlete email or phone to coaches.
3. Do not reintroduce minor phone collection.
4. Guardian consent remains required for published minor profiles.
5. Contact picker use must be user-initiated.
6. Do not store unrelated contacts.
7. School-directory data is public institutional data only.
8. No change may break existing athlete media.
9. No migration may destroy existing free-text school values.
10. Existing profiles must remain editable without forcing a school-directory match.
11. If a school is not found, allow manual school entry as a fallback.

---

# 8. Migration / Backward Compatibility

Existing athletes may have:

- `high_school` text
- no `high_school_id`

Do not force-convert them.

Recommended behavior:

- Existing `high_school` continues to display.
- If an athlete edits school, the search picker is offered.
- Selecting a directory school sets both `high_school_id` and `high_school`.
- Manual fallback leaves `high_school_id = null`.

No destructive backfill is required.

---

# 9. Testing Requirements

## Unit tests

Add tests for:

### Validation

- valid/invalid emails
- valid/invalid phones
- ZIP
- GPA
- SAT
- ACT
- graduation year

### Phone formatting

- 10 raw digits
- already formatted
- invalid short input
- punctuation variants

### Autofill

- blank fields receive defaults
- nonblank fields are never overwritten
- minor/adult behavior remains correct
- parent info fills guardian + consent fields
- sibling phone reuse requires confirmation

## UI tests

At minimum:

1. Athlete signup → profile:
   - name is present
   - DOB is present
   - athlete email is prefilled

2. Parent creates minor athlete:
   - guardian name/email prefilled
   - consent name/email prefilled

3. School search:
   - search results appear
   - selecting a school fills school/state/ZIP

4. Invalid email:
   - inline error appears before Save
   - Save still prevents invalid data

5. Contact picker:
   - selected guardian fills intended fields only

6. Quick Profile:
   - first-time create does not expose all 12 sections
   - profile can be created without optional enrichment

7. Existing athlete:
   - edit mode remains unchanged except for improved controls
   - photos/videos remain intact

## Regression tests

Must verify:

- guardian consent enforcement
- minor phone suppression
- coach-safe contact redaction
- profile publish/unpublish
- coach discovery
- athlete media
- NCAA Journey
- recruiting rules enforcement
- schedule/ICS import

---

# 10. Recommended Build Order

Implement in this order:

### Phase A — Low-risk, immediate UX wins

1. Reuse signup/account data
2. Parent/guardian autofill
3. iOS content types
4. inline validation
5. phone normalization
6. position/state/grad-year pickers

### Phase B — Quick Profile

7. first-run Quick Profile flow
8. post-create completion guidance

### Phase C — School Directory

9. Supabase school directory schema
10. NCES import script
11. school search service/UI
12. state/ZIP autofill
13. optional hometown suggestion

### Phase D — Contacts

14. guardian contact picker
15. club-coach contact picker
16. sibling guardian-contact reuse

---

# 11. Definition of Done

This feature is complete when:

- Athlete signup information is not unnecessarily re-entered.
- Parent-managed athletes inherit blank guardian/consent information from the parent account.
- High school is searchable from a national directory.
- School selection fills state and ZIP.
- Position, state, and graduation year are picker-driven.
- iOS autofill works on supported fields.
- Guardian/club-coach contacts can be selected from Contacts.
- Validation appears inline.
- Save-time validation remains authoritative.
- Phone formatting is normalized.
- New athlete creation is a short Quick Profile flow.
- Optional recruiting details can be completed later.
- Existing profiles continue to work.
- Existing photos, videos, schedules, contacts, coach permissions, guardian consent, NCAA Journey, and recruiting-rule enforcement remain intact.

---

# 12. Explicit Non-Goals

Do not include in this phase:

- Prep Hoops integration
- Hudl integration
- SportsEngine integration
- Exposure Events integration
- transcript import
- GPA verification
- SAT/ACT verification
- automatic NCAA ID lookup
- AI-generated profile bio
- public profile-link redesign
- coach workflow changes unrelated to profile setup

Keep this change focused on **faster, safer athlete profile creation**.
