# Coach Mode Phase 2 — Final Decisions and Claude Code Implementation Handoff

**Target application:** The Hub iOS  
**Target repository:** `sccmavenger/the-hub-ios`  
**Suggested repository location when separately authorized:** `docs/COACH-MODE-PHASE2-DECISIONS.md`  
**Status:** Final product decision record, with an executable Phase 2A–2F plan  
**Source:** “Competitor Analysis Research,” conversation `6abc93cc-5e70-83ea-9819-97ccaec4d7d2`.

## 1. Mandate, authority, and scope

This document preserves all 30 finalized Coach Mode Phase 2 decisions from the source conversation. The user's later correction replaces the original answer to Decision #24: **admin is an exclusive account role and cannot coexist with coach, athlete, or parent roles. There must be no Admin / Coach Mode switcher.**

The implementation details, acceptance checks, and Phase 2A–2F work packages below operationalize those decisions. The retrieved conversation contained the complete decision log and its correction, but did not contain the earlier detailed phase descriptions; the six-phase breakdown here is derived from the finalized dependencies. References to existing repository behavior are historical investigation pointers, not a claim that the current checkout has been inspected.

### Instruction to Claude Code

> Treat this document as the authoritative product specification for Coach Mode Phase 2, superseding conflicting assumptions in older gap analyses. Inspect the current repository, then implement Phases 2A–2F end to end. Deliver the full native Coach Workspace: Home/Dashboard, Discover, Recruiting Board, Messages, Program, and Notifications. Do not stop after backend hardening, migrations, RPCs, or data-layer work. Each phase must build and pass its relevant tests before proceeding. If a genuine external dependency prevents completion, report the precise blocker and remaining work; do not label Phase 2 complete.

**Phase 2 is not complete merely because the security/backend work is complete. The user-facing Coach Workspace must be built, connected to real authorized data, and verified.**

The core recruiting journey is:

**Choose verified program → discover athlete → evaluate profile/events → save to shared board → collaborate → message within the applicable rules → receive useful notifications.**

This handoff is a standalone document. Its creation does not authorize editing, committing, or pushing to GitHub. When the owner separately asks Claude Code to implement it, work within that authorization and the repository's applicable instructions. Production deployment, account changes, and App Store submission are separate operational actions and must follow the owner's authorization.

### Included and deferred scope

- **Included:** secure athlete media, consistent authorization, exclusive admin identity, verified program context, server-side Discover, shared program Recruiting Board, separate private notes, personal program-scoped saved searches and real alerts, compliant messaging, full coach dashboard, Program/staff experience, and native Notifications for coach and athlete/guardian accounts.
- **Deferred to Event Mode:** the standalone “Games Near Me” scouting workflow, event-centric ZIP/radius browsing, and related calendar/export experience. Upcoming athlete events and playing-date Discover filters remain in Phase 2.
- **Deferred:** CSV export. Do not add it as an alternate route around safe-field restrictions.
- **Excluded:** Admin / Coach switching and arbitrary free-form messages labeled “non-recruiting” as a compliance bypass.

## 2. Finalized decisions — all 30

### Decision #1 — Fix athlete-media exposure before expanding features

**Question:** Should feature expansion pause until the athlete-media exposure is fixed?

**Final answer:** Yes. Security remediation comes first.

**Acceptance:** Demonstrate that unauthenticated and otherwise unauthorized callers cannot retrieve protected athlete media or obtain new signed access. Do not enable the expanded Coach Workspace against the vulnerable access paths.

### Decision #2 — Store object paths and sign access at authorization time

**Question:** Should media receive a small policy patch or a proper architectural fix?

**Final answer:** Fix the architecture. New uploads store canonical storage object paths; authorized reads receive short-lived signed access.

**Acceptance:** Storage paths are not treated as permission. Signing checks the current caller, athlete visibility, block state, and applicable coach/program authorization. Expired or unauthorized requests fail. Persist neither long-lived signed URLs nor public storage URLs as the new protected-media model.

### Decision #3 — Preserve existing media during migration

**Question:** Must the migration be backward-compatible with zero intentional breakage?

**Final answer:** Yes. Preserve existing media; keep legacy references usable through the authorized migration path, verify storage objects before backfill, delete nothing, and leave existing external video URLs alone.

**Acceptance:** Inventory and reconcile every legacy reference. Do not guess an object path from an unverified URL. Report missing or ambiguous objects without discarding their original references. Existing authorized playback works before and after migration. Backward compatibility must not preserve a public-access vulnerability; see the media migration requirements below.

### Decision #4 — Blocking removes all affected Coach Mode access

**Question:** Should an athlete/guardian block affect all access rather than only messaging?

**Final answer:** Yes. The blocked coach loses Discover visibility, profile, media, events, contacts, messaging, activity signals, and related access to that athlete.

**Acceptance:** Enforce the block at every server boundary and remove stale visible data from the client. Direct identifiers, old links, shared board entries, and background alerts cannot bypass it. Apply the block's recorded actor/program scope consistently; see Decision #26.

### Decision #5 — Suspended or inactive coaches lose recruiting access

