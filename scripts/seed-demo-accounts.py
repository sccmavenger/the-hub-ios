#!/usr/bin/env python3
"""Seed (or purge) the App Review demo accounts in the live Supabase project.

Creates a fully populated demo ATHLETE (a published, consented minor) and a
demo COACH approved into a fictitious verified program, saves the athlete to
that program's board, and seeds one thread so reviewers can see every tab.
Passwords are generated once and kept in .secrets/demo-accounts.json
(gitignored) — never printed.

Usage:
  scripts/seed-demo-accounts.py            # idempotent: creates what's missing, refreshes content
  scripts/seed-demo-accounts.py --purge    # remove both accounts and everything they own (after approval)

Needs: .secrets/supabase-service-key, .secrets/supabase-token (for scripts/db-query.sh), Pillow.
Why a script: docs/SUBMISSION-READINESS.md §2g/§2h — the demo roster is rebuilt
before every submission and purged after approval so fictitious athletes never
appear in real coaches' searches.
"""
import io
import json
import secrets
import subprocess
import sys
from datetime import date, timedelta
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SECRETS = ROOT / ".secrets"
SUPABASE_URL = "https://fnlufxhznqclpajyadcc.supabase.co"
ADMIN_USER_ID = "1551c699-50f4-4e14-8ca2-ff9cd4284470"   # dguilloryjr@msn.com — approves the coach

ATHLETE = {
    "email": "apple.review.athlete@summithoops.example",
    "full_name": "Jalen Brooks",
    "date_of_birth": "2009-02-14",          # 17 → minor: shows consent + contact redaction
    "grad_year": 2027,                      # junior: D1 electronic correspondence already open → a coach send succeeds
    "position": "Point Guard",
    "jersey_number": "3",
    "high_school": "Summit Prep Academy",
    "hometown": "Chesterfield",
    "state": "MO",
    "zip_code": "63017",
    "latitude": 38.6631, "longitude": -90.5771,
    "height_inches": 74, "weight_lbs": 175, "gpa": 3.6,
    "intended_major": "Sports Management",
    "instagram_handle": "jalen.brooks3",
    "bio": "6'2\" point guard who runs the floor and gets everyone involved. Averaged 14.2 points, 7.1 assists and 2.3 steals as a sophomore while leading Summit Prep to a district title. Shoots 38% from three, defends the other team's best guard, and keeps a 3.6 GPA.",
    "guardian_name": "Marcus Brooks",
    "guardian_email": "marcus.brooks@summithoops.example",
    "guardian_phone": "(636) 555-0147",
    "club_coach_name": "Coach Reggie Hall (STL Elite 17U)",
    "club_coach_phone": "(314) 555-0198",
}
COACH = {
    "email": "apple.review.coach@summithoops.example",
    "full_name": "Casey Morgan",
    "institution": "Summit State University",
    "governing_body": "NCAA", "division": "D1", "sport_gender": "mens",
    "coach_title": "Head Coach",
    "athletics_url": "https://summitstate.example/athletics",
}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def service_key() -> str:
    return (SECRETS / "supabase-service-key").read_text().strip()


def creds() -> dict:
    f = SECRETS / "demo-accounts.json"
    if f.exists():
        return json.loads(f.read_text())
    data = {
        "athlete": {"email": ATHLETE["email"], "password": "Review-" + secrets.token_urlsafe(9) + "!"},
        "coach": {"email": COACH["email"], "password": "Review-" + secrets.token_urlsafe(9) + "!"},
    }
    f.write_text(json.dumps(data, indent=2) + "\n")
    f.chmod(0o600)
    return data


def http(method: str, url: str, body=None, headers=None, raw=None):
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = Request(url, data=data, method=method)
    req.add_header("apikey", service_key())
    req.add_header("Authorization", f"Bearer {service_key()}")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urlopen(req) as r:
            payload = r.read()
            return json.loads(payload) if payload else {}
    except HTTPError as e:
        detail = e.read().decode()
        raise RuntimeError(f"HTTP {e.code} {method} {url}\n{detail}") from None


