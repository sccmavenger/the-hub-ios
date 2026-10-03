# Parent Multi-Athlete Management & Athlete Invite/Claim Spec

**Repository:** `sccmavenger/the-hub-ios`  
**Primary client:** iOS / SwiftUI  
**Backend:** Supabase / PostgreSQL  
**Status:** Approved direction — implement in two milestones  
**Priority:** High  
**Core constraint:** Existing registered users, athlete profiles, media, recruiting data, messages, colleges, NCAA data, and current logins must not be broken or duplicated.

---

## 1. Product Goal

Support real family use cases safely:

- A parent can manage more than one athlete.
- The parent always knows which athlete is currently active.
- Switching athletes changes the entire athlete-facing app context.
- A parent can invite an athlete to gain their own login for an existing profile.
- The invited athlete claims the existing profile instead of creating a duplicate.
- Parent and athlete can both continue to manage the same athlete profile with separate credentials.

This feature must preserve all existing athlete IDs and all data already attached to them.

---

# 2. Current-State Findings

The current codebase already contains useful building blocks, but they are incomplete.

## 2.1 Existing multi-athlete retrieval

`AthleteService.fetchManagedAthletes(userId:)` already returns:

- athlete rows directly owned by the signed-in user
- athlete rows linked through `athlete_guardians`

So the app already understands the concept of a user managing multiple athlete profiles.

## 2.2 Existing per-screen athlete switchers

The following surfaces already contain their own managed-athlete selection logic:

- Home / Dashboard
- Profile
- Colleges

However, they each maintain their own selected-athlete state.

This creates a consistency problem:

> A parent can select Athlete A on Home and then navigate to another tab that independently selects Athlete B or defaults to the first athlete.

The correct model is one global selected athlete across the athlete/parent experience.

## 2.3 Athlete ownership constraint

The current `athletes` schema contains:

`user_id uuid not null unique references auth.users(id)`

This means a single auth account can directly own only one athlete row.

That is incompatible with a parent directly creating multiple athlete rows using the current `createAthlete(userId:fullName:)` method.

## 2.4 Guardian relationship exists

The database already has:

`athlete_guardians`

with:

- `athlete_id`
- `user_id`
- `relationship`

and `can_manage_athlete()` already treats an owner, linked guardian, or admin as a manager.

This should remain a major access-control primitive.

## 2.5 Invite table exists but is not implemented

The database already has:

`athlete_invites`

with:

- athlete_id
- code
- invited_email
- relationship
- redeemed_at
- redeemed_by
- expires_at
- created_at

However:

- there is no Swift invite flow
- there is no production redemption/claim RPC
- there is no special signup path for an invited athlete
- normal athlete signup automatically creates a new athlete row

Therefore the existing table is scaffolding, not a complete feature.

## 2.6 Normal athlete signup creates a new athlete automatically

The auth signup trigger `handle_new_user()` creates an athlete row whenever:

`signup_role = athlete`

Therefore an invited athlete must **not** use the normal athlete-signup path unchanged.

Otherwise an athlete who is invited to claim an existing profile would create a second athlete row and duplicate the profile.

## 2.7 Media ownership is tied to auth-user folders

Current uploads use paths such as:

- `{userId}/profile.jpg`
- `{userId}/gallery/{uuid}.jpg`

Storage write policies currently use the first path segment and `auth.uid()`.

Therefore changing `athletes.user_id` without addressing media write permissions can cause an existing manager to lose the ability to upload, replace, or delete media.

Existing media rows themselves are keyed to `athlete_id`, but the storage-path write model must be fixed before ownership transfer is allowed.

---

# 3. Migration Principle

## Do not perform a forced conversion.

Existing users remain exactly as they are until they deliberately use a new feature.

The migration must be additive:

- no bulk athlete-ID replacement
- no recreation of athlete rows
- no automatic transfer of athlete ownership
- no media relocation required for existing rows
- no forced onboarding replay
- no destructive rewrite of guardian relationships

Existing accounts must continue to work immediately after the migration.

---

# 4. Milestone 1 — Safe Multi-Athlete Parent Management

**No athlete invites or ownership transfers in this milestone.**

Goal: allow a parent to create/manage multiple athletes and make athlete selection global.

---

## 4.1 Global Managed Athlete Context

Create a single shared state object for athlete/parent mode.

Suggested name:

`ManagedAthleteContext`

Responsibilities:

- load all athletes the user can manage
- hold `selectedAthleteId`
- expose `selectedAthlete`
- switch the active athlete
- persist the most recently selected athlete
- recover safely if the previously selected athlete is no longer accessible

The context should be created at or above `AthleteTabView` and injected into all athlete-facing screens.

### Selection must drive:

- Home
- Profile
- Colleges
- Messages
- NCAA Journey
- Insights
- Profile Preview
- Bookmarks / coach saves
- Notifications that route to athlete-specific destinations
- future athlete-specific screens

Do not allow each feature screen to independently default to its first managed athlete.

---

## 4.2 Parent Athlete Switcher UX

The current toolbar-only person icon is not sufficiently obvious for multi-child families.

Recommended visible control:

> [Athlete photo] DJ Guillory  ▾

Selecting it opens:

- DJ Guillory — Class of 2030
- another managed athlete
- another managed athlete
- **+ Add Athlete**

The active athlete must always be visually clear.

When the parent switches athletes, every tab must immediately use that same athlete context.

---

## 4.3 Persist Selected Athlete

Store the selected athlete ID locally or in user settings.

Recommended behavior:

- app launch restores the previously selected athlete
- if inaccessible, fall back to first available athlete
- never crash or show stale data when the athlete list changes

---

## 4.4 Add Athlete Flow for Parents

A parent must be able to select:

**+ Add Athlete**

and create another child profile.

### Important architecture change

Do not reuse the current `createAthlete(userId:)` method unchanged.

Because `athletes.user_id` is unique, the backend needs a safe parent-created-athlete flow.

The new operation should be server-controlled, ideally an RPC such as:

`create_managed_athlete(...)`

The RPC should atomically:

1. verify caller has the parent role
2. create the new athlete row using the agreed ownership model
3. link the parent through `athlete_guardians`
4. return the new athlete
5. avoid partial state if any step fails

---

## 4.5 Ownership Model for Parent-Created Additional Athletes

Before implementation, standardize one model and use it consistently.

Recommended direction:

### Athlete profile identity and login ownership should be separable.

The athlete profile is the durable entity.

The auth users who may manage it are access relationships.

Do **not** model every manager as the athlete row's single identity.

For Milestone 1, existing records may retain their current `user_id` ownership model for backward compatibility.

New parent-created athletes should be created in a way that can later be claimed by the athlete without changing the athlete ID.

The implementation should avoid creating fake child auth accounts.

---

## 4.6 Existing Accounts

Existing parent accounts with one athlete:

- continue working
- existing athlete stays selected
- existing athlete ID is unchanged
- existing media paths are unchanged
- existing relationships remain unchanged

Existing athlete accounts:

- continue working as a one-athlete account
- global athlete context contains only that athlete
- no new UI complexity is required beyond the context infrastructure

---

## 4.7 Milestone 1 Tests

Required:

### Existing-user regression

- existing athlete account loads same athlete
- existing parent account loads same existing athlete
- existing profile photos/videos remain readable
- existing uploads still work
- colleges remain intact
- messages remain intact
- NCAA Journey remains intact
- coach bookmarks/profile views remain intact

### Parent multi-athlete

- parent can create second athlete
- parent can create third athlete
- all appear in switcher
- selecting Athlete B on Home means Profile shows Athlete B
- Colleges shows Athlete B
- NCAA Journey shows Athlete B
- Messages show Athlete B's threads
- returning to Home still shows Athlete B
- app relaunch restores Athlete B

### Isolation

- parent cannot access athletes they are not linked to
- one child's data never appears in another child's screen

---

# 5. Milestone 2 — Athlete Invite and Existing Profile Claim

Start only after Milestone 1 is stable.

Goal:

A parent can invite the athlete to create their own login and gain access to the **existing athlete profile**.

---

## 5.1 Parent Invite Flow

From the active athlete profile:

**Invite Athlete**

Parent enters:

- athlete email
- relationship/context as needed

The backend generates:

- secure random one-time token/code
- expiration
- invited email binding

The invite should reference the existing `athlete_id`.

Do not expose raw athlete access through a guessable code.

---

## 5.2 Email

Send an email such as:

> Your parent has set up your athlete profile in The Hub.  
> Create your account to access your existing profile.

The invite link must open the special claim flow.

It must **not** route through ordinary athlete signup without claim context.

---

## 5.3 Claim Signup

The invited athlete creates their own auth account.

The special signup path must prevent the normal `handle_new_user()` behavior from automatically creating a second athlete row.

Recommended mechanism:

Pass trusted invite/claim metadata and have the server distinguish:

- normal new athlete signup
- invited athlete claiming an existing athlete

Do not rely only on client logic.

---

## 5.4 Atomic Claim RPC

Create a server-side function such as:

`claim_athlete_invite(token)`

The transaction should:

1. require authenticated caller
2. validate invite exists
3. validate invite is not expired
4. validate invite is not already redeemed
5. validate signed-in email matches `invited_email` using normalized comparison
6. validate athlete still exists
7. grant the athlete account access to the existing athlete
8. preserve the parent as guardian
9. mark invite redeemed
10. write audit metadata
11. return the existing athlete ID

The same athlete ID must remain throughout the process.