**Question:** Should suspension or inactivity revoke athlete/recruiting access immediately?

**Final answer:** Yes. Deny Discover, messaging, board access, saved searches, athlete data, and other recruiting reads. Narrow cleanup/deletion of the coach's own stale records may remain available. Reinstatement restores only currently authorized access.

**Acceptance:** Recheck active status server-side, including on existing sessions and background jobs. Cleanup must not disclose athlete data or permit deletion of shared program records without authorization. Reinstatement cannot override blocks, unpublished profiles, expired memberships, or program restrictions.

### Decision #6 — Route athlete-interest notifications through verified membership

**Question:** Should only current verified staff of the matching verified program receive athlete-interest notifications?

**Final answer:** Yes. Do not use free-text `coach_requests.college` for authorization, program identity, or notification routing.

**Acceptance:** Recipients have current active verified membership in the matching verified program and retain permission to see the athlete. Pending, inactive, suspended, former, mismatched, or blocked staff are excluded. An old application claim cannot establish access.

### Decision #7 — Record only authorized profile views

**Question:** Should profile-view events require permission to view the athlete?

**Final answer:** Yes. Apply publication, blocks, active verified coach status, and all other read rules. Attribute a coach view to verified program membership, not a legacy application claim.

**Acceptance:** Rejected profile reads create no athlete-facing view or interest signal. View-recording endpoints cannot be used independently to fabricate unauthorized views or program attribution. Authorized multi-program views use the selected, validated program context.

### Decision #8 — Tighten internal helpers and broad lookup RPCs

**Question:** Should `SECURITY DEFINER` helpers and broad lookup RPCs be hardened before Discover ships?

**Final answer:** Yes. Expose purpose-built, authorized client RPCs. Internal authorization helpers must not be generally callable.

**Acceptance:** Audit function grants, execution privileges, row-level security, views, and bypass paths. Harden privileged functions, including their search path and caller checks. Direct table access or an old RPC must not reproduce the unrestricted data that the new endpoints withhold.

### Decision #9 — Validate coach recipients for athlete/guardian messaging

**Question:** May athletes/guardians start or send a coach conversation only to a currently active verified coach?

**Final answer:** Yes. Arbitrary user UUIDs cannot masquerade as coach recipients.

**Acceptance:** Validate recipient role, active status, verified program membership/context, relationship permissions, and blocks on conversation creation and every send. Existing threads do not grandfather an invalid recipient into eligibility.

### Decision #10 — Message previews are a user setting, default OFF

**Question:** Should message previews be configurable?

**Final answer:** Yes. Add **Show Message Previews** to Settings, default OFF. Keep message content primarily in the messaging system rather than unnecessarily duplicating it into notification records.

**Acceptance:** New and unset preferences resolve to OFF. With previews disabled, notification surfaces and delivery payloads do not expose message text. Opting in controls only that user's previews; it does not grant broader access to the underlying message.

### Decision #11 — The Recruiting Board is shared and program-owned

**Question:** Should board ownership belong to a coach or to the verified program?

**Final answer:** The verified program owns the shared board. Its current authorized verified staff collaborate on that board. Truly private coach notes remain separate.

**Acceptance:** One authorized program context yields a consistent shared prospect workflow across staff, including stages, tags, assignments, and activity. Another program cannot read or change it. Private notes are absent from shared payloads, shared activity, and other staff members' reads. Suspension, departure, and blocks revoke applicable access.

### Decision #12 — Discover search runs server-side only

**Question:** Should the app download athlete rows and filter locally?

**Final answer:** No. The backend performs authorization, block checks, safe-column projection, radius and event filtering, pagination, and program-context validation.

**Acceptance:** The client never receives the unrestricted athlete table. Search results, result counts, filter metadata, pagination, and detail endpoints apply equivalent permissions. A modified client cannot retrieve withheld columns or broaden sport/gender/program scope.

### Decision #13 — Saved searches generate real alerts, default OFF

**Question:** Should saved searches generate alerts or merely remember filters?

**Final answer:** Generate real alerts, with alerts default OFF. Coaches explicitly enable them. A periodic backend process finds new matches without repeatedly notifying about old results.

**Acceptance:** Persist alert preferences and delivery/match checkpoints. Retry and repeated job execution do not duplicate an already-notified match. Recheck coach/program eligibility and athlete access at evaluation and delivery. Specify and test initialization and edited-filter behavior so old results are not unexpectedly replayed.

### Decision #14 — Pre-window exceptions use controlled templates

**Question:** May coaches label arbitrary free-form text “non-recruiting” before the normal contact window?

**Final answer:** No. Any narrow non-recruiting exception must use controlled, rules-approved templates.

**Acceptance:** The backend validates template identity, approved content, allowed parameters, and applicability. Arbitrary text, altered template content, or a client-supplied exception flag cannot bypass the recruiting rules. If no approved template applies, no exception is offered.

### Decision #15 — Enforce known prohibited messages after launch gates pass

**Question:** Should clearly prohibited coach messages be hard-blocked when Coach Messages launches?

