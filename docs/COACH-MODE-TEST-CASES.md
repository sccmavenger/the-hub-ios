# Coach Mode — Device Test Cases (Release 2.0 + 2.1)

Manual pass for the Coach Workspace on a real device. Everything below is
covered by SQL and Swift tests for *logic*; this script is about what a human
sees and taps. Run as three people: **Admin** (`dguilloryjr@msn.com`),
**Coach** (`tstark@mailinator.com`, University Of IronMan, men's), and
**Athlete** (your own profile, published, men's). Where a step says "expect",
anything else is a bug — note the screen and what you saw.

Setup once: install the latest build on the phone, sign out, and have both the
coach and athlete passwords handy. For messaging steps the athlete must be
published and the same gender as the coach's program (men's).

## A. Coach entry (Phase 1 + 2B)

| # | Steps | Expect |
|---|-------|--------|
| A1 | Sign in as Coach. | Lands on **Coach Home** with the program card (University Of IronMan · Men's Basketball · D-label), "Verified …" date, board tiles, quick actions. Five tabs: Home, Discover, Board, Messages, Program. |
| A2 | Pull to refresh on Home. | Spinner, numbers reload, no layout jump. |
| A3 | Program tab → scroll. | Program card, staff roster with you listed, Account link, legal links, Sign Out. |
| A4 | Admin: suspend the coach's membership (Coaches tab → detail → Suspend). Coach: pull to refresh. | Coach is routed to the **access paused** screen; no athlete content anywhere. Restore and refresh: tabs return. |

## B. Discover (2C)

| # | Steps | Expect |
|---|-------|--------|
| B1 | Discover tab with no filters. | Your athlete's card appears (photo, name, class, position, school line). No DOB, GPA-only-if-set, no guardian info on the card. |
| B2 | Search by part of the athlete's name; clear it. | Results filter, then restore. |
| B3 | Filters: set grad year to the athlete's year → Apply. Then set a year that doesn't match. | Card present, then "no athletes" empty state. Filter button shows the active count. |
| B4 | Filters: ZIP + 25 mi radius near the athlete. | Card shows a distance. Radius 250 mi from far away → empty. |
| B5 | Filters: "Playing within next 7 days" with a game scheduled in that window. | Card shows the next game date. |
| B6 | Save current filters as "Test search". Open Saved Searches, run it, rename it, then delete it. | Each action reflects immediately; running applies the chips to the active-filter bar. |
| B7 | Athlete: unpublish the profile. Coach: pull to refresh Discover. | Athlete disappears. Republish → returns. |

## C. Athlete detail + contact unlock (2C, 2.1 F2)

| # | Steps | Expect |
|---|-------|--------|
| C1 | Tap the athlete card. | Detail with photo pager (swipe), videos, upcoming games, **Contact card locked** ("Save to Recruiting Board to unlock"). |
| C2 | Tap **Save to board**. | Stage chip bar appears (Watching), tag editor, assignee, private note. Contact card unlocks. |
| C3 | Contact card for a **minor** athlete (your profile has a 2012 DOB). | Shows the under-18 note; guardian / club coach rows only if entered; **no athlete email or phone rows**. |
| C4 | Athlete: Profile → Contact Info. | Caption says coaches never see a minor's email/phone; **no Athlete Phone field**. Set DOB to 18+ → field appears. Set back. |
| C5 | Athlete: Dashboard → Saved by. | Shows "University Of IronMan · Tony Stark" (program label, not the application claim). Athlete also has a notification "… saved your profile". |
| C6 | Coach: Report athlete → pick a reason → submit. | Confirmation; nothing else changes. |

## D. Recruiting Board (2D)

| # | Steps | Expect |
|---|-------|--------|
| D1 | Board tab. | Stage counts across the top; the saved athlete under Watching. "Assigned to me" filter available. |
| D2 | Open the entry → change stage to Evaluating → add tags "shooter", "2027" → assign to yourself → write a private note → back. | Board reflects stage and tags; activity log lists stage, tags, assignee (not the note). |
| D3 | Enter 11 tags, or a tag longer than 30 characters. | Refused with a clear message at 10 tags / 30 chars. |
| D4 | Remove the athlete from the board → Discover → card. | Card shows no stage; contact card locks again. Board → "Show removed" → Restore. |
| D5 | Coach Home. | Tiles match the board (Evaluating 1), "Assigned to you 1", recent activity lists your actions. |

## E. Blocks (W3)

| # | Steps | Expect |
|---|-------|--------|
| E1 | Athlete: Messages → the coach's thread → Block coach. Coach: pull to refresh Discover, Board, Messages. | Athlete gone from Discover and Board (teammates would still see it), thread gone from inbox, detail says not found if reopened. |
| E2 | Athlete: Account → Blocked People → Unblock. Coach: refresh. | Everything returns, board entry intact. |

## F. Messages (2E) — enforcement is ON

| # | Steps | Expect |
|---|-------|--------|
| F1 | Coach: athlete detail → **Message**. | Thread opens with the rule preflight at the top: badge, plain-English rule, source link, program label in the header. |
| F2 | If the preflight is **Not yet** (hard block — your 2030-grad athlete will be): type a message. | **Send is disabled** with the rule and start date shown. Nothing is sent; no error toast. |
| F3 | If **Needs review** (e.g. a D2 or NAIA program): send a short message. | Sent with a visible warning that the rule couldn't be fully verified. |
| F4 | Athlete: Messages tab. | Thread from "University Of IronMan · Tony Stark"; reply works; the athlete side shows **You can reach out** for its own outreach. |
| F5 | Coach: Messages tab. | One row per athlete, last message, unread count; opening clears unread. |
| F6 | Admin → Admin Settings. | Rules engine ON, enforcement ON (display mirrors the server). Toggling is possible but **leave it ON**. |

## G. Notifications + alerts (2F)

| # | Steps | Expect |
|---|-------|--------|
| G1 | Athlete sends a message to the coach. Coach: Home bell. | Badge count increments; bell opens the center with "New message from <athlete>" (body hidden unless previews are on). Tap → opens the thread. |
| G2 | Coach: Account → Notifications → **Show message previews** ON. Athlete sends another message. | New notification includes the first line of the message. Turn it back OFF. |
| G3 | Notifications center → swipe a row → Mark read; then **Mark all read**. | Dot and badge clear; counts persist after relaunch. |
| G4 | Coach: Discover → Saved Searches → turn **Alerts** on for a search matching your athlete. Athlete: unpublish, wait for the next :15 past the hour, republish, wait for the following :15. | First run after enabling sends nothing (baseline). After the republish run: one notification "1 new athlete matches “<name>”". Tapping switches to Discover with that search applied. |
| G5 | Athlete: Dashboard bell after being saved to a board. | "<Program> saved your profile" → tap opens Bookmarks. |

## H. Regressions from TestFlight feedback (build 1.3)

| # | Steps | Expect |
|---|-------|--------|
| H1 | Athlete: More → NCAA Journey → tap D1, D2, D3, Unsure repeatedly. | Pills are at the top; content below changes without the page jumping. |
| H2 | Athlete: My Colleges tab → drag sideways, hard, both directions. Also NCAA Journey. | No horizontal movement at all, not even a rubber-band; long source links wrap as text with the arrow inline. |
| H3 | Athlete: Profile tab. | Sections collapsed with "x of y" chips and "N of 12 sections complete"; Expand all / Collapse all works; tapping a header toggles with animation. |
| H4 | Profile → Game Schedule → Import from a calendar file → pick an .ics (export one from the school site or Apple Calendar). | Review list with dates, opponents, locations; past games and duplicates pre-unchecked; Import adds them; re-import skips duplicates. |
| H5 | Profile → Game Schedule → trash icon on a game. Also: Highlight Videos trash, My Colleges trash, coach "Remove from board", "Block" in a thread. | A centered alert naming the item, with Delete/Remove/Block and Cancel. No popover at the top of the screen. |
| H6 | Home → Profile Preview → share icon (top right, appears after a moment). | Share sheet with a 4:5 card: photo, name, school line, chips, The Hub footer, plus a one-line message ending in thehubsh.net. Send it to yourself in Messages and check the image renders. |

## I. Admin review loop (Phase 1)

| # | Steps | Expect |
|---|-------|--------|
| I1 | New coach signs up with a mailinator address. Admin: Coaches tab. | Pending row with claims. Request info → applicant sees the message and can edit/resubmit. Reject → applicant sees reason. |
| I2 | Approve into the existing program. | Applicant gains Coach Mode on next refresh; staff roster lists both coaches; the second coach sees the same board. |

Record results in this file's PR or in `docs/FEEDBACK-BACKLOG.md` if they
turn into fixes.