---

# 6. Ownership Transfer vs Access Grant

Do not blindly change `athletes.user_id` as the first implementation step.

Several backend systems currently interpret `athletes.user_id` as the athlete owner, including:

- notifications
- blocks
- coach messaging
- media/storage assumptions
- helper functions

Before changing it, all of those references must be reviewed.

Preferred design direction:

> Make access relationships authoritative and reduce dependency on `athletes.user_id` as the sole source of truth.

If a later migration formally transfers `athletes.user_id` from parent to athlete, it must happen only after all owner-dependent systems have been made safe.

---

# 7. Media Safety Requirement

This is a release blocker for Milestone 2.

Today upload paths use auth user ID folders.

Before athlete ownership can change:

- parents who are still authorized managers must continue to upload media
- athlete must be able to upload media
- old media must remain readable
- old media should not need destructive relocation
- media authorization should resolve through `athlete_id` / management rights rather than only folder owner

Do not ship athlete claim until this is proven by tests.

---

# 8. Invite States

Recommended states:

- pending
- redeemed
- expired
- revoked

Parent should be able to:

- see pending invite
- resend
- revoke
- issue replacement invite

A redeemed invite is immutable audit history.

---

# 9. Duplicate Protection

The claim flow must explicitly prevent:

- creating a second athlete for the invited user
- claiming the same athlete twice
- two unrelated users redeeming the same invite
- using an invite for the wrong email
- duplicate guardian links
- duplicate athlete-role/profile creation

If the invited email already belongs to an account, support a signed-in redemption flow instead of forcing a second account.

---

# 10. Onboarding Integration

## New parent

After signup:

1. Welcome
2. Create first athlete
3. Offer **Add another athlete**
4. Teach athlete switcher
5. Continue to Home

## Existing parent

Do not replay mandatory onboarding.

Optional lightweight callout:

> You can now manage multiple athletes.

Actions:

- Add Athlete
- Not now

## Invited athlete

Do not show generic first-time create-profile onboarding.

Show:

> Your profile is already set up.

Then:

- preview existing profile
- confirm access
- review/edit information
- complete unfinished sections

---

# 11. Suggested Files

## iOS

New:

- `ManagedAthleteContext.swift`
- `ManagedAthleteSwitcher.swift`
- `AddManagedAthleteView.swift`
- `AthleteInviteView.swift`
- `AthleteClaimView.swift`

Modify:

- `MainTabView.swift`
- `DashboardView.swift`
- `ProfileEditView.swift`
- `CollegeListView.swift`
- athlete message/root views
- NCAA Journey root
- Insights root
- `AthleteService.swift`
- auth/signup service and routing

## Supabase

Use new migrations, not edits to old applied migrations.

Likely additions:

- multi-athlete ownership/access migration
- secure parent-create RPC
- invite creation RPC
- invite claim RPC
- invite revoke/resend support
- audit trail
- media authorization migration
- tests

---

# 12. Release Order

## Release A — Multi-Athlete Parent Management

Ship:

- global athlete context
- athlete switcher
- Add Athlete
- multiple managed profiles
- persistence
- all-tab synchronization

Do **not** ship athlete ownership claim yet.

## Release B — Athlete Invite and Claim

Only after Release A is stable.

Ship:

- invitation
- email
- dedicated claim signup
- atomic claim
- separate child credentials
- parent remains guardian
- media-safe access model

---

# 13. Release Gates

Milestone 1 cannot ship unless:

- current production accounts work unchanged
- parent can manage 2+ athletes
- active athlete is consistent across all tabs
- existing media remains intact

Milestone 2 cannot ship unless:

- normal signup cannot create a duplicate during claim
- same athlete ID survives claim
- parent retains management rights
- athlete gains own login
- existing photos/videos remain intact
- both authorized parties can manage media
- messages/blocks/notifications behave correctly
- invite is one-time, expiring, and email-bound
- automated tests cover all claim failure cases

---

# 14. Explicit Non-Goals

Do not combine this work with:

- coach-mode redesign
- NCAA rules changes
- recruiting-rule changes
- external provider integrations
- public profile redesign
- school-directory work
- profile-autofill implementation
- unrelated UI refactors

Keep this effort focused on family account structure, multi-athlete selection, and safe profile claiming.

---

# 15. Definition of Done

The work is complete when:

- one parent account can manage multiple athletes
- the parent always sees which athlete is active
- switching athlete changes every athlete-specific feature
- existing users are not forced through migration UX
- existing athlete IDs are preserved
- an athlete can be invited to claim an existing profile
- the invited athlete uses separate credentials
- the parent remains an authorized guardian
- no duplicate profile is created
- no existing media is broken
- no existing recruiting data is lost
- security/RLS tests prove unauthorized users cannot claim or manage profiles