**Final answer:** Yes. Turn enforcement ON only after the Phase 2 messaging fixes and tests pass. Retain the admin kill switch. Keep `needs_review` distinct from a known `hard_block`.

**Acceptance:** Preflight and final server-side send checks use consistent program/rule context; direct inserts and changed conditions cannot bypass final enforcement. A `hard_block` creates no delivered message. `needs_review` retains its distinct result and follows the approved review policy; do not silently reinterpret it as allowed or hard-blocked. Verify the kill switch and durable rejected-attempt audit before enabling enforcement.

### Decision #16 — Multi-program coaches explicitly choose a program

**Question:** Should coaches choose which verified program they represent?

**Final answer:** Yes. Provide a **Program Switcher**. Discover, board, messaging, compliance, alerts, and other program-dependent coach actions carry a `program_id` verified against the signed-in coach's current membership.

**Acceptance:** Show the selected program clearly. A last-used selection may be restored only while valid; do not silently select the most recently verified program as a substitute for clear user context. Switching refreshes data and prevents old requests, drafts, caches, or notifications from acting under the wrong program. No available membership produces an explicit unavailable-access state.

### Decision #17 — Native Notifications Center for coaches and athletes/guardians

**Question:** Should native notifications be included in Phase 2?

**Final answer:** Yes, for both groups. Use a bell and unread badge, not an additional bottom tab. Include read/unread state, mark-all-read, and native destinations.

**Acceptance:** Both experiences can list their own notifications, open authorized destinations, mark individual items read, and mark all read. Badge counts update correctly. One account cannot read or change another account's notifications.

### Decision #18 — Defer standalone Games Near Me to Event Mode

**Question:** Should the full Games Near Me experience ship in Phase 2?

**Final answer:** No. Preserve event awareness: upcoming events on athlete detail and Discover filters for **playing this weekend**, **next 7 days**, and **next 30 days**. Defer standalone event/location scouting to Event Mode.

**Acceptance:** An authorized coach can use those athlete-oriented event windows, inspect upcoming events, and save an eligible athlete. Event results follow the same athlete permissions. Do not expand this phase into a standalone tournament browser or calendar-export project.

### Decision #19 — Ship the core Discover filter set with safe fields

**Question:** Which filters belong in Discover v1?

**Final answer:** Name, position, graduation year, ZIP/radius, minimum height, minimum GPA, and playing-date window. City/state may accompany location search. The selected program supplies sport/gender context automatically.

**Acceptance:** Filters compose correctly and paginate on the server. Do not expose DOB, guardian data, SAT/ACT, NCAA ID, or precise coordinates through Discover or its athlete-evaluation payloads. Use a documented safe-field allowlist, clear units, and defined date/time-zone semantics. Radius calculations must not require sending exact athlete coordinates to the client.

### Decision #20 — Defer CSV export

**Question:** Should CSV export ship in Phase 2?

**Final answer:** No. Finish the shared recruiting workflow first. A later export feature requires a strict safe-field allowlist, program authorization, and auditing.

**Acceptance:** Phase 2 adds no coach CSV export. Existing export paths, if present, are checked for authorization bypasses during the security audit; deferral is not permission to leave a known leak active.

### Decision #21 — Enforce tag and note limits in the UI and database

**Question:** Should limits exist only in the interface?

**Final answer:** No. Enforce a maximum of **10 tags** and **2,000 characters of notes** in both the UI and backend/database.

**Acceptance:** Test valid boundaries and over-limit writes, including direct calls. Apply the note limit to the relevant shared and private recruiting-note fields without conflating their visibility. Define character counting consistently. Preserve and report legacy over-limit values during migration; never silently truncate them.

### Decision #22 — Show active verified program staff

**Question:** May verified staff see other verified members of their program?

**Final answer:** Yes. The Program experience shows staff name, title, and recruiting role, without unnecessary personal contact information. Suspended or inactive staff disappear from the active list.

**Acceptance:** The roster reflects the selected verified program and current eligible membership. Cross-program reads fail. Removing someone from the active roster must also reflect actual authorization revocation, not just hide their name.

### Decision #23 — App Store review readiness is a release gate

**Question:** Should review configuration be revisited before release?

**Final answer:** Yes. Review age-rating answers, privacy disclosures, social/messaging capabilities, reviewer notes, and functioning demo accounts immediately before submission.

**Acceptance:** Release evidence covers Coach Discover, adult-to-minor messaging, user-generated profiles, blocking/reporting, and notifications. Verify fresh reviewer credentials and coach-approval instructions. Use the then-current official submission requirements; this document does not assert a specific legal conclusion or age-rating answer. Do not place credentials in this document or source control.

### Decision #24 — Admin is an exclusive role; mixed-role accounts are invalid

**Question:** What happens if one user is both an admin and a verified coach?

**Final answer — corrected by the user:** This must never be a valid state. Admins use dedicated accounts with no coach, athlete, or parent role. **Do not build an Admin / Coach Mode switcher.**

