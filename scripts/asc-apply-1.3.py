#!/usr/bin/env python3
"""Apply the 1.3 submission metadata to App Store Connect.

Source of truth for the wording is docs/APPSTORE-SUBMISSION-1.3.md; this script
holds the same text so the form can be (re)applied in one command. Demo
credentials come from .secrets/demo-accounts.json (written by
scripts/seed-demo-accounts.py) and are never printed.

Usage: scripts/asc-apply-1.3.py [--dry-run]
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import asc  # noqa: E402  (scripts/asc.py)

ROOT = Path(__file__).resolve().parent.parent
VERSION_ID = "5d7d0a83-d7fc-4eed-9c83-29b60b386ad9"
LOCALIZATION_ID = "5ccfea50-c50d-4b41-b8b4-3fa7f0273d56"
REVIEW_DETAIL_ID = "9133211e-efbe-43a2-b82d-950321106c89"
AGE_RATING_ID = "5df4189a-e2b8-4832-a935-196050f235eb"

PROMOTIONAL_TEXT = (
    "Build your recruiting profile, track your NCAA eligibility, and hear from verified college coaches "
    "— in the app where every coach is approved before they can see you."
)

DESCRIPTION = """The Hub puts a high school basketball player's entire recruiting story in one place — and puts it in front of real, verified college coaches.

BUILD A PROFILE THAT GETS NOTICED
Add your stats, academics, highlight video links, action photos, and game schedule — or import the schedule straight from your school's calendar file. Each section shows what's complete so you always know what to add next. When you're ready, publish; only approved college coaches can see your profile.

KNOW WHO'S WATCHING
See profile views, saves, and messages from college programs as they happen, with a notification center that tells you which program it was. Insights show which schools are paying attention so you can focus your outreach.

OWN YOUR NCAA JOURNEY
A step-by-step eligibility tracker covers the Eligibility Center, core courses, transcripts, and amateurism certification — with the official recruiting rules for your class year, sourced and dated.

TARGET YOUR SCHOOLS
Keep a list of the programs you're pursuing, from first interest to committed, with notes on every conversation.

TALK TO COACHES — ON THE RULES
Read and reply to messages from approved college coaches. Every coach message is checked against the NCAA recruiting calendar before it sends, and block and report tools are built into every conversation.

BUILT FOR FAMILIES
Parents can manage a young athlete's profile, and publishing a minor's profile requires recorded guardian consent. A coach never sees an under-18 athlete's own phone number or email. You can delete your account and all of your data at any time.

FOR COLLEGE COACHES
Apply in the app. Once our team verifies your program, discover published athletes for your sport, keep a recruiting board your whole staff shares, set alerts for new prospects who match a saved search, and message athletes when the rules allow.

The Hub is free for athletes. Coach accounts are individually reviewed and approved before they can see any athlete."""

WHATS_NEW = """College coaches are now in The Hub.

FOR COACHES
• Coach Mode: apply in the app; once verified, discover published athletes for your program's sport, keep a shared recruiting board with your staff, save searches with alerts, and message athletes.
• Recruiting rules, enforced: messages are checked against the official NCAA recruiting calendar before they send.

FOR ATHLETES AND FAMILIES
• Notifications: a new bell shows saves, messages, and alerts, with mark-all-read and an optional message-preview setting.
• Edit Profile is now a checklist — every section collapses and shows what's complete.
• Import your game schedule from your school's calendar (.ics) file.
• Stronger privacy for minors: a coach never sees an under-18 athlete's own phone or email.
• Fixes: NCAA Journey no longer jumps when you switch divisions; My Colleges no longer scrolls sideways."""

REVIEW_NOTES = """The Hub is a free recruiting-profile platform for US high school basketball players (ages 13-18), their parents, and the college coaches who recruit them. Key context:

1. Sign-in is required. The demo account above is a fully populated ATHLETE (fictitious data). To see the coach side: COACH username {coach_email}, password {coach_password}. Both accounts are created fresh for each submission; the passwords always work.

2. Minor safety: publishing requires a date of birth, and any athlete under 18 must have recorded parent/guardian consent (name, email, timestamp) before the profile can be published - enforced in the database, not just the UI. A coach never receives an under-18 athlete's own phone or email; only guardian or club-coach details the family chose to list become visible, and only after the coach saves the athlete to their program's board. Coaches never receive date of birth, test scores, NCAA ID, exact location, or consent details.

