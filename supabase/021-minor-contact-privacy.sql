-- =============================================================================
-- 021 — Minors' contact privacy (TestFlight feedback 2026-09-30, Danny):
--   "never explicitly show the phone number or email to a coach, especially
--    if the kid is a minor."
--
--   • athlete_is_minor(athlete): DOB missing or under 18 → true (fails closed).
--   • coach_athlete_detail: when the athlete is a minor the unlocked contact
--     payload omits athlete_email / athlete_phone and carries
--     athlete_contact_hidden = true so the client can say why. Guardian and
--     club-coach details still unlock on the board (the recruiting norm is to
--     reach a minor through an adult). Adults (18+) are unchanged.
--   • athlete_contacts coach RLS branch dropped: coaches read contacts only
--     through the RPC above, which is the single place the redaction lives.
--     Athletes/guardians (can_manage_athlete) unchanged.
--   • Stored athlete_phone for minors is nulled; the iOS editor no longer
--     collects it for minors.
--
-- Requires 017. Re-runnable.
-- =============================================================================

set check_function_bodies = off;

create or replace function public.athlete_is_minor(p_athlete_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select a.date_of_birth is null or a.date_of_birth > (current_date - interval '18 years')
     from public.athletes a where a.id = p_athlete_id),
    true);
$$;
revoke all on function public.athlete_is_minor(uuid) from public, anon;
grant execute on function public.athlete_is_minor(uuid) to authenticated;

create or replace function public.coach_athlete_detail(p_program_id uuid, p_athlete_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  prog public.recruiting_programs%rowtype;
  a public.athletes%rowtype;
  e public.program_board_entries%rowtype;
  contact_unlocked boolean;
  contact jsonb := null;
  note text;
begin
  perform public.coach_assert_program(p_program_id);
  select * into prog from public.recruiting_programs where id = p_program_id;

  select * into a from public.athletes
  where id = p_athlete_id and is_published and sport_gender = prog.sport_gender;
  if not found or public.coach_is_blocked(p_athlete_id) then
    raise exception 'not found';
  end if;

  select * into e from public.program_board_entries
    where program_id = p_program_id and athlete_id = p_athlete_id;
  contact_unlocked := found and e.removed_at is null;
  if contact_unlocked then
    if public.athlete_is_minor(p_athlete_id) then
      -- Minor: the athlete's own email/phone are never shown to a coach.
      select jsonb_build_object(
        'athlete_contact_hidden', true,
        'guardian_name', c.guardian_name, 'guardian_email', c.guardian_email, 'guardian_phone', c.guardian_phone,
        'club_coach_name', c.club_coach_name, 'club_coach_phone', c.club_coach_phone
      ) into contact
      from public.athlete_contacts c where c.athlete_id = p_athlete_id;
      contact := coalesce(contact, jsonb_build_object('athlete_contact_hidden', true));
    else
      select jsonb_build_object(
        'athlete_contact_hidden', false,
        'athlete_email', c.athlete_email, 'athlete_phone', c.athlete_phone,
        'guardian_name', c.guardian_name, 'guardian_email', c.guardian_email, 'guardian_phone', c.guardian_phone,
        'club_coach_name', c.club_coach_name, 'club_coach_phone', c.club_coach_phone
      ) into contact
      from public.athlete_contacts c where c.athlete_id = p_athlete_id;
    end if;
  end if;
  select body into note from public.coach_private_notes
    where coach_user_id = auth.uid() and athlete_id = p_athlete_id;

  return jsonb_build_object(
    'athlete', public.coach_athlete_card_json(a, null),
    'photos', coalesce((
      select jsonb_agg(jsonb_build_object('id', ph.id, 'storage_path', ph.storage_path, 'caption', ph.caption, 'created_at', ph.created_at)
                       order by ph.created_at)
      from public.athlete_photos ph where ph.athlete_id = a.id and ph.storage_path is not null), '[]'::jsonb),
    'videos', coalesce((
      select jsonb_agg(jsonb_build_object('id', v.id, 'url', v.url, 'title', v.title) order by v.created_at)
      from public.athlete_videos v where v.athlete_id = a.id), '[]'::jsonb),
    'upcoming_events', coalesce((
      select jsonb_agg(jsonb_build_object('id', ev.id, 'event_date', ev.event_date, 'event_time', ev.event_time,
                                          'opponent', ev.opponent, 'location', ev.location, 'notes', ev.notes, 'is_mayb', ev.is_mayb)
                       order by ev.event_date, ev.event_time)
      from public.athlete_events ev
      where ev.athlete_id = a.id
        and ev.event_date between (now() at time zone 'America/Chicago')::date
                              and (now() at time zone 'America/Chicago')::date + 30), '[]'::jsonb),
    'contact_unlocked', contact_unlocked,
    'contact', contact,
    'board', case when e.id is null then null else public.board_entry_json(e) end,
    'private_note', note,
    'program_id', p_program_id
  );
end;
$$;

-- Coaches no longer read athlete_contacts directly.
drop policy if exists "contacts select" on public.athlete_contacts;
create policy "contacts select" on public.athlete_contacts
  for select to authenticated
  using (public.can_manage_athlete(athlete_id));

-- Stored minors' phone numbers are removed (no longer collected for minors).
update public.athlete_contacts c
   set athlete_phone = null, updated_at = now()
 where c.athlete_phone is not null
   and public.athlete_is_minor(c.athlete_id);