**Acceptance:** Enforce a backend invariant across every role, membership, approval, provisioning, and import path: an admin cannot simultaneously hold any of those roles or an active coach identity. Coach approval rejects admin accounts; granting admin rejects accounts with another role. Test both operation orders and concurrent writes. Audit existing mixed-role records and report conflicts without silently deleting or converting accounts. The historical `admin > coach > athlete > parent` routing precedence may remain as defense in depth, but it neither legitimizes mixed roles nor replaces server enforcement. Do not impose exclusivity among non-admin roles unless another existing requirement requires it.

### Decision #25 — Saving to the program board unlocks the contact card

**Question:** Should coach access to an athlete's contact information require a board save?

**Final answer:** Yes. Saving the athlete to the **program** board unlocks the contact card for currently verified, authorized staff of that program, subject to publication and block rules.

**Acceptance:** Before save, display **“Save to Recruiting Board to unlock contact information”**. Enforce this gate server-side; hiding a card while downloading its contents is insufficient. After a valid save, return only the approved contact-card fields through a separately authorized path. Do not use contact unlock to expose the sensitive fields excluded in Decision #19 or to bypass communication rules.

### Decision #26 — Blocks remove board entries from affected active workflows

**Question:** What happens to a saved athlete when the athlete/guardian blocks the coach/program?

**Final answer:** Remove that athlete from all coach-visible active workflows within the affected block scope immediately. Profile, contact information, media, board card, and related notifications become unavailable. Retain only the minimum backend audit information required for integrity. **Unblocking must not silently restore old recruiting access; an eligible program must explicitly re-add the athlete.**

**Acceptance:** Apply the restriction to reads, counts, assignments, activity, searches, cached cards, and notification destinations. An individual-coach block must not be bypassed through the shared program board. A program-scoped block applies to all affected program staff. The source decisions do not establish that one coach block automatically blocks every colleague; preserve the recorded block scope rather than inventing that policy. Persist tombstones/revocation state or an equivalent mechanism so old entries and notifications do not reactivate on unblock. If legacy scope is ambiguous, fail closed for affected access and report it for resolution.

### Decision #27 — Saved searches are personal and program-scoped

**Question:** Should saved searches be shared like the board?

**Final answer:** No. A saved search belongs to its coach and is scoped to that coach's selected verified program. Alert preferences are personal; saved prospects join the shared program board.

**Acceptance:** Other program staff cannot read or change a coach's saved searches or alert settings. Validate both owner and program context on CRUD and background evaluation. Switching programs cannot expose the previous program's search results or reuse its alerts under a different identity.

### Decision #28 — Notifications use native typed destinations

**Question:** Should notifications keep using web strings such as `/messages` or `/coaches/messages`?

**Final answer:** No. Use typed native destinations for athlete profile, thread, saved search, board athlete, and program. Recheck authorization every time a destination is opened. Map legacy strings during transition where possible.

**Acceptance:** Typed payloads carry only necessary identifiers and program context. Unknown or stale legacy links fail gracefully; they never become permission grants. A blocked athlete, invalid membership, removed board entry, or unavailable thread yields an appropriate unavailable state without showing stale private content.

### Decision #29 — Durable audit for rejected recruiting-message attempts

**Question:** Is durable compliance history required before enforcement goes live?

**Final answer:** Yes. A rejected message must remain blocked while its denied attempt is recorded durably. An audit insert that rolls back with the rejected send, or a best-effort server log alone, does not satisfy this requirement.

**Acceptance:** Demonstrate a rollback/rejection with a durable, access-restricted audit event remaining afterward. Record sufficient actor, program, rule/version, outcome, and time metadata without unnecessarily retaining message bodies. Validate retries and correlation. Audit storage failure must not turn a prohibited send into a delivered message. Preserve final database enforcement while using a transaction-safe durable recording path.

### Decision #30 — Migrate board ownership without destructive rewrite

**Question:** Should the coach-owned board become program-owned through an in-place destructive rewrite?

**Final answer:** No. Add program ownership backward-compatibly. Map existing rows only where a coach's verified program can be determined unambiguously. Report unresolved rows, preserve data during verification, and retire old ownership assumptions only after tests pass.

**Acceptance:** Reconcile all source rows and handle collisions when multiple coaches saved the same athlete for the same program. Preserve notes, tags, history, and provenance; never promote private notes into shared program visibility. Unresolved or ambiguous rows remain preserved but cannot grant access. Replace the historical `(coach_user_id, athlete_id)` ownership/uniqueness assumption with a verified program-owned design after successful backfill validation.

## 3. Required user-facing Coach Workspace

The existing minimal `Home + More` experience is not the final deliverable. Use the app's native design and navigation conventions to provide all the following functional surfaces. The exact tab composition may follow the repository's established pattern; Notifications must remain bell-based rather than a new bottom tab.