3. Coach accounts cannot self-activate. Creating a coach account in the app only files an application; the coach sees a status screen with no athlete content until our staff manually verifies their affiliation with a specific college program and approves it. Only then does the account receive the coach role (enforced in the database). An approved coach can search published athletes for their program's sport and gender, save them to the program's shared recruiting board, set alerts on saved searches, and message them. Athletes and guardians are notified of saves, views, and messages with the program's name. Blocking a coach removes the athlete from that coach's results, board, and messages everywhere.

4. Recruiting-rule enforcement: before a coach's message sends, the server checks it against the official NCAA recruiting calendar for the athlete's class year and the coach's verified program (sources shown in-app with bylaw references and dates). A prohibited message is refused and the coach sees the rule and the date it opens. Athletes may always message a coach first.

5. User-generated content (photos, bios, messages) is moderated by our admin team. Every conversation has in-app Report and Block; reports notify all administrators and are reviewed within 24 hours.

6. Account deletion is in-app: More > Account > Delete Account (athletes), Program > Account > Delete Account (coaches). It removes the profile, photos, messages, consent records, and the login.

7. Athletes under 13 cannot create an account; sign-up blocks them and directs a parent or guardian to create and manage the profile.

--- Background previously requested by App Review (Guideline 2.1) ---

8. Setup: sign in with the athlete demo above. Athlete tabs: Home (activity, notification bell), Profile (edit, preview, publish, .ics schedule import), Colleges, Messages (Report and Block in every thread), More (NCAA Journey, Insights, Account, legal). Coach tabs (credentials in item 1): Home, Discover, Board, Messages, Program. New accounts need a working email for the confirmation link.

9. External services: Supabase (auth, Postgres, scheduled jobs, private file storage); Resend (transactional email); zippopotam.us (public ZIP-to-city lookup; only the ZIP is sent). No payments, ads, analytics SDKs, AI services, or push notifications (notifications are in-app only).

10. Distributed in the United States only; no regional differences. Not a regulated industry. No third-party protected material: college crests are generic letter monograms, and NCAA rule text is our own plain-English summary linking to the NCAA's published manual."""


def patch(path: str, type_: str, id_: str, attributes: dict, dry: bool):
    body = {"data": {"type": type_, "id": id_, "attributes": attributes}}
    if dry:
        safe = {k: ("<redacted>" if "assword" in k else v) for k, v in attributes.items()}
        print(f"DRY PATCH {path}\n{json.dumps(safe, indent=1)[:600]}…\n")
        return
    asc.call("PATCH", path, body)
    print(f"patched {path}: {', '.join(attributes)}")


def main():
    dry = "--dry-run" in sys.argv
    demo = json.loads((ROOT / ".secrets" / "demo-accounts.json").read_text())
    assert len(PROMOTIONAL_TEXT) <= 170, len(PROMOTIONAL_TEXT)
    assert len(DESCRIPTION) <= 4000 and len(WHATS_NEW) <= 4000
    notes = REVIEW_NOTES.format(coach_email=demo["coach"]["email"], coach_password=demo["coach"]["password"])
    assert len(notes) <= 4000, len(notes)

    patch(f"appStoreVersionLocalizations/{LOCALIZATION_ID}", "appStoreVersionLocalizations", LOCALIZATION_ID,
          {"promotionalText": PROMOTIONAL_TEXT, "description": DESCRIPTION, "whatsNew": WHATS_NEW}, dry)
    patch(f"appStoreReviewDetails/{REVIEW_DETAIL_ID}", "appStoreReviewDetails", REVIEW_DETAIL_ID,
          {"demoAccountRequired": True, "demoAccountName": demo["athlete"]["email"],
           "demoAccountPassword": demo["athlete"]["password"], "notes": notes}, dry)
    patch(f"appStoreVersions/{VERSION_ID}", "appStoreVersions", VERSION_ID, {"releaseType": "MANUAL"}, dry)
    # Social media: Apple's definition (July 2026) — "redistribute, amplify, or interact with user-generated
    # content through a social feed or similar discovery method". Coach Discover is a discovery method over
    # athlete-generated profiles, so Yes. socialMediaAgeRestricted requires adopting the Declared Age Range
    # API, which the app does not do → false. Rating stays 13+ via the existing override.
    patch(f"ageRatingDeclarations/{AGE_RATING_ID}", "ageRatingDeclarations", AGE_RATING_ID,
          {"socialMedia": True, "socialMediaAgeRestricted": False}, dry)


if __name__ == "__main__":
    main()