def sql(statement: str):
    """Run SQL through scripts/db-query.sh (management API); returns parsed JSON rows."""
    out = subprocess.run([str(ROOT / "scripts/db-query.sh")], input=statement, capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f"SQL failed:\n{out.stdout}\n{out.stderr}")
    text = out.stdout.strip()
    try:
        parsed = json.loads(text) if text else []
    except json.JSONDecodeError:
        if "message" in text and "Failed" in text:
            raise RuntimeError(text)
        return []
    # The management API reports SQL errors as a 200 with {"message": "Failed to run sql query: ..."}.
    if isinstance(parsed, dict) and "message" in parsed:
        raise RuntimeError(parsed["message"])
    return parsed


def q(value) -> str:
    """SQL literal."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def ensure_user(email: str, password: str, metadata: dict) -> str:
    rows = sql(f"select id from auth.users where email = {q(email)};")
    if rows:
        print(f"  user exists: {email}")
        # keep the password in the secrets file authoritative
        http("PUT", f"{SUPABASE_URL}/auth/v1/admin/users/{rows[0]['id']}", {"password": password})
        return rows[0]["id"]
    created = http("POST", f"{SUPABASE_URL}/auth/v1/admin/users",
                   {"email": email, "password": password, "email_confirm": True, "user_metadata": metadata})
    print(f"  created user: {email}")
    return created["id"]


def sign_in_works(email: str, password: str) -> bool:
    try:
        r = http("POST", f"{SUPABASE_URL}/auth/v1/token?grant_type=password", {"email": email, "password": password})
        return bool(r.get("access_token"))
    except RuntimeError:
        return False


# ---------------------------------------------------------------------------
# Images — sports-card graphics in the app palette (no third-party content)
# ---------------------------------------------------------------------------
def card(width: int, height: int, number: str, caption: str, seed: int) -> bytes:
    img = Image.new("RGB", (width, height))
    px = img.load()
    top = (14 + seed * 3, 18, 38 + seed * 5)
    bottom = (5, 6, 12)
    for y in range(height):
        t = y / max(1, height - 1)
        row = tuple(int(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
        for x in range(width):
            px[x, y] = row
    draw = ImageDraw.Draw(img)
    gold = (212, 175, 55)
    try:
        big = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", int(height * 0.42))
        small = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", int(height * 0.045))
    except OSError:
        big = small = ImageFont.load_default()
    draw.ellipse([width * 0.15, height * 0.12, width * 0.85, height * 0.12 + width * 0.7], outline=gold, width=max(4, width // 90))
    tw = draw.textlength(number, font=big)
    draw.text(((width - tw) / 2, height * 0.12 + width * 0.35 - height * 0.24), number, font=big, fill=gold)
    plate_top = int(height * 0.82)
    draw.rectangle([0, plate_top, width, height], fill=(20, 22, 30))
    cw = draw.textlength(caption, font=small)
    draw.text(((width - cw) / 2, plate_top + (height - plate_top) * 0.35), caption, font=small, fill=(235, 235, 240))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=88)
    return buf.getvalue()


def upload(path: str, data: bytes):
    http("POST", f"{SUPABASE_URL}/storage/v1/object/athlete-media/{path}", raw=data,
         headers={"Content-Type": "image/jpeg", "x-upsert": "true"})


# ---------------------------------------------------------------------------
# Seed
# ---------------------------------------------------------------------------
def seed():
    c = creds()
    print("1. Users")
    athlete_uid = ensure_user(c["athlete"]["email"], c["athlete"]["password"],
                              {"signup_role": "athlete", "full_name": ATHLETE["full_name"], "date_of_birth": ATHLETE["date_of_birth"]})
    coach_uid = ensure_user(c["coach"]["email"], c["coach"]["password"],
                            {"signup_role": "coach", "full_name": COACH["full_name"], "institution": COACH["institution"],
                             "governing_body": COACH["governing_body"], "division": COACH["division"],
                             "sport_gender": COACH["sport_gender"], "coach_title": COACH["coach_title"],
                             "athletics_url": COACH["athletics_url"]})

    rows = sql(f"select id from public.athletes where user_id = {q(athlete_uid)};")
    if not rows:
        raise RuntimeError("athlete row was not created by handle_new_user")
    athlete_id = rows[0]["id"]

    print("2. Athlete profile, contacts, consent")
    a = ATHLETE
    sql(f"""
    update public.athletes set
      full_name = {q(a['full_name'])}, date_of_birth = {q(a['date_of_birth'])}, grad_year = {a['grad_year']},
      position = {q(a['position'])}, jersey_number = {q(a['jersey_number'])}, high_school = {q(a['high_school'])},
      hometown = {q(a['hometown'])}, state = {q(a['state'])}, zip_code = {q(a['zip_code'])},
      latitude = {a['latitude']}, longitude = {a['longitude']},
      height_inches = {a['height_inches']}, weight_lbs = {a['weight_lbs']}, gpa = {a['gpa']},
      intended_major = {q(a['intended_major'])}, instagram_handle = {q(a['instagram_handle'])}, bio = {q(a['bio'])},
      sport_gender = 'mens',
      guardian_consent_at = coalesce(guardian_consent_at, now()),
      guardian_consent_name = {q(a['guardian_name'])}, guardian_consent_email = {q(a['guardian_email'])}
    where id = {q(athlete_id)};
    insert into public.athlete_contacts (athlete_id, athlete_email, guardian_name, guardian_email, guardian_phone, club_coach_name, club_coach_phone)
    values ({q(athlete_id)}, {q(a['email'])}, {q(a['guardian_name'])}, {q(a['guardian_email'])}, {q(a['guardian_phone'])}, {q(a['club_coach_name'])}, {q(a['club_coach_phone'])})
    on conflict (athlete_id) do update set athlete_email = excluded.athlete_email, athlete_phone = null,
      guardian_name = excluded.guardian_name, guardian_email = excluded.guardian_email, guardian_phone = excluded.guardian_phone,
      club_coach_name = excluded.club_coach_name, club_coach_phone = excluded.club_coach_phone, updated_at = now();
    """)

    print("3. Schedule, colleges, NCAA readiness")
    today = date.today()
    games = [
        (today + timedelta(days=3), "7:00 PM", "Ladue Rams", "Summit Prep Gym · Chesterfield, MO", False),
        (today + timedelta(days=9), "6:30 PM", "CBC Cadets", "CBC High School · Town and Country, MO", False),
        (today + timedelta(days=16), "5:00 PM", "Chaminade Red Devils", "Chaminade · Creve Coeur, MO", False),
        (today + timedelta(days=23), None, "STL Elite 17U — Gateway Showcase", "Chaifetz Arena · St. Louis, MO", True),
    ]
    values = ",".join(
        f"({q(athlete_id)}, {q(d.isoformat())}, {q(t)}, {q(o)}, {q(l)}, {q(m)})" for d, t, o, l, m in games
    )
    colleges = [
        ("Saint Louis University", "D1", "MO", "interested", "Camp invite received in June."),
        ("Drake University", "D1", "IA", "contacted", "Assistant coach watched the district final."),
        ("Washington University in St. Louis", "D3", "MO", "visiting", "Unofficial visit in September — loved the campus."),
    ]
    cvalues = ",".join(f"({q(athlete_id)}, {q(n)}, {q(d)}, {q(s)}, {q(st)}, {q(no)})" for n, d, s, st, no in colleges)
    sql(f"""
    delete from public.athlete_events where athlete_id = {q(athlete_id)};
    insert into public.athlete_events (athlete_id, event_date, event_time, opponent, location, is_mayb) values {values};
    delete from public.athlete_college_interests where athlete_id = {q(athlete_id)};
    insert into public.athlete_college_interests (athlete_id, college_name, division, state, status, notes) values {cvalues};
    insert into public.athlete_ncaa_readiness (athlete_id, intended_division, ec_account_status, core_courses_completed, estimated_core_gpa, transcript_sent, amateurism_done, final_cert_requested, source)
    values ({q(athlete_id)}, 'D1', 'profile_page', 9, 3.5, false, false, false, 'self_reported')
    on conflict (athlete_id) do update set intended_division = 'D1', ec_account_status = 'profile_page', core_courses_completed = 9, estimated_core_gpa = 3.5, updated_at = now();
    """)

    print("4. Photos")
    profile_path = f"{athlete_uid}/profile.jpg"
    upload(profile_path, card(900, 900, "3", "JALEN BROOKS · PG · 2027", 0))
    gallery = [
        ("gallery/01-drive.jpg", "Driving baseline vs. Ladue"),
        ("gallery/02-three.jpg", "Corner three, district final"),
        ("gallery/03-defense.jpg", "On-ball pressure, STL Elite"),
        ("gallery/04-huddle.jpg", "Summit Prep huddle"),
    ]
    photo_values = []
    for i, (name, caption) in enumerate(gallery, start=1):
        path = f"{athlete_uid}/{name}"
        upload(path, card(1200, 1500, "3", caption.upper(), i))
        photo_values.append(f"({q(athlete_id)}, {q(path)}, {q(caption)})")
    sql(f"""
    delete from public.athlete_photos where athlete_id = {q(athlete_id)};
    insert into public.athlete_photos (athlete_id, storage_path, caption) values {",".join(photo_values)};
    update public.athletes set profile_photo_path = {q(profile_path)}, profile_photo_url = null where id = {q(athlete_id)};
    """)

    print("5. Publish")
    sql(f"update public.athletes set is_published = true where id = {q(athlete_id)};")

    print("6. Coach approval (as admin)")
    pending = sql(f"select id, status from public.coach_requests where user_id = {q(coach_uid)};")
    if not pending:
        raise RuntimeError("coach_requests row was not created by handle_new_user")
    if pending[0]["status"] != "approved":
        program = json.dumps({
            "institution_name": COACH["institution"], "governing_body": COACH["governing_body"],
            "division": COACH["division"], "sport": "basketball", "sport_gender": COACH["sport_gender"],
            "athletics_url": COACH["athletics_url"],
        })
        sql(f"""
        do $$
        begin
          perform set_config('request.jwt.claims', json_build_object('sub', '{ADMIN_USER_ID}', 'role', 'authenticated')::text, true);
          perform set_config('request.jwt.claim.sub', '{ADMIN_USER_ID}', true);
          set local role authenticated;
          perform public.approve_coach_request({q(pending[0]['id'])}::uuid, null, {q(program)}::jsonb, 'head_coach', {q(COACH['coach_title'])}, 'Demo program for App Review (fictitious).');
          reset role;
        end $$;
        """)
        print("  approved into a new fictitious program")
    else:
        print("  already approved")
    prog = sql(f"select program_id from public.coach_program_memberships where coach_user_id = {q(coach_uid)} and status = 'verified' limit 1;")
    program_id = prog[0]["program_id"]

    print("7. Board save, thread, profile views")
    sql(f"""
    do $$
    declare r jsonb;
    begin
      -- athlete writes first (always allowed)
      perform set_config('request.jwt.claims', json_build_object('sub', '{athlete_uid}', 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', '{athlete_uid}', true);
      set local role authenticated;
      if not exists (select 1 from public.messages where athlete_id = {q(athlete_id)} and coach_user_id = {q(coach_uid)}) then
        insert into public.messages (athlete_id, coach_user_id, sender_user_id, body)
        values ({q(athlete_id)}, {q(coach_uid)}, {q(athlete_uid)}, 'Hi Coach Morgan — I''m Jalen Brooks, a 2027 point guard at Summit Prep. I''d love to learn more about your program and when I could visit campus.');
      end if;
      reset role;

      -- coach saves to the board and replies through the rules-checked RPC
      perform set_config('request.jwt.claims', json_build_object('sub', '{coach_uid}', 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', '{coach_uid}', true);
      set local role authenticated;
      perform public.board_save_athlete({q(program_id)}::uuid, {q(athlete_id)}::uuid, 'evaluating');
      if not exists (select 1 from public.messages where athlete_id = {q(athlete_id)} and coach_user_id = {q(coach_uid)} and sender_user_id = {q(coach_uid)}) then
        r := public.send_coach_message({q(program_id)}::uuid, {q(athlete_id)}::uuid, 'Jalen — thanks for reaching out. We saw the district final film and like how you run a team. Our staff will be at the Gateway Showcase; let''s set up a campus visit this fall.');
        raise notice 'send result %', r ->> 'status';
      end if;
      reset role;
    end $$;
    """)
    sql(f"""
    delete from public.athlete_profile_views where athlete_id = {q(athlete_id)} and viewer_user_id = {q(coach_uid)};
    insert into public.athlete_profile_views (athlete_id, viewer_user_id, viewer_role, viewer_label, created_at)
    select {q(athlete_id)}, {q(coach_uid)}, 'coach', {q(COACH['institution'] + " Men's Basketball")}, now() - (n || ' days')::interval
    from generate_series(1, 6) n;
    """)

    print("8. Verify sign-in")
    ok_a = sign_in_works(c["athlete"]["email"], c["athlete"]["password"])
    ok_c = sign_in_works(c["coach"]["email"], c["coach"]["password"])
    counts = sql(f"""
    select (select count(*) from public.athlete_photos where athlete_id = {q(athlete_id)}) photos,
           (select count(*) from public.athlete_events where athlete_id = {q(athlete_id)}) events,
           (select count(*) from public.athlete_college_interests where athlete_id = {q(athlete_id)}) colleges,
           (select count(*) from public.messages where athlete_id = {q(athlete_id)}) messages,
           (select count(*) from public.program_board_entries where athlete_id = {q(athlete_id)} and removed_at is null) board,
           (select is_published from public.athletes where id = {q(athlete_id)}) published,
           (select count(*) from public.user_roles where user_id = {q(coach_uid)} and role = 'coach') coach_role;
    """)
    print("  athlete sign-in:", "OK" if ok_a else "FAILED", "| coach sign-in:", "OK" if ok_c else "FAILED")
    print("  counts:", counts[0] if counts else counts)
    print("Credentials are in .secrets/demo-accounts.json (not printed).")
    if not (ok_a and ok_c):
        sys.exit(1)


# ---------------------------------------------------------------------------
# Purge (after approval)
# ---------------------------------------------------------------------------
def purge():
    emails = [ATHLETE["email"], COACH["email"]]
    users = sql(f"select id, email from auth.users where email in ({','.join(q(e) for e in emails)});")
    if not users:
        print("nothing to purge")
        return
    ids = [u["id"] for u in users]
    idlist = ",".join(q(i) for i in ids)
    # storage objects first (service role, Storage API)
    for uid in ids:
        try:
            objs = http("POST", f"{SUPABASE_URL}/storage/v1/object/list/athlete-media",
                        {"prefix": uid, "limit": 1000, "offset": 0}) or []
            names = [f"{uid}/{o['name']}" for o in objs if o.get("id")]
            sub = http("POST", f"{SUPABASE_URL}/storage/v1/object/list/athlete-media",
                       {"prefix": f"{uid}/gallery", "limit": 1000, "offset": 0}) or []
            names += [f"{uid}/gallery/{o['name']}" for o in sub if o.get("id")]
            if names:
                http("DELETE", f"{SUPABASE_URL}/storage/v1/object/athlete-media", {"prefixes": names})
                print(f"  removed {len(names)} storage objects for {uid}")
        except RuntimeError as e:
            print("  storage cleanup warning:", e)
    sql(f"""
    delete from public.program_board_entries where athlete_id in (select id from public.athletes where user_id in ({idlist}))
       or saved_by in ({idlist}) or assigned_to in ({idlist});
    delete from public.notifications where user_id in ({idlist});
    delete from public.recruiting_programs p where p.id in (select program_id from public.coach_program_memberships where coach_user_id in ({idlist}))
       and not exists (select 1 from public.coach_program_memberships m where m.program_id = p.id and m.coach_user_id not in ({idlist}));
    delete from auth.users where id in ({idlist});
    """)
    remaining = sql(f"select count(*) c from auth.users where id in ({idlist});")
    print("purged:", [u["email"] for u in users], "remaining:", remaining[0]["c"] if remaining else "?")
    f = SECRETS / "demo-accounts.json"
    if f.exists():
        f.unlink()
        print("removed .secrets/demo-accounts.json")


if __name__ == "__main__":
    if "--purge" in sys.argv:
        purge()
    else:
        seed()