| Surface | Required behavior | Completion evidence |
| --- | --- | --- |
| **Home / Dashboard** | Clearly selected verified program; program-board counts by stage; unread messages; new saved-search matches; recent recruiting activity; quick actions; notification bell/badge. | Real data for the current authorized context; each card/action opens its correct destination; switching programs refreshes counts and activity. |
| **Discover** | Server-backed filters, stable pagination, saved searches, opt-in alerts, safe athlete detail, upcoming events, and save-to-board action. | A coach can complete a filtered search and save an eligible athlete; withheld fields never arrive in client payloads. |
| **Recruiting Board** | Shared program prospects, stages, tags, assignments, activity, shared workflow, and separately protected private coach notes. | Two authorized staff accounts see shared updates; private notes remain author-only; contact access follows the board-save gate. |
| **Messages** | Coach inbox and thread experience; validated recipients; visible representing program; recruiting-rule preflight; approved pre-window templates; final enforcement; block/report handling. | An allowed exchange succeeds and a prohibited attempt is blocked and audited; changing membership or blocks invalidates stale permissions. |
| **Program** | Program Switcher, verified program details, and active verified staff with name, title, and recruiting role. | A multi-program coach can deliberately change context; ineligible programs/staff disappear from available access. |
| **Notifications** | Bell/unread badge for coach and athlete/guardian users; list; read/unread; mark-all-read; typed destinations; preview settings. | Both user experiences work, counts reconcile, and stale or unauthorized destinations fail safely. |

For each surface, implement usable loading, empty, error, retry, and revoked-access states. Show meaningful empty states for a new program instead of placeholder totals. Respect accessibility labels, readable text, and the application's normal interaction patterns.

Dashboard aggregates are authorized data too: counts and activity must not reveal blocked or unpublished athletes, private coach notes, or another program's work. Notifications and message badges must link to the context their counts represent. Document whether a badge is global or program-specific and preserve that meaning during program switching.

## 4. Cross-cutting security and migration requirements

### 4.1 One consistent authorization model

For each coach recruiting operation, validate the authenticated identity, active coach status, current verified membership, verified program, supplied program context, athlete visibility, and applicable block scope. Add resource-specific rules such as board membership for contact access and recruiting policy for sends. Derive the actor from the authenticated session, never from a client-supplied user ID.

Apply equivalent rules to direct reads/writes, RPCs, storage/signing, profile-view recording, aggregations, notifications, scheduled jobs, and realtime subscriptions where used. Use column allowlists and minimal payloads. Row-level authorization alone does not prevent sensitive-column exposure. Keep service-role credentials and signing authority off the client.

Internal helpers must have deliberate grants and safe execution context. Privileged entry points must validate authorization even if called outside the app. Legitimate admin operations remain in the separate administrative identity and must not provide an alternate Coach Mode.

Revoke access on blocks, suspension, membership removal, and publication changes at the server. Clear sensitive cached views and stop or reauthorize subscriptions on corresponding client state changes. Short-lived signed bearer URLs and already-downloaded media have practical revocation limits: choose and document a short expiration, avoid durable cached signed links, and test the residual window. Do not claim previously downloaded bytes can be recalled. If the storage design cannot meet the intended revocation requirement, use an authorization-checking delivery path for protected media and make the remaining limit explicit before release.

### 4.2 Media migration runbook

1. Inventory legacy URLs, storage-backed assets, external video URLs, missing objects, bucket policies, signing endpoints, and affected readers/writers. Capture reconciliation totals and a recoverable baseline.
2. Add the canonical object-path representation without dropping original references. Identify storage ownership and verify each object's existence before backfill.
3. Update new uploads to persist paths. Add authorized read/signing behavior and a compatibility resolver for verified legacy storage references. Treat unrelated external video URLs as external and leave them unchanged.
4. Test authorized playback across existing supported media surfaces and deny unauthorized public/storage access. Keep protected storage private; route legacy access through the new authorized mechanism.
5. Coordinate reader/writer rollout and storage-policy cutover. If an old client depends on insecure public URLs, plan an update/compatibility transition that preserves assets and legitimate user playback without leaving the exposure enabled. Do not promise unchanged insecure URLs will continue working anonymously.
6. Reconcile mapped, unmapped, missing, and ambiguous references. Retain originals and objects. Retire vulnerable paths only after authorized playback and access-denial checks pass. Rollback must not reintroduce public exposure.

### 4.3 Program-board migration runbook

1. Inventory coach-owned rows, verified memberships, duplicate prospect relationships, shared/private note semantics, tag/note limits, and unresolved historical owners.
2. Add program ownership and the required policies/indexes in an additive migration. Separate private-note storage/authorization before making any previously coach-owned data shared.
3. Backfill only deterministic, verified program mappings. Never use `coach_requests.college`, a guessed institution, or the most recently verified membership to resolve ambiguous multi-program rows.
4. Produce a reconciliation report: total legacy rows, mapped rows, rows merged or linked with provenance, unresolved rows, collisions, and limit violations. Preserve unresolved records outside active access-granting workflows.
5. Reconcile multiple coach entries for one program/athlete without discarding notes, tags, stages, assignments, or history. Where source stages conflict, retain source values and provenance and resolve deliberately; do not silently let the last row win. Preserve over-limit source data while requiring valid values for new/edited records.
6. Verify staff sharing, private-note isolation, block behavior, contact unlock, program isolation, and rerun safety. Validate the final program-owned uniqueness rule and old-client/write behavior before retiring legacy ownership assumptions.

All migrations must be rerunnable or have a clearly tested resume strategy, use bounded transactions/backfills appropriate to the data size, and retain a recovery path. Include dry-run/reconciliation output and rollback instructions. Avoid destructive cleanup as part of Phase 2. Disabling a feature is preferable to restoring an insecure access policy during rollback.

### 4.4 Admin identity migration and invariants

Audit all authoritative role and membership sources, not just the UI's primary-role property. Detect dedicated admin accounts that also have coach/athlete/parent roles or active coach memberships. Record conflicts for owner resolution without deleting profiles, stripping roles silently, or guessing which identity to retain. Deny affected Coach Mode access while conflicts remain.

Enforce exclusivity atomically at the database/backend boundary so parallel approvals cannot create a mixed-role state. Cover self-service, approval, admin assignment, migrations, imports, and service-side provisioning. Existing role caches/claims must not keep granting contradictory permissions. The application must present the dedicated admin experience to a valid admin account without exposing a coach switcher.

### 4.5 Messaging rules and durable audit

Inspect the repository's existing rule engine, templates, preflight endpoint, send enforcement, and admin switch. Do not invent NCAA contact windows or treat this decision record as a rulebook. Use the project's approved, current rules and official governing sources for rule updates; record versions and effective dates. Keep unsupported or uncertain evaluations distinct through `needs_review` and its approved handling policy.

Final enforcement must run at send time, including direct database/RPC attempts. Preflight is explanatory UI, not an authorization token. Revalidate program identity, participants, membership, blocks, and policy after preflight. Denied messages must neither persist as delivered messages nor trigger delivery notifications.

Implement a durable audit design whose denied-attempt record survives the rejected message transaction. Explain transaction boundaries and failure behavior in implementation notes. A separate durable server-side recording flow may be used, but must not weaken the database's final guard or create an unaudited bypass through another supported send path. Store minimal necessary metadata, restrict audit readers, and define retention according to existing project policy. Test database rejection, audit persistence, retries, and audit-sink failure.

The admin kill switch controls the recruiting-rule enforcement mode only as designed; it must not disable identity verification, blocks, privacy rules, or admin exclusivity. Log switch changes and verify both switch states. Enforcement remains gated until the messaging and audit acceptance tests pass, and must be ON for the launched Coach Messages experience.

### 4.6 Alerts, notifications, and privacy

Saved-search evaluation must use the same authorized query semantics as Discover. Use per-owner/per-program checkpoints and idempotent match/delivery handling. Turning alerts off, losing membership, suspension, or a new block prevents subsequent unauthorized delivery. Recheck delayed work rather than trusting eligibility captured when it was queued.

Notifications contain minimal typed destinations and contextual metadata. Apply access checks to listings and opening destinations, including legacy notifications. Remove or redact affected active notifications when access is revoked. Message previews default OFF across supported in-app and external delivery surfaces. Existing notification bodies must not leak message content merely because the new UI hides previews.

## 5. Phase 2A–2F implementation plan

Begin with a repository inspection and baseline build/test run. Identify current schemas, migration order, RLS/storage policies, RPCs, role sources, verification/suspension states, block scope, coach navigation, notification delivery, and rule enforcement. Reuse sound existing functionality. Record deviations from the historical pointers below. Do not weaken a finalized decision to match an old implementation.

For each phase: implement its backend and native UI scope, run relevant tests, build the affected app target, record evidence, and resolve failures before proceeding. Use separate, reviewable changes in the authorized development workflow. A phase checkpoint is not permission to abandon later phases.

### Phase 2A — Security foundation and safe media transition

**Primary decisions:** #1–#9, #24; shared enforcement foundations for #4–#7 and #26.

**Deliver:** a documented authorization matrix; tightened storage, RPC, and table access; path-based media and compatible authorized reads; authorization-aware profile views and interest routing; validated coach recipients; active-status revocation; and atomic admin exclusivity. Audit existing conflicts and migration exceptions without data loss.

**Exit gate:** unauthorized media/data access tests pass; legitimate historical media still plays through the secure path; privileged helper exposure is addressed; recipient spoofing and unauthorized profile-view recording fail; suspension and admin-role conflict tests pass. Complete the security remediation before enabling expanded recruiting features.

### Phase 2B — Verified program context and shared recruiting data

**Primary decisions:** #11, #16, #21, #22, #25–#27, #30.

**Deliver:** native Program Switcher and Program/staff view; validated program context through services and operations; additive board migration; shared stages/tags/assignments/activity model; isolated private notes; tag/note limits; contact-card gate; block/removal/tombstone handling; and owner/program-scoped saved-search storage. Establish real navigation entry points for the remaining workspace surfaces.

**Exit gate:** all legacy board rows are accounted for, including unresolved rows; no private note becomes shared; two same-program coaches can collaborate; another program is denied; program switching does not reuse stale context; limits, contact gating, blocks, and no automatic restoration after unblock are verified.

### Phase 2C — Discover, athlete evaluation, and saved-search alerts

**Primary decisions:** #12, #13, #18–#20, #25, #27.

**Deliver:** native Discover list/filter experience; purpose-built server search with safe fields and stable pagination; athlete detail and upcoming events; save-to-board/contact unlock; personal saved-search CRUD; opt-in real periodic alerts with deduplication. Build the alert production path now; complete its native notification presentation in Phase 2E.

**Exit gate:** all specified core filters work, including radius and playing windows; program sport/gender context is enforced; sensitive fields are absent from responses; blocked/unpublished athletes are absent from results and counts; authorized save/contact flow works; repeated alert jobs do not re-notify old matches. CSV and standalone Games Near Me remain deferred.

### Phase 2D — Complete shared Recruiting Board and Home/Dashboard

**Primary decisions:** #11, #16, #21, #25, #26, plus the explicit full-workspace mandate.

**Deliver:** finished native board workflow for stage changes, tags, assignments, shared activity, and separate private notes. Build the full dashboard with selected program, stage counts, unread messages, new saved-search matches, recent activity, quick actions, and bell entry point. Connect existing message/notification data where available; complete new messaging and notifications integration in Phase 2E.

**Exit gate:** dashboard and board use real authorized data with functional destinations and no placeholder completion claims. Shared updates reach eligible staff; program switches update all relevant views; blocked athletes do not leak through cards, counts, or activity; private notes stay private. Track any dependencies on Phase 2E explicitly.

### Phase 2E — Compliant Messages and native Notifications

**Primary decisions:** #9, #10, #13–#17, #28, #29; complete dashboard/alert integration.

**Deliver:** coach inbox/threads/composer; visible verified representing program; eligible athlete/guardian initiation and replies; preflight and final enforcement; approved pre-window templates; block/report handling; durable denied-attempt audit; kill switch behavior; native notification centers for coach and athlete/guardian accounts; typed destinations; preview setting; badges/read state/mark-all-read. Connect dashboard unread counts, new-match notifications, and native destinations end to end.

**Exit gate:** allowed messaging succeeds; known prohibited messages fail and leave durable audit records; forged exceptions, stale preflight, invalid recipients, wrong programs, and blocked relationships cannot send. `needs_review` remains distinct. Notification privacy, destinations, read state, default-OFF previews, alert deduplication, and both user experiences pass. Only after these tests pass may the enforcement activation step enable the launch configuration; activation in a live environment follows deployment authorization.

### Phase 2F — End-to-end verification and release readiness

**Primary decisions:** #23 plus regression coverage of all 30 decisions and all six workspace surfaces.

**Deliver:** complete connected workspace; resolved Phase 2D/2E dependencies; full role/program/security regression evidence; migration reconciliation and recovery notes; then-current App Store questionnaire/privacy/reviewer preparation; and an honest completion report with remaining external release actions.

**Exit gate:** every applicable check in Sections 6 and 7 passes. Validate on the supported iOS simulator/device workflow available to the project and inspect the actual rendered app. No surface may be declared complete based only on service code, mock data, screenshots of empty scaffolding, or a backend test suite. The release configuration has recruiting enforcement ON after its gates pass, and App Store readiness is checked before submission. Any unavailable external release check remains explicitly pending rather than represented as completed.

## 6. Acceptance test matrix

Use meaningful integration tests at the backend boundary alongside focused client/service tests and native UI walkthroughs. Include modified/direct clients in negative tests; a disabled button is not proof of authorization.

| Area | Required positive and negative scenarios |
| --- | --- |
| **Identity and roles** | Dedicated admin works; admin→coach approval fails; coach/athlete/parent→admin grant fails; concurrent grants cannot create mixed roles; pending/inactive/suspended coaches cannot recruit; reinstated coaches regain only still-authorized access. |
| **Programs** | One- and multi-program coaches work; explicit switching refreshes context; forged `program_id`, former membership, unverified program, and cross-program access fail; old in-flight responses cannot overwrite the new context. |
| **Media and data** | Verified legacy and new media play for an authorized caller; unauthenticated/unrelated/blocked callers cannot sign/read; missing objects are reported; external URLs are preserved; unsafe fields and broad helper/table access are denied; URL expiry/revocation limits are measured. |
| **Publication and blocks** | Unpublished/blocked athlete absent from Discover, detail, events, contact, board, counters, profile-view signals, alerts, and affected notifications; stale deep links fail; individual/program scope is consistent; unblock does not reactivate the old board entry. |
| **Board and contact** | Two eligible staff share prospects/stages/tags/assignments/activity; other programs and suspended staff fail; private notes remain author-only; contact denied before program save and available after valid save; blocked access remains denied. |
| **Limits and migration** | 10 tags/2,000 note characters accepted; 11 tags/2,001 characters rejected by client and backend; multibyte text handled consistently; duplicates and multi-program ambiguities preserved/reported; private notes never promoted; migration rerun/resume does not lose or duplicate data. |
| **Discover and events** | Core filters work separately and together; stable page traversal; correct units/radius/date windows; no sensitive coordinates or fields; program sport/gender is enforced; upcoming events respect profile access. |
| **Saved searches** | Owner/program isolation; alerts default OFF; explicit enable produces new-match alerts; repeated jobs/retries deduplicate; disable, suspension, membership removal, or blocking prevents subsequent unauthorized delivery. |
| **Messages and compliance** | Active verified recipients accepted; arbitrary UUID recipients rejected; allowed send succeeds; hard-blocked send fails; `needs_review` is distinct; altered templates/free-form exceptions fail; stale preflight cannot bypass final checks; direct writes are guarded. |
| **Durable audit and switch** | Rejected transaction leaves durable audit; no rejected message is delivered; retries correlate; audit failure cannot authorize a prohibited send; both enforcement switch states behave as designed; switch changes cannot disable baseline privacy/identity/block checks. |
| **Notifications and previews** | Coach and athlete/guardian lists/read states work; mark-all-read and badges reconcile; typed/legacy destinations route correctly; unauthorized/stale links show no private content; previews default OFF in all supported delivery surfaces; personal preferences remain isolated. |
| **Whole workspace** | Home, Discover, Board, Messages, Program, and Notifications are reachable and functional; quick actions navigate correctly; loading/empty/error/revoked states work; a complete discover→save→collaborate→message→notification journey succeeds. |

Use synthetic fixtures: two programs; two active verified coaches sharing one program; a coach in multiple programs; pending, inactive, and suspended coaches; a dedicated admin; published and unpublished athletes; a valid linked guardian; individually blocked and program-blocked relationships where supported; legacy media; ambiguous/duplicate board records; and allowed, hard-blocked, and review-needed rule evaluations. Do not expose real minors' data in test artifacts or screenshots.

The source does not settle every implementation detail, such as exact board-stage names, staff assignment permissions, alert cadence, or how `needs_review` is operationally reviewed. Inspect existing approved behavior and use it where consistent. Record routine implementation choices. Escalate a genuine policy ambiguity instead of silently widening permissions, inventing recruiting rules, or dropping the feature.

## 7. Definition of done and required handoff evidence

Claude Code's completion report must identify what was implemented, what was verified, and any remaining external dependencies. Include:

- [ ] All 30 decisions implemented or explicitly mapped to their intentional deferral/release gate; corrected #24 is enforced server-side.
- [ ] Full native **Home/Dashboard, Discover, Recruiting Board, Messages, Program, and Notifications** implemented and connected to real authorized data.
- [ ] Coach and athlete/guardian Notifications both verified; message previews and saved-search alerts default OFF.
- [ ] All six phase gates met; appropriate backend tests and iOS builds pass; native journeys inspected with screenshots or recorded walkthrough evidence where practical.
- [ ] Media and board migration reconciliation totals, unresolved-row handling, no-loss evidence, and recovery instructions supplied. Unresolved rows cannot grant access.
- [ ] No unrestricted athlete download, private-note sharing, free-text institution authorization, mixed-role admin account, or arbitrary pre-window free-text exception remains possible through supported access paths.
- [ ] Contact unlock, publication rules, suspension, block scope, no automatic board restoration, native deep-link authorization, and background-job authorization verified.
- [ ] Durable rejected-attempt audit proven; enforcement activation gate passed; intended launch configuration has enforcement ON and the admin kill switch remains available.
- [ ] App Store review/privacy/age-rating/demo-account preparation completed before submission, with credentials handled outside source control.
- [ ] Deferred Games Near Me and CSV export clearly recorded; no backend-only or scaffold-only completion claim.
- [ ] Final change summary, relevant file/migration list, test results, known limitations, and exact remaining deployment/submission actions delivered to the owner.

**Completion rule:** If only the backend/security portion is finished, report **“Phase 2 is incomplete — Coach Workspace implementation remains”** and continue through the remaining authorized phases. Do not stop there and declare success.

## 8. Repository investigation pointers

These paths were cited in the source conversation. Verify their current names and contents before relying on them; this handoff did not inspect or change the GitHub repository.

| Historical pointer | What to inspect |
| --- | --- |
| `supabase/setup.sql` | Historical coach-owned board uniqueness on `(coach_user_id, athlete_id)`, ownership policies, and missing tag/note limits; reconcile with later migrations. |
| `supabase/013-recruiting-messaging-enforcement.sql` | Existing preflight/enforcement behavior, admin switch, privileged functions, and the rejected-transaction audit rollback issue. |
| `TheHub/Services/CoachProgramService.swift` | Existing multi-program support and historical automatic choice of the most recently verified program. |
| `TheHub/Views/Main/MainTabView.swift` | Role routing, minimal Coach Mode navigation, and historical admin precedence; retain dedicated-admin behavior and build the full workspace. |
| `GAP-ANALYSIS.md` | Earlier parity assumptions, filter intentions, limits, and deferred event features; this decision record wins on conflicts. |
| `STATUS.md` | Current release state, reviewer/demo-account preparation, and coach-approval review notes. |

Also locate every media uploader/reader, bucket policy, coach-verification and role mutation path, block/report implementation, profile-view recorder, notification producer/consumer, scheduler, and recruiting-data access path. Security applies across the application, not only to newly added views.

